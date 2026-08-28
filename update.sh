#!/usr/bin/env bash
# Update script for the fastpotify package.
# Usage: ./update.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"

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
SRI_HASH=$(nix-prefetch-github crmne fastpotify --rev "$LATEST_TAG" | jq -r '.hash')

if [ -z "$SRI_HASH" ] || [ "$SRI_HASH" = "null" ]; then
    echo "Error: Could not compute source hash"
    exit 1
fi

echo "New SRI hash: $SRI_HASH"

sed -i "s/version = \"$CURRENT_VERSION\"/version = \"$LATEST_VERSION\"/" "$PACKAGE_NIX"
sed -i "s|hash = \"sha256-.*\"|hash = \"$SRI_HASH\"|" "$PACKAGE_NIX"

echo "Updated package.nix to version $LATEST_VERSION"
echo ""
echo "Verify with: nix build .#fastpotify"
