# Testing and verification

← [Index](README.md)

## Unit tests (Swift Testing, in CleanerKit)
Tests build fixture trees in a temp folder and never touch the real `$HOME`. They cover:
- one fake project per ecosystem; each rule matches only when its marker is present
- a `build/` folder with no marker is never matched
- a symlink pointing outside the root is not followed
- a committed `dist/` folder (temp git repo) is rejected by the git-tracked guard
- hard links are counted once

## Vault tests
- Temp git repo with a `.gitignore`d `.env`, a `.jks` and a tracked `pubspec.yaml`; collect, then check mirror layout, manifest hashes and `0600` permissions.
- Re-clone the repo, restore by remote, and check the bytes match.
- Round-trip the encrypted image (`hdiutil attach` with the password).

## Cache provider tests
Inject a fake shell runner and assert the right native commands are issued (`docker system prune ...`, `xcrun simctl delete unavailable`).

## CLI smoke test
Run `cleaner scan ~/Projects --dry-run --json` on a real machine and compare reported sizes with `du -sh` on a few targets.

## UI
Walk through onboarding, scan, select, dry run, clean in Trash mode, then Put Back from History. Repeat for vault export in each format. XCUITest covers the main flow.

## Release check
`spctl -a -vv` and `stapler validate` on the notarized DMG; test a Sparkle update from the previous build.

## Commands
`make test` runs `swift test` in `Packages/CleanerKit`.
