#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "scripts" / "refresh-cargo-git-sources.py"
SPEC = importlib.util.spec_from_file_location("refresh_cargo_git_sources", HELPER_PATH)
HELPER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(HELPER)


LOCK = textwrap.dedent(
    """
    version = 3

    [[package]]
    name = "registry-only"
    version = "1.0.0"
    source = "registry+https://github.com/rust-lang/crates.io-index"

    [[package]]
    name = "librespot-audio"
    version = "0.8.0"
    source = "git+https://github.com/crmne/librespot?rev=1111111#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    [[package]]
    name = "librespot-core"
    version = "0.8.0"
    source = "git+https://github.com/crmne/librespot?rev=1111111#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    [[package]]
    name = "projectm-sys"
    version = "1.2.3"
    source = "git+https://github.com/crmne/projectm-rs?rev=2222222#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    """
).strip()


class RefreshCargoGitSourcesTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("nix") and shutil.which("git"), "requires Nix and Git")
    def test_prefetch_hash_includes_nested_submodules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(repo, *args):
                return subprocess.run(
                    ["git", "-C", str(repo), *args],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                ).stdout.strip()

            env = {
                "GIT_CONFIG_COUNT": "3",
                "GIT_CONFIG_KEY_0": "protocol.file.allow",
                "GIT_CONFIG_VALUE_0": "always",
                "GIT_CONFIG_KEY_1": "user.name",
                "GIT_CONFIG_VALUE_1": "Updater Test",
                "GIT_CONFIG_KEY_2": "user.email",
                "GIT_CONFIG_VALUE_2": "test@example.invalid",
            }
            with patch.dict(os.environ, env):
                child = None
                for name in ("nested", "library", "workspace"):
                    repo = root / name
                    repo.mkdir()
                    git(repo, "init", "-q")
                    (repo / "source.txt").write_text(name + "\n")
                    if child is not None:
                        git(repo, "submodule", "add", "-q", child.as_uri(), "vendor")
                        git(repo, "submodule", "update", "--init", "--recursive")
                    git(repo, "add", ".")
                    git(repo, "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
                    child = repo

                expected_tree = root / "expected"
                shutil.copytree(repo, expected_tree, ignore=shutil.ignore_patterns(".git"))
                expected_hash = subprocess.run(
                    ["nix", "hash", "path", str(expected_tree)],
                    check=True,
                    stdout=subprocess.PIPE,
                    text=True,
                ).stdout.strip()
                actual_hash = HELPER.prefetch_git(repo.as_uri(), git(repo, "rev-parse", "HEAD"))

            self.assertEqual(actual_hash, expected_hash)

    def test_rejects_conflicting_repositories_for_same_revision(self):
        lock = LOCK + textwrap.dedent(
            """

            [[package]]
            name = "collision"
            version = "1.0.0"
            source = "git+https://github.com/example/other#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            """
        )
        with tempfile.TemporaryDirectory() as directory:
            lock_file = Path(directory) / "Cargo.lock"
            lock_file.write_text(lock)
            with self.assertRaisesRegex(ValueError, "same revision"):
                HELPER.read_git_sources(lock_file)

    def test_rejects_duplicate_output_hash_keys_for_different_revisions(self):
        lock = textwrap.dedent(
            """
            version = 3
            [[package]]
            name = "duplicate"
            version = "1.0.0"
            source = "git+https://github.com/example/one#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            [[package]]
            name = "duplicate"
            version = "1.0.0"
            source = "git+https://github.com/example/two#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            """
        )
        with tempfile.TemporaryDirectory() as directory:
            lock_file = Path(directory) / "Cargo.lock"
            lock_file.write_text(lock)
            with self.assertRaisesRegex(ValueError, "outputHashes key"):
                HELPER.read_git_sources(lock_file)

    def test_rejects_git_source_without_resolved_revision(self):
        lock = textwrap.dedent(
            """
            version = 3
            [[package]]
            name = "broken"
            version = "1.0.0"
            source = "git+https://github.com/example/broken?branch=main"
            """
        )
        with tempfile.TemporaryDirectory() as directory:
            lock_file = Path(directory) / "Cargo.lock"
            lock_file.write_text(lock)
            with self.assertRaisesRegex(ValueError, "resolved revision"):
                HELPER.read_git_sources(lock_file)

    def test_rejects_fake_hash(self):
        with self.assertRaisesRegex(ValueError, "fake hash"):
            HELPER.validate_hash("sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")

    def test_rejects_malformed_hash(self):
        with self.assertRaisesRegex(ValueError, "unusable"):
            HELPER.validate_hash("sha256-too-short")


class EnsureReleaseTests(unittest.TestCase):
    def run_script(self, release_exists):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "gh.log"
            fake_gh = root / "gh"
            fake_gh.write_text(
                textwrap.dedent(
                    """#!/usr/bin/env bash
                    printf '%s\\n' "$*" >> "$GH_LOG"
                    if [ "$1 $2" = "release view" ]; then
                      [ "$RELEASE_EXISTS" = true ]
                    fi
                    """
                )
            )
            fake_gh.chmod(0o755)
            env = os.environ | {
                "PATH": f"{root}:{os.environ['PATH']}",
                "GH_LOG": str(log),
                "RELEASE_EXISTS": "true" if release_exists else "false",
            }
            subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts" / "ensure-release.sh"),
                    "0.5.0",
                    "v0.5.0",
                ],
                check=True,
                env=env,
            )
            return log.read_text().splitlines()

    def test_existing_release_is_a_no_op(self):
        self.assertEqual(self.run_script(True), ["release view v0.5.0"])

    def test_missing_release_is_created_for_main(self):
        calls = self.run_script(False)
        self.assertEqual(calls[0], "release view v0.5.0")
        self.assertIn("release create v0.5.0 --target main", calls[1])
        self.assertIn("upstream: https://github.com/crmne/fastpotify/releases/tag/v0.5.0", calls[1])


if __name__ == "__main__":
    unittest.main()
