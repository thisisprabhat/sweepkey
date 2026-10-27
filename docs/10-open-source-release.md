# Open-source release

← [Index](README.md)

## Project hygiene
MIT license; README with screenshots; CONTRIBUTING; a rules contribution guide (rules are JSON, so easy to PR, see [02](02-cleaning-rules.md)); issue and PR templates.

## CI (GitHub Actions)
On push/PR: build, unit tests, SwiftLint/SwiftFormat. The CI workflow installs XcodeGen and runs `make test` and `make build`.

## Release on tag
Archive, sign (Developer ID, Hardened Runtime, no sandbox), notarize, staple, publish a DMG to GitHub Releases, and update the Sparkle 2 appcast and the Homebrew cask.

## Sparkle 2
In-app updates, EdDSA-signed. Sparkle update checks are the only network use in the app.

## Homebrew
A cask for the app and a formula for the `cleaner` CLI.

## Verification
`spctl -a -vv` and `stapler validate` on the DMG; test an update from the previous build.
