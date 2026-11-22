#!/usr/bin/env bash
# Prepares a Sparkle update for the current version:
#  1. builds the English DMG (scripts/make-dmg.sh; honours PRUNE_APP, NOTARY_PROFILE, PRUNE_SIGN_IDENTITY),
#  2. signs it with the EdDSA key in the login keychain (created by generate_keys) and writes appcast.xml.
# Then: attach build/Prune-<version>.dmg to the GitHub Release v<version>, and commit + push appcast.xml
# (the app reads https://raw.githubusercontent.com/gh0styx/prune/main/appcast.xml).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/make-dmg.sh

APP="${PRUNE_APP:-build/Prune.app}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Prune-$VERSION.dmg"
[ -f "$DMG" ] || { echo "Missing $DMG" >&2; exit 1; }

UPDATES=build/updates
rm -rf "$UPDATES" && mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"

GEN="$(find .build/artifacts -path '*/Sparkle/bin/generate_appcast' -type f | head -1)"
[ -n "$GEN" ] || { echo "generate_appcast not found: run swift package resolve" >&2; exit 1; }
"$GEN" --download-url-prefix "https://github.com/gh0styx/prune/releases/download/v$VERSION/" "$UPDATES"
cp "$UPDATES/appcast.xml" appcast.xml

echo "Update $VERSION ready: $DMG (attach to Release v$VERSION) and appcast.xml (commit and push to publish)."
