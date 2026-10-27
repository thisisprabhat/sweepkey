<p align="center"><img src="docs/images/icon.png" width="128" alt="Sweepkey icon"></p>

# Sweepkey

*Sweep the rebuildable. Keep the keys.*

A native macOS 26+ app (with a companion `sweepkey` CLI) that reclaims disk space by removing regenerable developer artifacts and caches, and collects your un-committed secrets into a vault before you clean. Open source (MIT), distributed outside the App Store.

<!-- Screenshots: add images under docs/images/ and link them here. -->
*Screenshots: coming soon.*

## Features
- **Project cleaning.** Finds `node_modules`, `target`, `build`, `.venv`, `Pods`, `DerivedData`-style folders and more across 20+ ecosystems, driven by JSON rules ([docs/rules.md](docs/rules.md)). Shows size, last activity and how to regenerate each item.
- **Global caches.** Developer tool caches (package managers, simulators, toolchains) listed by group.
- **Secrets vault.** Collects `.env`-style and other un-committed secret files from projects into a folder, zip or password-protected DMG, and restores them later (optionally matching projects by git remote).
- **History.** Every clean is journaled, with lifetime space reclaimed.
- **CLI** for scripting and CI.
- **Updates** via Sparkle 2, EdDSA-signed.

More in [docs/](docs/README.md).

## Install

### Download
Get the notarized DMG from [Releases](https://github.com/waygosquad/sweepkey/releases) and drag Sweepkey to Applications. The release also contains `sweepkey-<version>-macos.zip` with just the CLI.

### Homebrew
```sh
brew install --cask waygosquad/tap/sweepkey    # app, plus the `sweepkey` CLI on your PATH
```
(The cask template is in [Casks/sweepkey.rb](Casks/sweepkey.rb); publish it in your own tap.)

### Build from source
Requires macOS 26+ and Xcode 27.
```sh
brew install xcodegen
make test    # SweepkeyKit unit tests
make build   # generate the project and build the app (ad-hoc signed)
make cli     # release build of the CLI
scripts/make-dmg.sh   # local Release build packaged as a DMG
```
Local builds have no Sparkle key, so the updater stays disabled and "Check for Updates..." is greyed out.

## Safety model
Sweepkey deletes files, so it is conservative by design.
- **Dry run first.** Nothing is deleted until you have seen the full list and total size and confirmed. The CLI supports `--dry-run`, and refuses to run non-interactively without `--yes`.
- **Git-tracked guard.** A folder containing any git-tracked file is skipped (this protects a deliberately committed `build/` or `dist/`). If git cannot answer, the check fails closed and the folder is skipped.
- **Symlinks are never followed.**
- **Path guards.** Nothing outside a scan root is removed; scan roots themselves, `~`, `/` and system paths are never removed.
- **Pinned and excluded projects.** Pin a project or exclude a path and it is never offered for cleaning.
- **Active projects.** You are warned when a project appears to be open in an editor or terminal.
- **Risk levels.** Items are Safe, Caution or Danger; Danger needs an extra confirmation.
- **Permanent delete by default,** with Move to Trash available per run or as a default in Settings. Sizes are shown as "up to X" because APFS clones may not free all blocks.

## Full Disk Access
Developer projects often live in places macOS protects (Desktop, Documents, Downloads, external volumes). Without Full Disk Access, scanning silently misses those folders and deletions can fail. The onboarding flow links to System Settings so you can grant it; Sweepkey works without it, on the folders it can read. The App Sandbox is off because a sandboxed app cannot clean arbitrary project folders.

## CLI
```sh
sweepkey scan [paths...] [--json] [--stale-only] [--min-size 100MB]
sweepkey clean [paths...] [--dry-run] [--trash] [--stale-only] [--rule <id>]... [--yes] [--skip-vault]
sweepkey caches [--json]
sweepkey caches clean <group-id>... [--dry-run] [--yes]
sweepkey vault collect <paths...> --to <dest> [--format folder|zip|dmg] [--uncommitted] [--scan-contents]
sweepkey vault restore <vault> [--by-remote <searchRoot>...] [--overwrite] [--dry-run]
sweepkey history [--json]
```
Paths default to your configured scan roots. `clean` prints the plan and asks `Proceed? [y/N]` unless `--yes` is given. When **Require a vault export before cleaning** is on in Settings, a real `clean` first exports the affected projects' secrets (folder format, to the vault destination from Settings, with your collect options) and aborts without deleting anything if that export fails; `--skip-vault` bypasses this explicitly. Exit codes: `0` ok, `1` error, `2` nothing to do. Always try `--dry-run` first.

## Privacy
No telemetry, no analytics, no accounts. Everything stays on your Mac, and vault contents leave the machine only if you export them. The only network use is the Sparkle update check, which fetches the appcast from GitHub Releases and is disabled in builds without an update key.

## Releasing (maintainers)
1. Run `scripts/configure-repo.sh <github-owner>` once to replace the `OWNER` placeholder everywhere.
2. Generate Sparkle keys (`generate_keys`) and add GitHub secrets: `DEVELOPER_ID_CERT_P12` (base64), `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `SPARKLE_PRIVATE_KEY`, `SPARKLE_PUBLIC_KEY`.
3. Push a tag `vX.Y.Z`. [release.yml](.github/workflows/release.yml) archives, signs, notarizes, staples, builds the DMG and appcast, creates the GitHub Release, and prints the cask sha256.

`scripts/release.sh` (used by the workflow, runnable locally) also:
- signs with `Config/Sweepkey.entitlements` and `Config/SweepkeyWidgets.entitlements` (`SWEEPKEY_APP_ENTITLEMENTS` / `SWEEPKEY_WIDGET_ENTITLEMENTS`), so the shipped widget is sandboxed and shares the App Group `$(TeamIdentifierPrefix)com.prabhatkumar.Sweepkey` with the app. The Team-ID prefix form works for Developer ID builds without a provisioning profile; both targets read the resolved id from the `SweepkeyAppGroup` Info.plist key;
- refuses to run while `SPARKLE_FEED_URL` (from the environment or `project.yml`) still contains `OWNER`;
- stamps the release version into `SweepkeyVersion.current` (the CLI's `--version`) for the build and passes it to the app as `MARKETING_VERSION`.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md). New cleaning rules are just JSON: [docs/rules.md](docs/rules.md).

## License
MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Prabhat Kumar.
