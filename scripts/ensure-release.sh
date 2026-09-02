#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <version> <upstream-tag>" >&2
    exit 2
fi

VERSION=$1
UPSTREAM_TAG=$2
RELEASE_TAG="v$VERSION"

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    echo "Release $RELEASE_TAG already exists."
    exit 0
fi

gh release create "$RELEASE_TAG" \
    --target main \
    --title "fastpotify $VERSION" \
    --notes "Updated fastpotify to $VERSION (upstream: https://github.com/crmne/fastpotify/releases/tag/$UPSTREAM_TAG)"
