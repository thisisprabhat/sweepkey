# Roadmap

← [Index](README.md)

## Delivery phases
0. **Docs first**: this documentation set (Task 12).
1. **Foundation**: repo, Xcode project, `CleanerKit` package, CI, app shell with sidebar and glass components.
2. **MVP clean**: walker, rules engine for top ecosystems (JS, Python, Flutter, Android, Rust, Swift/iOS, Maven), SafetyGuard, Projects view, confirmation sheet, delete/trash, journal, CLI `scan`/`clean`.
3. **Vault**: git-aware detection, patterns plus always-collect (`pubspec.yaml`), mirror layout, manifest, three export formats, restore by path and git remote.
4. **Global caches**: Xcode, simulators, Gradle and SDK, package managers, Docker, version managers.
5. **Automation**: menu bar extra, low-space alert, scheduler, login item, notifications, widgets, App Intents.
6. **Insights and recipes**: dashboard charts, treemap, suggestions, Archive project, Free up X GB, New-Mac migration, content scanner, remaining ecosystems.
7. **Release**: onboarding polish, accessibility, localization scaffolding, notarized DMG, Sparkle, Homebrew cask, docs.

## Implementation waves
| Wave | Tasks (parallel within wave) |
|---|---|
| 0 | Task 1 Foundation, Task 12 Docs split |
| A | Task 2 Rules + scanner, Task 3 Safety + cleaning + journal, Task 4 Vault, Task 5 Global caches, Task 6 App UI with mock services |
| B | Task 7 App integration (live services), Task 8 CLI |
| C | Task 9 Automation, Task 10 Insights and recipes, Task 11 Release and OSS |

Rough mapping: phase 1 is Task 1; phase 2 is Tasks 2, 3, 6, 7, 8; phase 3 is Task 4; phase 4 is Task 5; phase 5 is Task 9; phase 6 is Task 10; phase 7 is Task 11.

Each task owns a fixed set of paths, and the `Core/` contract is frozen from Wave A onward. See `plans/implementation-plan.md`.

## v1.1 (moved out of v1)
These spec features are not in v1. They were moved to v1.1 at the final v1 review:
- **Quick Look** for items and vault files (and the Space shortcut for it).
- **Vault diff view**: what changed since the last snapshot. (v1 keeps the last N versions in `.versions/`, without a diff UI.)
- **Vault reveal and copy**: unmasking and copying secret values in the vault browser. (v1 shows masked previews only.)
- **Custom-rule live preview**: showing what a custom rule would match while editing it.
- **Rule import and export**.
- **`~/Library/Caches` dev-tool items** in the Misc cache group.
- **Automatic Homebrew cask update** on release. (v1's release workflow prints the cask version and sha256 for a manual update.)
