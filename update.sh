#!/usr/bin/env bash
# Update script for the fastpotify package.
# Usage: ./update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"
CARGO_LOCK="$SCRIPT_DIR/Cargo.lock"

CURRENT_VERSION=$(grep 'version = ' "$PACKAGE_NIX" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current version: $CURRENT_VERSION"

echo "Checking GitHub for latest release..."
CURL_OPTS=(-sL)
[ -n "${GITHUB_TOKEN:-}" ] && CURL_OPTS+=(-H "Authorization: token $GITHUB_TOKEN")
LATEST_TAG=$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/crmne/fastpotify/releases/latest" | jq -r '.tag_name')

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
    echo "Error: Could not fetch latest version from GitHub"
    exit 1
fi

LATEST_VERSION="${LATEST_TAG#v}"
echo "Latest version:  $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "Already up to date!"
    exit 0
fi

echo "Fetching source hash for $LATEST_TAG..."
SRC_HASH=$(nix-prefetch-github crmne fastpotify --rev "$LATEST_TAG" | jq -r '.hash')

if [ -z "$SRC_HASH" ] || [ "$SRC_HASH" = "null" ]; then
    echo "Error: Could not compute source hash"
    exit 1
fi
echo "New source hash: $SRC_HASH"

# Pin the exact Cargo.lock from the release tag as a real repo-tracked file.
# `cargoLock.lockFile = ${src}/Cargo.lock` would need to read a fetcher's
# output during evaluation (import-from-derivation) and breaks
# `nix flake check --option allow-import-from-derivation false`; a
# repo-local ./Cargo.lock avoids that without any hash-mismatch trick.
echo "Fetching Cargo.lock for $LATEST_TAG..."
curl "${CURL_OPTS[@]}" -o "$CARGO_LOCK" \
    "https://raw.githubusercontent.com/crmne/fastpotify/$LATEST_TAG/Cargo.lock"

if ! grep -q '^\[\[package\]\]' "$CARGO_LOCK"; then
    echo "Error: Fetched Cargo.lock looks malformed"
    exit 1
fi

# Only the first occurrence of each attribute: package.nix declares each of
# these exactly once, but an unbounded sed would silently touch a second
# match if the file ever grows one (e.g. a changelog URL repeating the hash).
sed -i "0,/version = \".*\"/{s/version = \".*\"/version = \"$LATEST_VERSION\"/}" "$PACKAGE_NIX"
sed -i "0,/hash = \"sha256-.*\"/{s/hash = \"sha256-.*\"/hash = \"$SRC_HASH\"/}" "$PACKAGE_NIX"

echo "Updated package.nix and Cargo.lock to version $LATEST_VERSION"
echo ""
echo "Verifying build..."
nix build "$SCRIPT_DIR#fastpotify" -L
echo "Build ok."
