#!/usr/bin/env bash
# Builds build/Prune-<version>.dmg: drag-to-Applications installer with a custom background.
#
# Signing: uses PRUNE_SIGN_IDENTITY, else the first "Developer ID Application" or "Apple Development"
# identity in the keychain, else ad-hoc.
# Notarization (needs a Developer ID identity): set NOTARY_PROFILE to a keychain profile created with
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
APP=build/Prune.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
# DMG_LANG=ru gives a Russian installer window (background text and the Applications link name).
DMG_LANG="${DMG_LANG:-en}"
if [ "$DMG_LANG" = ru ]; then
  DMG="build/Prune-$VERSION-ru.dmg"; APPS_NAME="Программы"; LANG_ARGS=(-AppleLanguages "(ru)")
else
  DMG="build/Prune-$VERSION.dmg"; APPS_NAME="Applications"; LANG_ARGS=()
fi
VOL="Prune"
STAGE=build/dmg
RW=build/Prune-rw.dmg

SIGN_ID="${PRUNE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Developer ID Application/ {print $2; exit}')}"
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development/ {print $2; exit}')}"
IS_DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID.*Developer ID" && echo yes || echo no)

# Developer ID builds get the hardened runtime and a secure timestamp, which notarization requires.
if [ "$IS_DEVELOPER_ID" = yes ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi

# Stage: the app, a link to /Applications, the background and the volume icon.
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/$APPS_NAME"
"$APP/Contents/MacOS/Prune" --render-dmg-background "$STAGE/.background" ${LANG_ARGS[@]+"${LANG_ARGS[@]}"}
tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
rm "$STAGE/.background/"background*.png
cp build/icon/AppIcon.icns "$STAGE/.VolumeIcon.icns"

hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
# Detach any stale mount with the same name first.
if [ -d "/Volumes/$VOL" ]; then hdiutil detach "/Volumes/$VOL" -force >/dev/null || true; fi
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1; exit}')
MOUNT="/Volumes/$VOL"

# Custom volume icon.
xcrun SetFile -a C "$MOUNT" 2>/dev/null || true

# Window layout (icon positions match DmgArt.appCenter / applicationsCenter).
if ! osascript <<EOF >/dev/null 2>&1
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Prune.app" of container window to {180, 210}
    set position of item "$APPS_NAME" of container window to {480, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
then
  echo "Note: Finder layout skipped (allow Terminal to control Finder for the styled window)."
fi

sync
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"

if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" ${IS_DEVELOPER_ID/yes/--timestamp} "$DMG" 2>/dev/null \
    || codesign --force --sign "$SIGN_ID" "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  if [ "$IS_DEVELOPER_ID" != yes ]; then
    echo "NOTARY_PROFILE set but no Developer ID identity: skipping notarization." >&2
  else
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "Built $DMG ($(du -h "$DMG" | cut -f1)), signed: $([ -n "$SIGN_ID" ] && echo yes || echo ad-hoc), notarized: $([ -n "${NOTARY_PROFILE:-}" ] && [ "$IS_DEVELOPER_ID" = yes ] && echo yes || echo no)"
