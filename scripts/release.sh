#!/usr/bin/env bash
#
# Noori
# Copyright (C) 2026 Wenuja Liyanamana
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Builds a Release of Noori, zips it, signs it for Sparkle and adds it to
# Updates/appcast.xml.
#
#   scripts/release.sh <version> [--publish]
#   e.g. scripts/release.sh 1.0.1 --publish
#
# <version> is what users see (1.0.1). The build number is picked automatically:
# one more than the newest build in Updates/appcast.xml (Sparkle uses it to
# decide what is newer), or the project's current build for the first release.
# Set BUILD=<n> to choose it yourself.
# --publish also creates the GitHub release v<version> (with the zip and the
# version's CHANGELOG.md notes) in the public repo wenujacodes/Noori-releases,
# and pushes the updated appcast there. Noori's own repo is private, so
# installed copies read the feed and download updates from that public repo.
# Its local checkout is ../Noori-releases (set RELEASES_DIR to change it).
# Updates/appcast.xml here is the master copy and still has to be committed.
#
# Signing: SIGN_IDENTITY (default "-", ad-hoc) is used for the app itself.
# The Sparkle signature uses the "Noori" EdDSA key in the login Keychain
# (created with `generate_keys --account Noori`). Keep a backup of that key:
# without it no existing install can update again.

set -euo pipefail

VERSION="${1:-}"
PUBLISH="${2:-}"
if [[ -z "$VERSION" || "$VERSION" == --* ]]; then
    echo "usage: scripts/release.sh <version> [--publish]" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build number: next after the newest one already released.
if [[ -z "${BUILD:-}" ]]; then
    LAST_RELEASED="$(grep -oE '<sparkle:version>[0-9]+</sparkle:version>' Updates/appcast.xml \
        | grep -oE '[0-9]+' | sort -n | tail -1 || true)"
    if [[ -n "$LAST_RELEASED" ]]; then
        BUILD=$((LAST_RELEASED + 1))
    else
        BUILD="$(grep -oE 'CURRENT_PROJECT_VERSION = [0-9]+;' Noori.xcodeproj/project.pbxproj \
            | head -1 | grep -oE '[0-9]+')"
    fi
fi
if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "Build number must be a whole number, got: $BUILD" >&2
    exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
APPCAST="$ROOT/Updates/appcast.xml"
RELEASES_REPO="wenujacodes/Noori-releases"
RELEASES_DIR="${RELEASES_DIR:-$ROOT/../Noori-releases}"
DOWNLOAD_PREFIX="https://github.com/$RELEASES_REPO/releases/download/v$VERSION/"
ZIP="$DIST/Noori-$VERSION.zip"

# 1. Version numbers (kept in the repo so the next release starts from them).
echo "$VERSION" > VERSION
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/" Noori.xcodeproj/project.pbxproj
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" Noori.xcodeproj/project.pbxproj

# 2. Build.
echo "Building Noori $VERSION ($BUILD)…"
xcodebuild build \
    -project Noori.xcodeproj \
    -scheme Noori \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="$DERIVED/Build/Products/Release/Noori.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }

# 3. Zip.
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# 4. Sign the zip and update the appcast. generate_appcast works on a folder
#    holding the archives and appcast.xml, so the current appcast is copied in
#    first; existing entries are kept.
SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts" "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)"
[[ -n "$SPARKLE_BIN" ]] || { echo "Sparkle tools not found; resolve packages first" >&2; exit 1; }
cp "$APPCAST" "$DIST/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --account Noori \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    "$DIST"
cp "$DIST/appcast.xml" "$APPCAST"
echo "Updated $APPCAST"

# 5. Optionally publish: the GitHub release (zip + this version's changelog
#    notes) and the appcast, both in the public releases repo.
if [[ "$PUBLISH" == "--publish" ]]; then
    [[ -d "$RELEASES_DIR/.git" ]] || git clone -q "https://github.com/$RELEASES_REPO.git" "$RELEASES_DIR"
    NOTES="$DIST/notes-$VERSION.md"
    awk -v v="$VERSION" '
        index($0, "## [" v "]") == 1 { found = 1; next }
        found && /^## \[/ { exit }
        found { print }
    ' CHANGELOG.md > "$NOTES"
    [[ -s "$NOTES" ]] || echo "See the changelog for what's new." > "$NOTES"

    gh release create "v$VERSION" "$ZIP" \
        --repo "$RELEASES_REPO" \
        --title "Noori $VERSION" \
        --notes-file "$NOTES"
    echo "Published release v$VERSION in $RELEASES_REPO"

    # Release first, feed second: the feed must never point at a missing download.
    cp "$APPCAST" "$RELEASES_DIR/appcast.xml"
    git -C "$RELEASES_DIR" pull -q --ff-only
    git -C "$RELEASES_DIR" add appcast.xml
    git -C "$RELEASES_DIR" commit -q -m "Noori $VERSION ($BUILD)"
    git -C "$RELEASES_DIR" push -q
    echo "Pushed the appcast to $RELEASES_REPO"
fi

echo
echo "Next: commit VERSION, the project file and Updates/appcast.xml here, then push."
