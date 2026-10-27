# Safety system and cleaning execution

← [Index](README.md)

Safety is non-negotiable.

## Safety system
- **Dry run first.** Nothing is deleted until a confirmation sheet has shown the full list and total size.
- **Git-tracked guard.** If a target folder contains any git-tracked file (`git ls-files <dir>`), skip it and explain why. This protects a deliberately committed `build/` or `dist/`.
- **Path guards.** Never delete outside a scan root (global caches excepted: they live under `$HOME` or are tool-managed). Never delete a scan root itself, `~`, `/`, or system paths (`/System`, `/usr`, `/bin`, `/sbin`, `/Library`, `/Applications`). Never follow a symlink.
- **Active-project guard.** Warn when a project is open in Xcode, VS Code, Android Studio or a terminal, by checking working directories of running processes (`proc_pidinfo`).
- **Vault-before-clean.** Optionally require a secrets snapshot of a project before its artifacts can be cleaned (`requireVaultBeforeClean`).
- **Risk badges** Safe, Caution, Danger. Danger items need an extra confirmation.
- **"How to regenerate"** command shown for every item (`npm install`, `flutter pub get`, `pod install`, ...) with a copy button.
- **APFS-clone awareness.** Sizes are labelled "up to X freed" since cloned blocks may not be freed.

`SafetyEvaluating` returns a `SafetyVerdict` per candidate: `allowed`, `warning(reason)` (still allowed) or `blocked(reason)`.

## Cleaning execution
- Permanent delete (default) or Move to Trash, chosen per run, with a global default in Settings.
- Progress with per-item status; cancellable. Locked or permission-denied items are reported but do not stop the run.
- **Journal / history**: every clean is recorded (what, where, size, mode, time), including lifetime space reclaimed. Trash-mode runs can be undone with Put Back.
- After a clean, rescan automatically and show the free-space delta before and after.

Item statuses: `cleaned`, `skipped`, `failed`, `dryRun`. A `CleanReport` holds the mode, whether it was a dry run, and one `CleanItemResult` per candidate (with `trashURL` for Trash mode).

## Implementation rules
Every filesystem-touching type takes injectable root/home URLs so tests use temp fixture trees and never the real `$HOME`. Secret file contents are never logged.
