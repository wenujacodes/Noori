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
# Builds a Release of Noori, zips it (plus a DMG), signs the zip for Sparkle and adds it to
# Updates/appcast.xml.
#
#   scripts/release.sh <version> [--publish]
#   e.g. scripts/release.sh 1.0.1 --publish
#
# <version> is what users see (1.0.1). The build number is picked automatically:
# one more than the newest build in Updates/appcast.xml (Sparkle uses it to
# decide what is newer), or the project's current build for the first release.
# Set BUILD=<n> to choose it yourself.
# --publish also creates the GitHub release v<version> in wenujacodes/Noori (with
# the zip, the DMG and the version's CHANGELOG.md notes), then commits the version bump,
# the changelog and Updates/appcast.xml and pushes them. Installed copies read
# that appcast on main and download from the release.
#
# Signing: the app is signed with SIGN_IDENTITY, or else the first "Developer ID
# Application" certificate in the Keychain, or else the first "Apple Development"
# one, and only ad-hoc ("-") when there's none. Use a real certificate: macOS
# remembers permissions (Accessibility, Automation, Full Disk Access) by the
# app's signature, and an ad-hoc signature is different for every build, so
# every update asked for all of them again. Keep using the same certificate.
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
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    SIGN_IDENTITY="$(grep '"Developer ID Application:' <<<"$IDENTITIES" | head -1 | awk '{print $2}' || true)"
    [[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY="$(grep '"Apple Development:' <<<"$IDENTITIES" | head -1 | awk '{print $2}' || true)"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        SIGN_IDENTITY="-"
        echo "warning: no signing certificate found; signing ad-hoc (users will be asked for permissions again after this update)" >&2
    fi
fi
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
APPCAST="$ROOT/Updates/appcast.xml"
RELEASES_REPO="wenujacodes/Noori"
DOWNLOAD_PREFIX="https://github.com/$RELEASES_REPO/releases/download/v$VERSION/"
ZIP="$DIST/Noori-$VERSION.zip"
DMG="$DIST/Noori-$VERSION.dmg"

# 1. Version numbers (kept in the repo so the next release starts from them).
echo "$VERSION" > VERSION
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/" Noori.xcodeproj/project.pbxproj
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" Noori.xcodeproj/project.pbxproj

# 2. Build, from scratch: leftovers from an earlier release (an old app, cached
#    modules from older package versions) must never end up in this one.
echo "Building Noori $VERSION ($BUILD)…"
rm -rf "$DERIVED/Build" "$DERIVED/ModuleCache.noindex"
mkdir -p "$DERIVED"
# Universal: Apple Silicon and Intel in one app ("generic" so it isn't built
# only for this Mac's chip), stripped of debugging symbols.
xcodebuild build \
    -project Noori.xcodeproj \
    -scheme Noori \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    > "$DERIVED/build.log" 2>&1 \
    || { grep -E "error:" "$DERIVED/build.log" | sort -u | head -20 >&2; echo "Build failed; nothing was released (full log: $DERIVED/build.log)" >&2; exit 1; }
echo "Build succeeded."
APP="$DERIVED/Build/Products/Release/Noori.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }
# The signature must be valid; show what it's tied to.
codesign --verify --deep --strict "$APP" \
    || { echo "Noori.app's code signature isn't valid; nothing was released" >&2; exit 1; }
echo "Signed with: $(codesign -dvv "$APP" 2>&1 | grep -m1 '^Authority=' | cut -d= -f2- || echo 'ad-hoc')"
# Refuse to ship an app that won't start on one kind of Mac.
for arch in arm64 x86_64; do
    lipo "$APP/Contents/MacOS/Noori" -verify_arch "$arch" \
        || { echo "Noori.app has no $arch code; it wouldn't run on every Mac" >&2; exit 1; }
done

# The release is stripped of debugging symbols (much smaller). They're kept in
# a .dSYM next to the zip, to read crash reports from this version.
DSYM="$DERIVED/Build/Products/Release/Noori.app.dSYM"
mkdir -p "$DIST"
if [[ -d "$DSYM" ]]; then
    rm -rf "$DIST/Noori-$VERSION.app.dSYM"
    cp -R "$DSYM" "$DIST/Noori-$VERSION.app.dSYM"
fi

# 3. Zip.
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# 3b. DMG for first-time downloads: Noori.app next to an Applications link to
#     drag it onto. Updates keep using the zip.
DMG_SRC="$DERIVED/dmg"
rm -rf "$DMG_SRC" "$DMG"
mkdir -p "$DMG_SRC"
ditto "$APP" "$DMG_SRC/Noori.app"
ln -s /Applications "$DMG_SRC/Applications"
hdiutil create -quiet -volname "Noori $VERSION" -srcfolder "$DMG_SRC" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"

# 4. Sign the zip and make the new appcast. generate_appcast works on a folder
#    holding the archives and appcast.xml. Only this version's zip goes in, so
#    the older entries are kept exactly as they are (with older zips in the
#    folder it rewrites their links to this version's release and adds delta
#    files). The result stays in a staging folder until the release is up.
SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts" "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)"
[[ -n "$SPARKLE_BIN" ]] || { echo "Sparkle tools not found; resolve packages first" >&2; exit 1; }
STAGE="$DERIVED/appcast"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ZIP" "$STAGE/"
cp "$APPCAST" "$STAGE/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --account Noori \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    "$STAGE"
rm -f "$STAGE"/*.delta
echo "Signed $ZIP"

# 5. Optionally publish: the GitHub release (zip, DMG + this version's changelog
#    notes), then the appcast on main. Release first, feed second: the feed
#    must never point at a missing download.
if [[ "$PUBLISH" == "--publish" ]]; then
    NOTES="$DIST/notes-$VERSION.md"
    awk -v v="$VERSION" '
        index($0, "## [" v "]") == 1 { found = 1; next }
        found && /^## \[/ { exit }
        found { print }
    ' CHANGELOG.md > "$NOTES"
    [[ -s "$NOTES" ]] || echo "See the changelog for what's new." > "$NOTES"

    # Create the release first, then upload the zip and DMG with retries (big uploads
    # sometimes time out).
    if ! gh release view "v$VERSION" --repo "$RELEASES_REPO" > /dev/null 2>&1; then
        gh release create "v$VERSION" \
            --repo "$RELEASES_REPO" \
            --title "Noori $VERSION" \
            --notes-file "$NOTES"
    fi
    for attempt in 1 2 3 4 5; do
        gh release upload "v$VERSION" "$ZIP" "$DMG" --clobber --repo "$RELEASES_REPO" && break
        [[ $attempt == 5 ]] && { echo "Upload failed; the release v$VERSION is missing its downloads and the appcast wasn't changed" >&2; exit 1; }
        echo "Upload failed, trying again ($attempt/5)…" >&2
        sleep 5
    done
    echo "Published release v$VERSION in $RELEASES_REPO"

    cp "$STAGE/appcast.xml" "$APPCAST"
    git add VERSION Noori.xcodeproj/project.pbxproj CHANGELOG.md Updates/appcast.xml
    git commit -q -m "Release $VERSION"
    git push -q
    echo "Committed and pushed the version bump and the appcast"
else
    cp "$STAGE/appcast.xml" "$APPCAST"
    echo "Updated $APPCAST"
fi

if [[ "$PUBLISH" != "--publish" ]]; then
    echo
    echo "Not published. To publish: run again with --publish (or create the release and push the appcast yourself)."
fi
