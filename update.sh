#!/usr/bin/env bash
# Update script for the fastpotify package.
# Usage: ./update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

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

# Only the first occurrence of each attribute: package.nix declares each of
# these exactly once, but an unbounded sed would silently touch a second
# match if the file ever grows one (e.g. a changelog URL repeating the hash).
sed -i "0,/version = \".*\"/{s/version = \".*\"/version = \"$LATEST_VERSION\"/}" "$PACKAGE_NIX"
sed -i "0,/hash = \"sha256-.*\"/{s/hash = \"sha256-.*\"/hash = \"$SRC_HASH\"/}" "$PACKAGE_NIX"

# Cargo.lock content at the new rev is unknown up front, so cargoHash must be
# recomputed: force a mismatch against a fake hash and read Nix's own
# fixed-output-derivation report for the real one, same trick `nix-init` uses.
sed -i "0,/cargoHash = \".*\"/{s/cargoHash = \".*\"/cargoHash = \"$FAKE_HASH\"/}" "$PACKAGE_NIX"

echo "Recomputing cargoHash..."
BUILD_OUTPUT=$(nix build "$SCRIPT_DIR#fastpotify" -L 2>&1) || true
CARGO_HASH=$(echo "$BUILD_OUTPUT" | grep -A1 "vendor-staging.drv" | grep "got:" | head -1 | sed 's/.*got:[[:space:]]*//')

if [ -z "$CARGO_HASH" ]; then
    echo "Error: Could not compute cargoHash. Build output:"
    echo "$BUILD_OUTPUT"
    exit 1
fi
echo "New cargoHash: $CARGO_HASH"

sed -i "0,/cargoHash = \".*\"/{s/cargoHash = \".*\"/cargoHash = \"$CARGO_HASH\"/}" "$PACKAGE_NIX"

echo "Updated package.nix to version $LATEST_VERSION"
echo ""
echo "Verifying build..."
nix build "$SCRIPT_DIR#fastpotify" -L
echo "Build ok."
