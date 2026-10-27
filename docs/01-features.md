# Features

← [Index](README.md)

Overview of the feature set. Details live in the linked documents.

## A. Scanning and detection
- Multiple scan roots (drag and drop or folder picker), remembered between launches.
- Marker-based project detection: a folder is a candidate only when a marker file proves its type (for example `build/` only counts next to `build.gradle`, `pubspec.yaml` or `CMakeLists.txt`). See [02](02-cleaning-rules.md).
- Fast parallel walker with bounded TaskGroup concurrency; never descends into a matched artifact. Sizes use `totalFileAllocatedSize`, hard links are counted once (inode dedupe), symlinks are never followed.
- Live streaming results with a running reclaimable counter; scans are cancellable.
- Incremental rescans: results cached locally; FSEvents marks changed folders so a rescan only redoes those.
- Project metadata: last git commit date, last modified, branch, remote URL, dirty state, unpushed commits, stashes, ecosystem icons.
- Staleness score: projects untouched for N days (default 30) are flagged "Stale, safe to clean".

## B. Per-project cleaning rules
Data-driven JSON rules. See [02](02-cleaning-rules.md).

## C. Global developer caches
Xcode, Android, package managers, version managers, containers, browser/test tools, IDEs, AI/ML models (opt-in), misc. See [02](02-cleaning-rules.md).

## D. Safety system
Dry run first, git-tracked guard, path guards, active-project guard, vault-before-clean, risk badges, regenerate hints, APFS-clone aware sizes. See [03](03-safety.md).

## E. Cleaning execution
Permanent delete or Trash, progress, journal/history, undo via Put Back, auto rescan with free-space delta. See [03](03-safety.md).

## F. Secrets vault
Git-aware detection, patterns, mirror layout, manifest, three export formats, versions, restore by path or git remote, vault browser. See [04](04-secrets-vault.md).

## G. Combined workflows
Archive project, Free up X GB, New-Mac migration, pre-clean safety pass. See [05](05-automation-and-insights.md).

## H. Monitoring and automation
Menu bar extra, low-space alert, scheduled jobs, widgets, App Intents, CLI companion, Finder integration. See [05](05-automation-and-insights.md).

## I. Insights
Dashboard, treemap/sunburst, suggestions. See [05](05-automation-and-insights.md).

## J. App experience
Liquid Glass UI, sidebar, table plus inspector, onboarding, keyboard shortcuts, accessibility, localization. See [06](06-ui-design.md).

## K. Open-source project hygiene
MIT license, CI, notarized releases, Sparkle 2, Homebrew. See [10](10-open-source-release.md).
