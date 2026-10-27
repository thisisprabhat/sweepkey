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
