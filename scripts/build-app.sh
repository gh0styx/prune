#!/usr/bin/env bash
# Builds build/Prune.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Prune"

ICON_DIR=build/icon
rm -rf "$ICON_DIR" && mkdir -p "$ICON_DIR"
"$BIN" --render-icon "$ICON_DIR"
iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "$ICON_DIR/AppIcon.icns"
# Icon Composer icon (macOS 26+): Liquid Glass with light, dark and tinted appearances,
# compiled into Assets.car. AppIcon.icns stays as the fallback for older macOS.
mkdir -p "$ICON_DIR/car"
xcrun actool "$ICON_DIR/AppIcon.icon" --compile "$ICON_DIR/car" --platform macosx \
  --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "$ICON_DIR/partial.plist" >/dev/null

APP=build/Prune.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Prune"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ICON_DIR/car/Assets.car" "$APP/Contents/Resources/Assets.car"
# Localizations (English source, Russian translation).
cp -R Resources/en.lproj Resources/ru.lproj "$APP/Contents/Resources/"
# A stable identity keeps macOS privacy grants (Documents, Full Disk Access) across rebuilds;
# ad-hoc signatures change every build, so macOS asks again each time.
SIGN_ID="${PRUNE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${SIGN_ID:--}" "$APP" >/dev/null
if [ -n "$SIGN_ID" ]; then echo "Signed with a stable identity"; else echo "Signed ad-hoc (no identity found)"; fi

echo "Built $APP"
