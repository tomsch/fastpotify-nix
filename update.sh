#!/usr/bin/env bash
# Update Fastpotify and every Cargo git dependency to the latest release.
# Usage: ./update.sh [--no-build]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"
CARGO_LOCK="$SCRIPT_DIR/Cargo.lock"
BUILD=true

case "${1:-}" in
    "") ;;
    --no-build) BUILD=false ;;
    *)
        echo "Usage: $0 [--no-build]" >&2
        exit 2
        ;;
esac

CURRENT_VERSION=$(grep 'version = ' "$PACKAGE_NIX" | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Current version: $CURRENT_VERSION"

echo "Checking GitHub for latest release..."
CURL_OPTS=(-fsSL)
[ -n "${GITHUB_TOKEN:-}" ] && CURL_OPTS+=(-H "Authorization: token $GITHUB_TOKEN")
LATEST_TAG=$(curl "${CURL_OPTS[@]}" \
    "https://api.github.com/repos/crmne/fastpotify/releases/latest" |
    jq -er '.tag_name')
LATEST_VERSION="${LATEST_TAG#v}"
echo "Latest version:  $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "Already up to date!"
    exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
NEXT_PACKAGE="$TMP_DIR/package.nix"
NEXT_LOCK="$TMP_DIR/Cargo.lock"
cp "$PACKAGE_NIX" "$NEXT_PACKAGE"

echo "Fetching source hash for $LATEST_TAG..."
RAW_HASH=$(nix-prefetch-url --unpack --type sha256 \
    "https://github.com/crmne/fastpotify/archive/refs/tags/${LATEST_TAG}.tar.gz")
SRC_HASH=$(nix hash convert --hash-algo sha256 --to sri "$RAW_HASH")
case "$SRC_HASH" in
    sha256-AAAAAAAA*)
        echo "Error: refusing to write the Nix fake hash" >&2
        exit 1
        ;;
    sha256-?*) ;;
    *)
        echo "Error: unusable source hash: '$SRC_HASH'" >&2
        exit 1
        ;;
esac
echo "New source hash: $SRC_HASH"

echo "Fetching Cargo.lock for $LATEST_TAG..."
curl "${CURL_OPTS[@]}" -o "$NEXT_LOCK" \
    "https://raw.githubusercontent.com/crmne/fastpotify/$LATEST_TAG/Cargo.lock"
grep -q '^\[\[package\]\]' "$NEXT_LOCK"

echo "Refreshing Cargo git dependency hashes..."
python3 "$SCRIPT_DIR/scripts/refresh-cargo-git-sources.py" \
    "$NEXT_LOCK" "$NEXT_PACKAGE" \
    --version "$LATEST_VERSION" \
    --source-hash "$SRC_HASH"

mv "$NEXT_PACKAGE" "$PACKAGE_NIX"
mv "$NEXT_LOCK" "$CARGO_LOCK"
echo "Updated package.nix and Cargo.lock to version $LATEST_VERSION"

if "$BUILD"; then
    echo "Verifying build..."
    nix build "$SCRIPT_DIR#fastpotify" --accept-flake-config -L
    echo "Build ok."
fi
