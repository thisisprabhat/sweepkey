# Architecture

← [Index](README.md)

## Module layout
```
cleaner/
├─ project.yml                     XcodeGen spec (Cleaner.xcodeproj is generated, git-ignored)
├─ App/                            SwiftUI app target (macOS 26+, Swift 6 strict concurrency)
│  ├─ Features/{Dashboard,Projects,GlobalCaches,Vault,History,Rules,Settings,Onboarding}
│  ├─ MenuBar/                     MenuBarExtra + low-space monitor
│  ├─ Intents/                     App Intents
│  └─ DesignSystem/                glass components, size formatters, risk badges
├─ Widgets/                        WidgetKit extension
├─ Packages/CleanerKit/            Swift package: all logic, no UI, unit-tested
│  ├─ Sources/CleanerKit/
│  │  ├─ Core/       frozen contract: Models, Protocols, Settings
│  │  ├─ Support/    Shell, SizeCalculator, GitClient, FileSystem helpers
│  │  ├─ Scanning/   walker, ProjectDetector, FSEvents watcher
│  │  ├─ Rules/      RuleSet, RuleMatcher
│  │  ├─ Resources/  rules.json
│  │  ├─ Cleaning/   SafetyGuard, CleanExecutor (remove/trash), Journal
│  │  ├─ Caches/     CacheProvider + one provider per tool
│  │  ├─ Vault/      SecretDetector, ContentScanner, writers, Manifest, Restorer
│  │  └─ Store/      persisted scan snapshots, clean records, vault snapshots
│  ├─ Sources/CleanerCLI/   `cleaner` executable (swift-argument-parser)
│  └─ Tests/CleanerKitTests/
└─ .github/workflows/
```
Package: `swift-tools-version: 6.2`, `.macOS(.v26)`; tests with Swift Testing in `Tests/CleanerKitTests`. Bundle id `com.prabhatkumar.Cleaner`; Hardened Runtime on, App Sandbox off (Full Disk Access via onboarding).

## Key choices
- All logic lives in `CleanerKit`, shared by the app, CLI, widgets and intents, with one test suite.
- The `Core/` contract is frozen after Task 1; later work extends via `extension`s in its own area.
- `Rule` and cache providers both produce one `Candidate` type, so the UI, safety guard and journal treat every item alike. `CleanAction` is `.delete` or `.command(executable:arguments:)`.
- `CacheProvider: Sendable` has `var id: String { get }` and `func detect(_ context: CacheContext) async -> [CacheGroup]`. Providers only detect: they emit `Candidate`s whose `action` is `.delete` or `.command(executable:arguments:)`, preferring the tool's own command when its executable resolves. Cleaning is done by `CleanExecuting` (`CleanExecutor`), not by the provider.
- Settings persist as JSON (`SettingsStore`, tolerant of missing keys) under `~/Library/Application Support/Cleaner` (`AppPaths`: settings, journal, scan cache); default vault dir `~/Documents/Cleaner Vault`. Vault passwords go in Keychain.
- `GitClient` runs `/usr/bin/git` via `Process` and detects missing Command Line Tools without triggering the install prompt.
- `ProcessShellRunner` resolves executables on an augmented PATH, drains stdout/stderr concurrently, and enforces timeouts.

## Protocols (Core/Protocols.swift)
| Protocol | Method(s) |
|---|---|
| `ProjectScanning` | `scan(ScanOptions) -> AsyncThrowingStream<ScanEvent, Error>` |
| `CacheScanning` | `scanCaches() async -> [CacheGroup]` |
| `SafetyEvaluating` | `evaluate(candidates, scanRoots) -> [Candidate.ID: SafetyVerdict]` |
| `CleanExecuting` | `clean(candidates, mode, dryRun, progress) -> CleanReport`; `putBack(items)` |
| `CleanJournaling` | `append(report)`, `reports()` (newest first), `lifetimeFreedBytes()` |
| `SecretFinding` | `findSecrets(VaultCollectOptions) -> [SecretFile]` |
| `VaultExporting` | `export(VaultExportRequest) -> VaultExportResult` |
| `VaultRestoring` | `open`, `close`, `planRestore(strategy)`, `restore(actions, overwrite)` |

## Key types (Core/Models.swift)
`RiskLevel`, `DeleteMode`, `CandidateKind`, `CleanAction`, `Ecosystem`, `Rule`, `Candidate`, `GitInfo`, `Project`, `ScanOptions`, `ScanEvent` (progress, project, finished), `SafetyVerdict`, `CleanReport`, `CacheCategory`, `CacheGroup`, `SecretFile`, `VaultCollectOptions`, `VaultExportFormat` (`folder`, `zip`, `encryptedImage`), `VaultManifest`, `RestoreStrategy` (`originalPaths`, `matchGitRemote`). Settings types: `CleanerSettings`, `VaultSettings`, `ScheduleSettings`.

Commands (Makefile): `make test`, `make generate`, `make build`, `make cli`.
