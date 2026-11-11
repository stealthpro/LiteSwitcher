#!/bin/sh
# Builds LiteSwitcher in Release and packages it as a compressed .dmg
# with an /Applications shortcut and a styled Finder window: big icons,
# the app on the left, an arrow in the middle, Applications on the right,
# over a custom background.
#
#   ./make-dmg.sh          writes dist/LiteSwitcher.dmg
#
# The styled window is produced by dmgbuild. Install it once with:
#   pip3 install dmgbuild
# If dmgbuild is missing, the script falls back to a plain, unstyled image.
#
# The app is only as signed as the Release build: it is not notarized, so
# on another Mac Gatekeeper will block it until the user allows it in
# System Settings > Privacy & Security.
set -eu

cd "$(dirname "$0")"
ROOT="$(pwd)"

APP_NAME=LiteSwitcher
OUT_DIR=dist
VOL_NAME="LiteSwitcher"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/liteswitcher-dmg.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Building $APP_NAME (Release)..."
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$WORK_DIR/derived" build \
    > "$WORK_DIR/build.log" 2>&1; then
    tail -n 40 "$WORK_DIR/build.log"
    echo "Build failed." >&2
    exit 1
fi

BUILT_APP="$WORK_DIR/derived/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "Build succeeded but $BUILT_APP was not found." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")
DMG="$OUT_DIR/$APP_NAME.dmg"

mkdir -p "$OUT_DIR"
rm -f "$DMG"

# Prefer dmgbuild for the styled window; fall back to a plain image.
if command -v dmgbuild >/dev/null 2>&1; then
    DMGBUILD="dmgbuild"
elif python3 -c 'import dmgbuild' >/dev/null 2>&1; then
    DMGBUILD="python3 -m dmgbuild"
else
    DMGBUILD=""
fi

if [ -n "$DMGBUILD" ]; then
    echo "Packaging styled DMG (dmgbuild)..."
    $DMGBUILD -s "$ROOT/dmg/settings.py" \
        -D "app=$BUILT_APP" \
        -D "background=$ROOT/dmg/background.png" \
        "$VOL_NAME" "$DMG"
else
    echo "dmgbuild not found: making a plain DMG (run 'pip3 install dmgbuild' for the styled window)." >&2
    STAGE="$WORK_DIR/stage"
    mkdir -p "$STAGE"
    ditto "$BUILT_APP" "$STAGE/$APP_NAME.app"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" \
        -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" > /dev/null
fi

hdiutil verify "$DMG" > /dev/null
echo "Done: $ROOT/$DMG"
