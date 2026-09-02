#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
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

SOURCE_HASH = "sha256-" + ("d" * 43) + "="

PACKAGE_NIX = textwrap.dedent(
    """
    let
      projectmRsSource = fetchgit {
        url = "https://github.com/old/projectm-rs";
        rev = "old-revision";
        fetchSubmodules = true;
        hash = "sha256-old";
      };
    in
    rustPlatform.buildRustPackage {
      version = "0.4.1";
      src = fetchFromGitHub {
        owner = "crmne";
        repo = "fastpotify";
        rev = "v${version}";
        hash = "sha256-old-source";
      };
      cargoLock = {
        lockFile = ./Cargo.lock;
        outputHashes = {
          "obsolete-1.0.0" = "sha256-obsolete";
        };
      };
    }
    """
).strip() + "\n"


class RefreshCargoGitSourcesTests(unittest.TestCase):
    def test_groups_workspace_crates_and_refreshes_projectm_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock_file = root / "Cargo.lock"
            package_file = root / "package.nix"
            lock_file.write_text(LOCK)
            package_file.write_text(PACKAGE_NIX)

            calls = []

            def fake_prefetch(url, rev, *, fetch_submodules=False):
                calls.append((url, rev, fetch_submodules))
                suffix = "submodules" if fetch_submodules else rev[0]
                return f"sha256-{suffix}"

            with patch.object(HELPER, "prefetch_git", side_effect=fake_prefetch):
                HELPER.refresh(
                    lock_file,
                    package_file,
                    version="0.5.0",
                    source_hash=SOURCE_HASH,
                )

            updated = package_file.read_text()
            self.assertIn('version = "0.5.0";', updated)
            self.assertIn(f'hash = "{SOURCE_HASH}";', updated)
            self.assertNotIn("sha256-old-source", updated)
            self.assertIn('"librespot-audio-0.8.0" = "sha256-a";', updated)
            self.assertNotIn("librespot-core-0.8.0", updated)
            self.assertIn('"projectm-sys-1.2.3" = "sha256-b";', updated)
            self.assertNotIn("obsolete-1.0.0", updated)
            self.assertNotIn("registry-only", updated)
            self.assertIn('url = "https://github.com/crmne/projectm-rs";', updated)
            self.assertIn('rev = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";', updated)
            self.assertIn('hash = "sha256-submodules";', updated)
            self.assertEqual(
                calls,
                [
                    (
                        "https://github.com/crmne/librespot",
                        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        False,
                    ),
                    (
                        "https://github.com/crmne/projectm-rs",
                        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        False,
                    ),
                    (
                        "https://github.com/crmne/projectm-rs",
                        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        True,
                    ),
                ],
            )

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
