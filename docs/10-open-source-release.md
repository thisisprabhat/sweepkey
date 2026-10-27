# Open-source release

← [Index](README.md)

## Project hygiene
MIT license; README with screenshots; CONTRIBUTING; a rules contribution guide (rules are JSON, so easy to PR, see [02](02-cleaning-rules.md)); issue and PR templates.

## CI (GitHub Actions)
On push/PR: build, unit tests, SwiftLint/SwiftFormat. The CI workflow installs XcodeGen and runs `make test` and `make build`.

## Release on tag
Archive, sign (Developer ID, Hardened Runtime, no sandbox for the app; the widget extension is sandboxed and shares a Team-ID-prefixed App Group, `$(TeamIdentifierPrefix)com.prabhatkumar.Cleaner`), notarize, staple, publish a DMG to GitHub Releases, and update the Sparkle 2 appcast. The workflow prints the cask version and sha256; updating the Homebrew cask automatically is planned for v1.1 ([08](08-roadmap.md)). `scripts/release.sh` refuses to run while the Sparkle feed URL still contains the `OWNER` placeholder.

## Sparkle 2
In-app updates, EdDSA-signed. Sparkle update checks are the only network use in the app.

## Homebrew
A cask for the app and a formula for the `cleaner` CLI.

## Verification
`spctl -a -vv` and `stapler validate` on the DMG; test an update from the previous build.
