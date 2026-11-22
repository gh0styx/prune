# Prune — what's left

State as of 2026-11-22. App builds (`./scripts/build-app.sh`), self-test passes (`swift run Prune --selftest`:
tree removal ok, 16/16 path rules, 0 unsafe items). DMGs: `DMG_LANG=ru ./scripts/make-dmg.sh` and `./scripts/make-dmg.sh`.

## Release
- [ ] Final check of every screen in the real app (EN + RU, dark + light), then build the release DMGs.
- [ ] Notarize: a "Developer ID Application" identity is in the keychain; `make-dmg.sh` already signs with it
      (hardened runtime + timestamp). Missing: a notarytool profile. Create once:
      `xcrun notarytool store-credentials prune --apple-id <id> --team-id <team>` (needs an app-specific password),
      then `NOTARY_PROFILE=prune ./scripts/make-dmg.sh` and the same with `DMG_LANG=ru`.
- [ ] `git init`, first commit, GitHub repo, Release with both DMGs, Homebrew cask (`prune` is free).
- [ ] Website for the app (download buttons for EN/RU DMG, screenshots from `docs/`).
- [ ] README + screenshots are behind the current UI.

## Not verified live (built and compiled, never exercised)
- Moving to Trash / Restore / "Free space now" / app uninstall (nothing was deleted on the dev Mac).
- Dev servers: Stop / Force quit.
- Maintenance tasks (DNS flush, Spotlight reindex, purge need admin via the system password dialog).
- Login items: Disable / Enable / Remove.
- Security check: Remove for flagged launch agents.
- Duplicates: identical-file and similar-photo scans (similar-photo threshold 0.35 not tuned on real photos).
- Mail attachments scan (needs Full Disk Access) and the Photos "Recently Deleted" card.
- Notifications + scheduled scans, multi-disk picker (dev Mac has one disk), menu bar popover glass, hover animations.

## Known small issues
- Git activity date for a repo with no commits can be inaccurate.
- Duplicates scan has no cancel button; similar-photo grouping is chain-based (A~B, B~C → one group).

## Ideas not started
- First-launch "Move to Applications" prompt (instead of a custom installer).
- Quick Look on Space in tables, keyboard navigation, fast rescans via FSEvents + cache.
- Memory/CPU monitor in the menu bar, app updater, browser data cleanup, secure shredding.
