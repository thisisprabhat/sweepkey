# Cleaner

Cleaner is a native macOS 26+ SwiftUI app (with a companion `cleaner` CLI) that reclaims disk space by removing regenerable developer artifacts and caches, and collects un-committed secrets into a vault.

## Build

```sh
brew install xcodegen
make test    # run CleanerKit tests
make build   # generate Cleaner.xcodeproj and build the app (ad-hoc signed)
make cli     # build the release CLI
```
