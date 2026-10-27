# Cleaner: developer documentation

Cleaner is a native macOS 26+ SwiftUI app that (1) safely reclaims disk space from regenerable developer junk and (2) collects non-regenerable, non-git files (secrets) into a vault before anything is deleted or archived.

## Index

| Doc | Contents |
|---|---|
| [01-features.md](01-features.md) | Feature overview, sections A to K |
| [02-cleaning-rules.md](02-cleaning-rules.md) | Per-project rules, global caches, Rule JSON schema |
| [03-safety.md](03-safety.md) | Safety system and cleaning execution |
| [04-secrets-vault.md](04-secrets-vault.md) | Detection, patterns, mirror layout, manifest, export, restore |
| [05-automation-and-insights.md](05-automation-and-insights.md) | Menu bar, scheduler, widgets, intents, CLI, recipes, insights |
| [06-ui-design.md](06-ui-design.md) | Liquid Glass and HIG guidelines, screens |
| [07-architecture.md](07-architecture.md) | Module layout, protocols, key types |
| [08-roadmap.md](08-roadmap.md) | Delivery phases and task waves |
| [09-testing.md](09-testing.md) | Verification strategy |
| [10-open-source-release.md](10-open-source-release.md) | License, CI, notarization, Sparkle, Homebrew |

The original spec is `plans/feature-plan.md`; the task breakdown is `plans/implementation-plan.md`.

## Context

Dev projects pile up regenerable junk (`node_modules`, `.venv`, `build/`, `target/`, DerivedData, Gradle/npm/pub caches) and trigger low-storage warnings. Cleaner reclaims that space safely. Before anything is deleted or a project is archived, it collects the files that cannot be regenerated and are not in git (`.env`, `.jks`, keystores, `key.properties`, `google-services.json`, `pubspec.yaml`, ...) into a mirror of the original tree (`<root>/dir1/dir1/file.jks`).

## Decisions

- Personal use, also released as open source. Distributed outside the App Store (Developer ID, notarized, no App Sandbox) so it can walk `~/` and call `git`, `docker`, `xcrun`, `brew`.
- Default delete mode is permanent delete, with a per-clean "Move to Trash" toggle.
- Vault export format is chosen per export: plain folder, `.zip`, or encrypted disk image.
- Target is macOS 26 Tahoe or later, SwiftUI with native Liquid Glass.

## Defaults

Delete mode `permanent`; stale after 30 days; always-collect list `["pubspec.yaml"]`; keep 5 vault versions; low-space threshold 20 GB; vault file size cap 10 MB. Privacy: everything stays local, no telemetry; the only network use is Sparkle update checks.
