#!/usr/bin/env python3
"""Refresh Nix hashes for every git dependency in a Cargo lockfile."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tomllib
from typing import NamedTuple
from urllib.parse import urlsplit, urlunsplit


FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
SRI_HASH = re.compile(r"^sha256-[A-Za-z0-9+/]{43}=$")


class GitSource(NamedTuple):
    url: str
    rev: str
    packages: tuple[tuple[str, str], ...]

    @property
    def output_hash_key(self) -> str:
        name, version = min(self.packages)
        return f"{name}-{version}"


def validate_hash(value: str) -> str:
    if value == FAKE_HASH:
        raise ValueError("refusing to write the Nix fake hash")
    if not SRI_HASH.fullmatch(value):
        raise ValueError(f"unusable Nix SRI hash: {value!r}")
    return value


def read_git_sources(lock_file: Path) -> list[GitSource]:
    lock = tomllib.loads(lock_file.read_text())
    by_revision: dict[str, tuple[str, list[tuple[str, str]]]] = {}

    for package in lock.get("package", []):
        source = package.get("source", "")
        if not source.startswith("git+"):
            continue

        parsed = urlsplit(source.removeprefix("git+"))
        if not parsed.fragment:
            raise ValueError(
                f"git package {package['name']!r} has no resolved revision in Cargo.lock"
            )
        url = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, "", ""))
        rev = parsed.fragment
        identity = (package["name"], package["version"])

        if rev in by_revision and by_revision[rev][0] != url:
            raise ValueError(
                f"git dependencies use the same revision {rev} from different repositories"
            )
        by_revision.setdefault(rev, (url, []))[1].append(identity)

    sources = sorted(
        (
            GitSource(url, rev, tuple(packages))
            for rev, (url, packages) in by_revision.items()
        ),
        key=lambda source: source.output_hash_key,
    )
    keys = [source.output_hash_key for source in sources]
    if len(keys) != len(set(keys)):
        raise ValueError(
            "different git revisions require the same cargoLock.outputHashes key"
        )
    return sources


def prefetch_git(url: str, rev: str, *, fetch_submodules: bool = False) -> str:
    configured = os.environ.get("NIX_PREFETCH_GIT")
    command = (
        shlex.split(configured)
        if configured
        else [
            "nix",
            "run",
            f"{Path(__file__).resolve().parents[1]}#nix-prefetch-git",
            "--",
        ]
    )
    command.extend(["--quiet", "--url", url, "--rev", rev])
    if fetch_submodules:
        command.append("--fetch-submodules")

    completed = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    result = json.loads(completed.stdout)
    if "hash" not in result:
        raise ValueError("nix-prefetch-git returned no SRI hash")
    return validate_hash(result["hash"])


def replace_release(package_nix: str, version: str, source_hash: str) -> str:
    validate_hash(source_hash)
    package_nix, version_count = re.subn(
        r'(^\s*version = )".*";',
        rf'\g<1>{json.dumps(version)};',
        package_nix,
        count=1,
        flags=re.MULTILINE,
    )
    if version_count != 1:
        raise ValueError("package.nix has no unique package version attribute")

    block_pattern = re.compile(
        r"(?P<head>src = fetchFromGitHub \{\n)(?P<body>.*?)(?P<tail>^\s*\};)",
        re.MULTILINE | re.DOTALL,
    )
    block_match = block_pattern.search(package_nix)
    if block_match is None:
        raise ValueError("package.nix has no fetchFromGitHub source block")

    body, hash_count = re.subn(
        r'(^\s*hash = )".*";',
        rf'\g<1>{json.dumps(source_hash)};',
        block_match.group("body"),
        count=1,
        flags=re.MULTILINE,
    )
    if hash_count != 1:
        raise ValueError("fetchFromGitHub source has no unique hash attribute")
    return (
        package_nix[: block_match.start("body")]
        + body
        + package_nix[block_match.end("body") :]
    )


def replace_output_hashes(package_nix: str, hashes: list[tuple[str, str]]) -> str:
    pattern = re.compile(
        r"(?P<head>^\s*outputHashes = \{\n)(?P<body>.*?)(?P<tail>^\s*\};)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(package_nix)
    if match is None:
        raise ValueError("package.nix has no cargoLock.outputHashes block")

    opener_indent = match.group("head").split("outputHashes", 1)[0]
    entry_indent = f"{opener_indent}  "
    body = "".join(
        f'{entry_indent}{json.dumps(key)} = {json.dumps(value)};\n'
        for key, value in hashes
    )
    return package_nix[: match.start("body")] + body + package_nix[match.end("body") :]


def replace_projectm_source(package_nix: str, source: GitSource, source_hash: str) -> str:
    block_pattern = re.compile(
        r"(?P<head>projectmRsSource = fetchgit \{\n)(?P<body>.*?)(?P<tail>^\s*\};)",
        re.MULTILINE | re.DOTALL,
    )
    block_match = block_pattern.search(package_nix)
    if block_match is None:
        raise ValueError("package.nix has no projectmRsSource fetchgit block")

    body = block_match.group("body")
    replacements = {
        "url": source.url,
        "rev": source.rev,
        "hash": source_hash,
    }
    for attribute, value in replacements.items():
        body, count = re.subn(
            rf'(^\s*{attribute} = )".*";',
            rf'\g<1>{json.dumps(value)};',
            body,
            count=1,
            flags=re.MULTILINE,
        )
        if count != 1:
            raise ValueError(f"projectmRsSource has no unique {attribute} attribute")

    return (
        package_nix[: block_match.start("body")]
        + body
        + package_nix[block_match.end("body") :]
    )


def refresh(
    lock_file: Path,
    package_file: Path,
    *,
    version: str | None = None,
    source_hash: str | None = None,
) -> None:
    if (version is None) != (source_hash is None):
        raise ValueError("version and source hash must be supplied together")

    sources = read_git_sources(lock_file)
    if not sources:
        raise ValueError("Cargo.lock contains no git dependencies")

    output_hashes = [
        (source.output_hash_key, prefetch_git(source.url, source.rev))
        for source in sources
    ]

    projectm_sources = [
        source
        for source in sources
        if any(name == "projectm-sys" for name, _version in source.packages)
    ]
    if len(projectm_sources) != 1:
        raise ValueError("Cargo.lock must contain exactly one projectm-sys git source")
    projectm_source = projectm_sources[0]
    projectm_hash = prefetch_git(
        projectm_source.url,
        projectm_source.rev,
        fetch_submodules=True,
    )

    package_nix = package_file.read_text()
    if version is not None and source_hash is not None:
        package_nix = replace_release(package_nix, version, source_hash)
    package_nix = replace_output_hashes(package_nix, output_hashes)
    package_nix = replace_projectm_source(package_nix, projectm_source, projectm_hash)
    package_file.write_text(package_nix)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("lock_file", type=Path)
    parser.add_argument("package_nix", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--source-hash")
    args = parser.parse_args()
    refresh(
        args.lock_file,
        args.package_nix,
        version=args.version,
        source_hash=args.source_hash,
    )


if __name__ == "__main__":
    main()
