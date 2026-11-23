#!/usr/bin/env bash
# Builds a Developer ID release of Prune with Xcode's own signing and notarization, then runs the
# DMG + appcast step. Uses the Apple account already signed in to Xcode (no app-specific password).
#
#   scripts/release.sh            # archive, export + notarize, DMG, appcast
#
# Afterwards: attach build/Prune-<version>.dmg to the GitHub Release v<version>, then commit and push appcast.xml.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-N527H8UA5P}"
ARCHIVE=build/Prune.xcarchive
EXPORT_DIR=build/export

rm -rf "$ARCHIVE" "$EXPORT_DIR" && mkdir -p build

# destination: "upload" sends the archive to Apple for notarization; "export" then writes the notarized app.
for dest in upload export; do
cat > "build/ExportOptions-$dest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>destination</key><string>$dest</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
done

echo "Archiving…"
xcodebuild -project Prune.xcodeproj -scheme Prune -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive | tail -3

echo "Uploading for notarization (Apple may take a few minutes)…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/upload \
  -exportOptionsPlist build/ExportOptions-upload.plist -allowProvisioningUpdates | tail -5

echo "Exporting the notarized app…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions-export.plist -allowProvisioningUpdates | tail -5

APP="$EXPORT_DIR/Prune.app"
[ -d "$APP" ] || { echo "Export did not produce $APP" >&2; exit 1; }

echo "Checking signature, notarization ticket and Gatekeeper…"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "Building DMG and appcast from $APP…"
PRUNE_APP="$APP" ./scripts/release-update.sh
