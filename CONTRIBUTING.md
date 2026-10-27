# Contributing

Thanks for helping. Cleaner deletes files, so changes are reviewed with safety first.

## Setup
```sh
brew install xcodegen
make test    # CleanerKit unit tests (Swift Testing)
make build   # generate the Xcode project and build the app, ad-hoc signed
make cli     # release build of the `cleaner` CLI
```
Requires macOS 26+ and Xcode 27 (Swift 6, strict concurrency).

`make build` is ad-hoc signed and has no entitlements, so there is no App Group: the widget shows placeholder data and the app silently skips writing its snapshot. `make build-signed` (needs a development certificate and team) applies `Config/*.entitlements`; the App Group id is `$(TeamIdentifierPrefix)com.prabhatkumar.Cleaner` and reaches the code through the `CleanerAppGroup` Info.plist key. Release builds always use the entitlements (see `scripts/release.sh`).

Versions: the CLI version lives only in `CleanerVersion.current` (`Packages/CleanerKit/Sources/CleanerKit/CLISupport/Version.swift`) and must match `MARKETING_VERSION` in `project.yml` (a unit test checks this); the release script stamps both from the tag. Sparkle is pinned with `exactVersion` in `project.yml`, because the generated Xcode project (and its `Package.resolved`) is not committed. CleanerKit's own `Package.resolved` pins only its dependencies; Xcode adds the app's whole graph (Sparkle included) to it on a fresh resolve, so `make build`/`make build-signed` save and restore it around `xcodebuild`. Do not commit a Sparkle pin there.

## Layout
- `Packages/CleanerKit`: all logic (scanner, rules, safety guard, executor, vault) and the CLI target.
- `App/`: SwiftUI app. `project.yml` is the XcodeGen spec; `Cleaner.xcodeproj` is generated and not committed.

## Rules
- Every filesystem-touching type takes injectable root/home URLs. Tests must use temp directories and never read or modify the real home directory.
- Never log secret file contents.
- Do not weaken the safety guards (dry run first, git-tracked guard, symlinks never followed, path guards).
- No compiler warnings. SwiftLint and SwiftFormat configs are in the repo (`.swiftlint.yml`, `.swiftformat`).
- Conventional commit messages (`feat(scanner): ...`, `fix(vault): ...`).

## Adding a cleaning rule
Rules are JSON. See [docs/rules.md](docs/rules.md).

## Pull requests
Fill in the template, keep the change focused, and include tests.
