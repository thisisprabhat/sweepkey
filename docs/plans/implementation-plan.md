# Cleaner — Implementation Plan

Spec: `docs/plans/feature-plan.md` (binding authority). This plan breaks it into tasks that can run in parallel waves.

## Global Constraints

- **Platform**: macOS 26.0+ only. Swift 6 language mode with complete strict concurrency. SwiftUI only (AppKit only where SwiftUI has no API: `NSWorkspace`, `NSOpenPanel`, `NSBackgroundActivityScheduler`).
- **Not sandboxed**: Hardened Runtime ON, App Sandbox OFF. Bundle id `com.prabhatkumar.Cleaner`. App name "Cleaner". Category `public.app-category.developer-tools`.
- **Layout**:
  - `Packages/CleanerKit/` (SwiftPM, `// swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`) holds ALL non-UI logic.
    - Library target `CleanerKit`: `Sources/CleanerKit/<Area>/…`
    - Executable target `CleanerCLI` (product `cleaner`): `Sources/CleanerCLI/`, depends on `swift-argument-parser` (from: "1.5.0").
    - Tests: `Tests/CleanerKitTests/<Area>Tests.swift` using **Swift Testing** (`import Testing`).
    - Resources: `Sources/CleanerKit/Resources/rules.json`, declared `.copy("Resources/rules.json")`.
  - `App/` is the SwiftUI app target. `Widgets/` is the widget extension.
  - `project.yml` is the XcodeGen spec. **`Cleaner.xcodeproj` is generated and git-ignored.** Never commit it; regenerate with `xcodegen generate`.
- **Commands** (Makefile at repo root):
  - `make test`: `cd Packages/CleanerKit && swift test`
  - `make generate`: `xcodegen generate`
  - `make build`: generate, then `xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build`
  - `make cli`: `cd Packages/CleanerKit && swift build -c release --product cleaner`
- **The contract file `Sources/CleanerKit/Core/*.swift` (Task 1) is frozen** for tasks 2–11. A task needing a contract change adds an `extension` in its own area or reports DONE_WITH_CONCERNS. It never edits the Core files.
- **File ownership**: each parallel task touches only the paths listed in its "Owns" line. A task may *read* anything.
- **Safety (spec §D)**:
  - Never follow symlinks.
  - Never delete outside a scan root (global caches excepted, which are under `$HOME` or tool-managed).
  - Never delete a scan root, `$HOME`, `/` or anything under `/System`, `/usr`, `/bin`, `/sbin`, `/Library`, `/Applications`.
  - Never delete a directory containing git-tracked files.
  - Every filesystem-touching type takes injectable root/home URLs so tests run on temp fixture trees. Tests must never touch the real `$HOME`.
- **Liquid Glass**:
  - Glass (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`, `glassEffectID`) goes only on controls and floating chrome, never on content rows or cards.
  - Use the standard `NavigationSplitView` (sidebar becomes glass automatically).
  - No hand-rolled blur imitations. SF Symbols for all icons.
- **Privacy**: no network calls except Sparkle update checks (Task 11). No telemetry. Secret file contents are never logged.
- **Defaults**:
  - delete mode `.permanent`
  - stale after 30 days
  - always-collect list `["pubspec.yaml"]`
  - keep 5 vault versions
  - low-space threshold 20 GB
  - vault file size cap 10 MB
- **Commits**: conventional style (`feat(scanner): …`). End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Waves

| Wave | Tasks (parallel within wave) |
|---|---|
| 0 | Task 1 (Foundation) ‖ Task 12 (docs split) |
| A | Task 2 (Rules+Scanner) ‖ Task 3 (Safety+Cleaning+Journal) ‖ Task 4 (Vault) ‖ Task 5 (Global caches) ‖ Task 6 (App UI with mock services) |
| B | Task 7 (App integration) ‖ Task 8 (CLI) |
| C | Task 9 (Automation) ‖ Task 10 (Insights & recipes) ‖ Task 11 (Release & OSS) |

---

### Task 1: Foundation — repo, contract, shared utilities, app shell

**Owns:** everything at repo root plus `Packages/CleanerKit/Package.swift`, `Sources/CleanerKit/Core/`, `Sources/CleanerKit/Support/`, `Sources/CleanerKit/Resources/rules.json` (as `[]`), `Sources/CleanerCLI/main.swift` (skeleton), `App/` shell, `.github/workflows/ci.yml`.

**Create:**
1. `.gitignore`: `.build/`, `*.xcodeproj`, `DerivedData/`, `.DS_Store`, `.superpowers/`, `xcuserdata/`, `*.dmg`, `.swiftpm/`.
2. `Makefile` with the targets listed in Global Constraints.
3. `project.yml` (XcodeGen):
   - project `Cleaner`, deployment target macOS 26.0
   - local package `CleanerKit` at `Packages/CleanerKit`
   - target `Cleaner` (application, sources `App`), depending on package product `CleanerKit`
   - settings: `PRODUCT_BUNDLE_IDENTIFIER=com.prabhatkumar.Cleaner`, `ENABLE_HARDENED_RUNTIME=YES`, `SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete`, `MARKETING_VERSION=0.1.0`, `CURRENT_PROJECT_VERSION=1`, `GENERATE_INFOPLIST_FILE=YES`, `INFOPLIST_KEY_LSApplicationCategoryType=public.app-category.developer-tools`, `CODE_SIGN_STYLE=Automatic`
   - no sandbox entitlement
   - scheme `Cleaner`
4. `Packages/CleanerKit/Package.swift` matching Global Constraints, with a test target `CleanerKitTests`.
5. **Contract**: `Sources/CleanerKit/Core/Models.swift`, `Core/Protocols.swift` and `Core/Settings.swift` exactly as below. Add `public init`s with the defaults shown, so other modules can construct values. Every type is `public`.

```swift
// Core/Models.swift
public enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable { case safe, caution, danger }  // ordered safe<caution<danger
public enum DeleteMode: String, Codable, Sendable, CaseIterable { case permanent, trash }
public enum CandidateKind: String, Codable, Sendable { case projectArtifact, globalCache }
public enum CleanAction: Codable, Hashable, Sendable {
    case delete                                              // remove/trash Candidate.url
    case command(executable: String, arguments: [String])    // tool-native cleanup (e.g. "docker", ["system","prune","-f"])
}
public struct Ecosystem: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var name: String; public var symbolName: String
    public static let builtIn: [Ecosystem]   // ids below; lookup helper: static func named(_ id: String) -> Ecosystem (falls back to "generic")
}
// builtIn ids (id → name, SF symbol): javascript→"JavaScript/TypeScript","curlybraces"; python→"Python","chevron.left.forwardslash.chevron.right";
// flutter→"Flutter/Dart","bird"; android→"Android","apps.iphone"; jvm→"Java/Kotlin","cup.and.saucer"; rust→"Rust","gearshape.2";
// swift→"Swift/iOS","swift"; go→"Go","hare"; dotnet→".NET","number"; cpp→"C/C++","c.square"; elixir→"Elixir","drop";
// haskell→"Haskell","function"; ruby→"Ruby","diamond"; php→"PHP","p.square"; zig→"Zig","bolt"; scala→"Scala","s.square";
// bazel→"Bazel","shippingbox"; terraform→"Terraform","cloud"; unity→"Unity","cube"; unreal→"Unreal","gamecontroller"; generic→"Other","folder"
public struct Rule: Codable, Hashable, Sendable, Identifiable {
    public var id: String              // "javascript.node_modules"
    public var ecosystemID: String
    public var markers: [String]       // any-of; file names or globs ("*.csproj") that must exist in the project dir
    public var target: String          // relative path from project dir; last segment may be a glob ("cmake-build-*", "*.egg-info"); may contain "/" ("ios/Pods")
    public var risk: RiskLevel
    public var enabledByDefault: Bool
    public var regenerate: String?     // "npm install"
    public var note: String?
}
public struct Candidate: Identifiable, Codable, Hashable, Sendable {
    public var id: String              // "<ruleID>|<url.path>"
    public var url: URL
    public var kind: CandidateKind
    public var title: String           // e.g. "node_modules", "Xcode DerivedData"
    public var ecosystemID: String     // ecosystem id for artifacts; CacheCategory.rawValue for caches
    public var ruleID: String
    public var risk: RiskLevel
    public var sizeBytes: Int64
    public var lastModified: Date?
    public var projectRoot: URL?
    public var regenerateHint: String?
    public var note: String?
    public var action: CleanAction     // default .delete
}
public struct GitInfo: Codable, Hashable, Sendable {
    public var repositoryRoot: URL
    public var remoteURL: String?; public var branch: String?; public var headCommit: String?
    public var lastCommitDate: Date?
    public var isDirty: Bool
    public var unpushedCommitCount: Int?   // nil = no upstream
    public var stashCount: Int
}
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL; public var name: String
    public var ecosystemIDs: [String]
    public var candidates: [Candidate]
    public var git: GitInfo?
    public var lastActivity: Date?
    public var isStale: Bool
    public var reclaimableBytes: Int64 { get }   // sum of candidates
}
public struct ScanOptions: Codable, Hashable, Sendable {
    public var roots: [URL]; public var excludedPaths: [URL] = []
    public var ruleOverrides: [String: Bool] = [:]   // ruleID → enabled
    public var customRules: [Rule] = []
    public var staleAfterDays: Int = 30
    public var includeGitInfo: Bool = true
    public var maxConcurrency: Int = 8
}
public struct ScanProgress: Hashable, Sendable { public var directoriesVisited: Int; public var currentPath: String; public var projectsFound: Int; public var bytesFound: Int64 }
public struct ScanSummary: Codable, Hashable, Sendable { public var projectCount: Int; public var candidateCount: Int; public var totalBytes: Int64; public var startedAt: Date; public var finishedAt: Date }
public enum ScanEvent: Sendable { case progress(ScanProgress), project(Project), finished(ScanSummary) }
public enum SafetyVerdict: Codable, Hashable, Sendable { case allowed, warning(String), blocked(String); public var isAllowed: Bool { get } }  // warning counts as allowed
public enum CleanItemStatus: String, Codable, Sendable { case cleaned, skipped, failed, dryRun }
public struct CleanItemResult: Codable, Hashable, Sendable { public var candidate: Candidate; public var status: CleanItemStatus; public var freedBytes: Int64; public var message: String?; public var trashURL: URL? }
public struct CleanProgress: Hashable, Sendable { public var completed: Int; public var total: Int; public var currentTitle: String; public var freedBytes: Int64 }
public struct CleanReport: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID; public var startedAt: Date; public var finishedAt: Date
    public var mode: DeleteMode; public var dryRun: Bool; public var items: [CleanItemResult]
    public var freedBytes: Int64 { get }  // sum of items' freedBytes where status == .cleaned
}
public enum CacheCategory: String, Codable, Sendable, CaseIterable {
    case xcode, android, packageManager, versionManager, container, browserTesting, ide, aiModels, misc
    public var displayName: String { get }; public var symbolName: String { get }
}
public struct CacheGroup: Identifiable, Hashable, Sendable {
    public var id: String              // provider id, e.g. "xcode.derivedData"
    public var title: String; public var category: CacheCategory; public var symbolName: String
    public var detail: String?         // one-line explanation shown in UI
    public var candidates: [Candidate]
    public var totalBytes: Int64 { get }
}
// Vault
public enum SecretReason: String, Codable, Sendable { case ignoredMatch, untrackedMatch, alwaysCollect, uncommittedWork, contentMatch, patternMatch }
public struct SecretFile: Identifiable, Codable, Hashable, Sendable {
    public var id: String { sourceURL.path }
    public var sourceURL: URL
    public var scanRoot: URL
    public var vaultPath: String          // "<scanRoot.lastPathComponent>/<path relative to scanRoot>", e.g. "Projects/app/android/upload.jks"
    public var reason: SecretReason
    public var matchedRule: String        // pattern / rule that matched
    public var sizeBytes: Int64
    public var modified: Date?
    public var git: GitInfo?
    public var pathInRepository: String?  // relative to git.repositoryRoot
}
public struct VaultCollectOptions: Codable, Hashable, Sendable {
    public var roots: [URL]; public var excludedPaths: [URL] = []
    public var extraPatterns: [String] = []
    public var alwaysCollect: [String] = ["pubspec.yaml"]
    public var includeUncommittedWork: Bool = false
    public var scanContents: Bool = false
    public var maxFileSizeBytes: Int64 = 10_485_760
}
public enum VaultExportFormat: String, Codable, Sendable, CaseIterable { case folder, zip, encryptedImage }
public struct VaultExportRequest: Sendable {
    public var files: [SecretFile]
    public var destination: URL          // .folder: vault directory; .zip/.encryptedImage: output file URL (.zip/.dmg)
    public var format: VaultExportFormat
    public var password: String?         // required for .encryptedImage
    public var keepVersions: Int = 5
}
public struct VaultManifestEntry: Codable, Hashable, Sendable {
    public var vaultPath: String; public var sourcePath: String; public var sha256: String
    public var sizeBytes: Int64; public var modified: Date?; public var collectedAt: Date
    public var reason: SecretReason
    public var gitRemoteURL: String?; public var gitBranch: String?; public var gitHeadCommit: String?
    public var pathInRepository: String?
}
public struct VaultManifest: Codable, Hashable, Sendable { public var formatVersion: Int = 1; public var createdAt: Date; public var hostName: String; public var entries: [VaultManifestEntry] }
public struct VaultExportResult: Codable, Hashable, Sendable { public var outputURL: URL; public var manifest: VaultManifest; public var copiedCount: Int; public var unchangedCount: Int }
public struct OpenedVault: Hashable, Sendable { public var manifest: VaultManifest; public var root: URL; public var mountPoint: URL? }  // mountPoint set for encrypted images
public enum RestoreStrategy: Codable, Hashable, Sendable { case originalPaths, matchGitRemote(searchRoots: [URL]) }
public struct RestoreAction: Identifiable, Codable, Hashable, Sendable {
    public var id: String { entry.vaultPath }
    public var entry: VaultManifestEntry; public var vaultFileURL: URL; public var destinationURL: URL
    public var destinationExists: Bool; public var identical: Bool
}
public struct RestoreResult: Codable, Hashable, Sendable { public var restored: [String]; public var skipped: [String]; public var failed: [String: String] }
```

```swift
// Core/Protocols.swift
public protocol ProjectScanning: Sendable { func scan(_ options: ScanOptions) -> AsyncThrowingStream<ScanEvent, Error> }
public protocol CacheScanning: Sendable { func scanCaches() async -> [CacheGroup] }
public protocol SafetyEvaluating: Sendable { func evaluate(_ candidates: [Candidate], scanRoots: [URL]) async -> [Candidate.ID: SafetyVerdict] }
public protocol CleanExecuting: Sendable {
    func clean(_ candidates: [Candidate], mode: DeleteMode, dryRun: Bool,
               progress: @escaping @Sendable (CleanProgress) -> Void) async -> CleanReport
    func putBack(_ items: [CleanItemResult]) async -> [CleanItemResult]   // restore trashed items to original location
}
public protocol CleanJournaling: Sendable {
    func append(_ report: CleanReport) async throws
    func reports() async throws -> [CleanReport]          // newest first
    func lifetimeFreedBytes() async throws -> Int64
}
public protocol SecretFinding: Sendable { func findSecrets(_ options: VaultCollectOptions) async throws -> [SecretFile] }
public protocol VaultExporting: Sendable { func export(_ request: VaultExportRequest) async throws -> VaultExportResult }
public protocol VaultRestoring: Sendable {
    func open(_ vaultURL: URL, password: String?) async throws -> OpenedVault
    func close(_ vault: OpenedVault) async
    func planRestore(_ vault: OpenedVault, strategy: RestoreStrategy) async throws -> [RestoreAction]
    func restore(_ actions: [RestoreAction], overwrite: Bool) async throws -> RestoreResult
}
```

```swift
// Core/Settings.swift — decoding MUST tolerate missing keys (custom init(from:) using decodeIfPresent ?? default)
public struct VaultSettings: Codable, Hashable, Sendable {
    public var destination: URL? = nil; public var defaultFormat: VaultExportFormat = .folder
    public var alwaysCollect: [String] = ["pubspec.yaml"]; public var extraPatterns: [String] = []
    public var includeUncommittedWork = false; public var scanContents = false; public var keepVersions = 5
}
public struct ScheduleSettings: Codable, Hashable, Sendable {
    public var autoScanEnabled = false; public var autoScanIntervalHours = 24
    public var autoCleanStaleEnabled = false; public var autoCleanIntervalDays = 7
    public var autoVaultSnapshotEnabled = false; public var autoVaultIntervalDays = 7
}
public struct CleanerSettings: Codable, Hashable, Sendable {
    public var scanRoots: [URL] = []; public var excludedPaths: [URL] = []; public var pinnedProjects: [URL] = []
    public var ruleOverrides: [String: Bool] = [:]; public var customRules: [Rule] = []
    public var staleAfterDays = 30; public var defaultDeleteMode: DeleteMode = .permanent
    public var requireVaultBeforeClean = false
    public var vault = VaultSettings()
    public var lowSpaceAlertsEnabled = true; public var lowSpaceThresholdGB = 20
    public var schedule = ScheduleSettings()
    public var showMenuBarExtra = true; public var launchAtLogin = false
    public var hasCompletedOnboarding = false
}
public struct SettingsStore: Sendable {
    public init(fileURL: URL = AppPaths.settingsFile)
    public func load() -> CleanerSettings          // defaults if missing/corrupt
    public func save(_ settings: CleanerSettings) throws   // atomic write, pretty JSON, sorted keys
}
public enum AppPaths {
    public static var applicationSupport: URL     // ~/Library/Application Support/Cleaner (created on access)
    public static var settingsFile: URL           // …/settings.json
    public static var journalFile: URL            // …/journal.json
    public static var scanCacheFile: URL          // …/scan-cache.json
    public static var defaultVaultDirectory: URL  // ~/Documents/Cleaner Vault
}
```

6. **Support utilities** (`Sources/CleanerKit/Support/`), all `public` and tested:
   - `Shell.swift`:
     - `ShellResult {exitCode: Int32, stdout: String, stderr: String, succeeded: Bool}` and `ShellError {executableNotFound(String), timedOut, launchFailed(String)}`.
     - `protocol ShellRunning: Sendable { func run(_ executable: String, arguments: [String], currentDirectory: URL?, input: Data?, timeout: Duration) async throws -> ShellResult }`, plus an extension convenience `run(_ executable: String, _ arguments: [String]) ` with nil/nil/`.seconds(120)`.
     - `ProcessShellRunner`:
       - Resolves a bare executable name by searching `PATH` plus `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `~/.cargo/bin`, `~/.local/bin`, `~/go/bin`.
       - Passes an augmented `PATH` to the child process.
       - Reads stdout and stderr concurrently so a full pipe can't deadlock.
       - Enforces the timeout by terminating the child.
     - Free func `resolveExecutable(_ name: String) -> String?`.
   - `SizeCalculator.swift`:
     - `struct SizeCalculator: Sendable`. `func allocatedSize(of url: URL) -> Int64` is recursive and uses `totalFileAllocatedSizeKey`, falling back to `fileAllocatedSizeKey`. It never follows symlinks (a symlink counts as its own size). Hard links are counted once per call (dedupe on `fileResourceIdentifierKey`). A missing path returns 0.
     - `func allocatedSizes(of urls: [URL], maxConcurrency: Int = 8) async -> [URL: Int64]`.
   - `GitClient.swift`: `struct GitClient: Sendable { init(shell: ShellRunning = ProcessShellRunner(), gitPath: String = "/usr/bin/git") }` with these methods:
     - `func isAvailable() async -> Bool`: true only if `xcode-select -p` succeeds, so we never trigger the CLT install prompt.
     - `func repositoryRoot(containing url: URL) async -> URL?`
     - `func info(forRepository root: URL) async -> GitInfo?`
     - `func hasTrackedFiles(at path: URL, repositoryRoot: URL) async -> Bool`: `git ls-files -z -- <rel>` is non-empty.
     - `func ignoredPaths(repositoryRoot: URL) async throws -> [String]`: `ls-files -z --others --ignored --exclude-standard --directory`. Paths are relative; directories end in `/`.
     - `func untrackedPaths(repositoryRoot: URL) async throws -> [String]`: `ls-files -z --others --exclude-standard`.
   - `FileSystem+Helpers.swift`:
     - `URL.isSymlink`, `URL.isDirectory`, `URL.isDescendant(of:)` (standardized, resolving `..`, not prefix-string tricks).
     - `func modificationDate(_:)`.
     - `Glob.matches(_ pattern: String, _ name: String) -> Bool`, using fnmatch semantics for `*`, `?` and `[...]` on a single path segment.
7. `Sources/CleanerCLI/main.swift`: an ArgumentParser root command `cleaner` with a `--version` printing `0.1.0`. No subcommands yet (Task 8).
8. **App shell** (`App/`):
   - `CleanerApp.swift`: `@main`, a `WindowGroup` with `RootView`, plus a `Settings` scene with a placeholder.
   - `RootView.swift`: `NavigationSplitView`. The sidebar is a `List` of `enum SidebarItem: String, CaseIterable, Identifiable { case dashboard, projects, caches, vault, history, rules }`, with SF Symbols `gauge.with.dots.needle.33percent`, `folder`, `internaldrive`, `lock.shield`, `clock.arrow.circlepath`, `list.bullet.rectangle`. Each detail is a `ContentUnavailableView` placeholder.
   - `App/Assets.xcassets` with an empty AppIcon set and AccentColor.
9. `.github/workflows/ci.yml`: on push/PR, `macos-26` runner (fall back to `macos-latest`). Steps: `brew install xcodegen`, `make test`, then `make build`.
10. `README.md` stub: one paragraph plus build instructions.

**Tests** (`Tests/CleanerKitTests/`):
- `ShellTests`:
  - `echo` round trip
  - non-zero exit code captured
  - stdin input is passed through to `cat`
  - timeout throws `.timedOut` (`sleep 5` with a 0.5 s timeout)
  - output larger than 1 MB doesn't deadlock
- `SizeCalculatorTests`:
  - nested files sum correctly
  - a hard-linked file counts once
  - a symlink to a big file outside the tree doesn't add that file's size
  - a missing path returns 0
- `GitClientTests` (temp repo via `git init`, skip if git unavailable):
  - tracked vs untracked detection
  - `ignoredPaths` lists `.env` and the `node_modules/` dir
  - `info` returns branch and lastCommitDate
  - `unpushedCommitCount` is nil without an upstream
- `SettingsStoreTests`:
  - save/load round trip
  - decoding `{}` gives the defaults
  - decoding with an unknown extra key works
- `GlobTests`: `*.egg-info`, `cmake-build-*`, a literal name, and `?` matching.
- `ModelsTests`: `RiskLevel` ordering, `Candidate` Codable round trip with a `.command` action, `Ecosystem.named("nope").id == "generic"`.

**Accept:** `make test` passes, `make build` succeeds, and the app launches to a sidebar with 6 items.

---

### Task 2: Rules catalog + project scanner

**Owns:** `Sources/CleanerKit/Rules/`, `Sources/CleanerKit/Scanning/`, `Sources/CleanerKit/Resources/rules.json`, `Tests/CleanerKitTests/RulesTests.swift`, `ScannerTests.swift`, `Tests/CleanerKitTests/Fixtures/` (create in code, not on disk).

- `rules.json`: a JSON array of `Rule` covering **every** row of the per-project rules table in spec §B (feature-plan.md). Use the ecosystem ids from `Ecosystem.builtIn`. Rules marked `*` in the spec are `enabledByDefault: false` with `risk: caution`. Everything else is `safe`, except Unity `Library` and Unreal `DerivedDataCache`, which are `caution`. Each rule has its markers, a `regenerate` command, and a `note` where useful. Ambiguous names need specific markers:
  - `build` for Flutter needs `pubspec.yaml`.
  - `build` for Gradle needs any of `build.gradle`, `build.gradle.kts`, `settings.gradle`, `settings.gradle.kts`.
  - `target` for Rust needs `Cargo.toml`.
  - `target` for Maven needs `pom.xml`.
  - `target` for Scala needs `build.sbt`.
  - `vendor` for PHP needs `composer.json`.
- `RuleSet`:
  - `static func bundled() throws -> [Rule]` (from `Bundle.module`)
  - `func effectiveRules(overrides: [String: Bool], custom: [Rule]) -> [Rule]`: enabled rules only, with custom rules appended
  - `func validate(_ rule: Rule) -> [String]`: problems such as an empty id or target, `..` in the target, an absolute path, or no markers
- `RuleMatcher`: given a directory URL and its immediate child names, it returns the matching rules and the resolved target URLs. It supports `/` in the target and a glob on the last segment, and it requires at least one marker to exist in that directory.
- `ProjectScanner: ProjectScanning` with `init(sizer: SizeCalculator = .init(), git: GitClient = .init(), rules: [Rule]? = nil, now: @Sendable () -> Date = Date.init)`:
  - Walk each root breadth-first with bounded concurrency (`maxConcurrency`).
  - Skip hidden system dirs (`.Trash`, `Library` when directly under `$HOME`, `.git` contents), `excludedPaths`, and symlinks.
  - Never descend into a matched target, nor into a `node_modules` folder.
  - A directory with ≥1 matching rule becomes a `Project`, whose `ecosystemIDs` come from the matched rules. Keep descending into that project's other subdirectories, since monorepos contain nested projects, but nested candidates belong to the nearest project dir.
  - Size candidates with `SizeCalculator` (concurrently).
  - Candidate id is `"<ruleID>|<path>"` and `lastModified` is the target's mtime.
  - When `includeGitInfo` is on, call `git.repositoryRoot` + `info` once per repository root (cache them).
  - `lastActivity` = max(git lastCommitDate, mtime of the marker files). `isStale` = lastActivity older than `staleAfterDays` relative to `now()`.
  - Emit `.progress` at most every 100 ms or every 500 dirs, `.project` as each project completes, and `.finished` with the summary. Honor task cancellation.
- `ScanCache`: an actor persisting `[Project]` plus a timestamp to a URL as JSON (default `AppPaths.scanCacheFile`). Methods: `save`, `load`.

**Tests**, using temp fixture trees built in code:
- every bundled rule decodes and passes `validate`; ids are unique
- a JS project gives a `node_modules` candidate
- a `build/` folder with no marker gives no candidate
- a Flutter project gives `build` and `.dart_tool` candidates
- a Rust `target` folder is matched but a `target` folder with no `Cargo.toml` is not
- `cmake-build-debug` matches its glob
- `*.egg-info` matches its glob
- a nested monorepo package gives a separate project
- a symlinked directory is not followed
- an excluded path is skipped
- a disabled override removes the rule
- a custom rule matches
- the stale flag works with an injected `now`
- a candidate's size equals the bytes written (allocated ≥ logical)
- the stream finishes with a correct summary
- cancellation stops the scan

---

### Task 3: Safety guard, clean executor, journal

**Owns:** `Sources/CleanerKit/Cleaning/`, `Tests/CleanerKitTests/SafetyTests.swift`, `CleanExecutorTests.swift`, `JournalTests.swift`.

- `SafetyGuard: SafetyEvaluating`, initialized with `init(git: GitClient = .init(), home: URL = FileManager.default.homeDirectoryForCurrentUser, pinnedProjects: [URL] = [], activeDirectories: @Sendable () async -> [URL] = { [] })`. Rules are checked in this order; the first match wins:
  1. Path is `/`, `home`, a scan root, or under a system prefix (Global Constraints) → `.blocked`.
  2. The candidate URL is a symlink → `.blocked`.
  3. `.projectArtifact` with `.delete`: not a descendant of some scan root → `.blocked`.
  4. `.globalCache` with `.delete`: not a descendant of `home` → `.blocked`, unless it is under `/opt/homebrew` or `/usr/local` and the action is `.command`.
  5. The project is pinned (`projectRoot` is in `pinnedProjects`) → `.blocked("Pinned project")`.
  6. The candidate dir contains git-tracked files → `.blocked("Contains files tracked by git")`. Find the repo via `git.repositoryRoot`; skip this check for global caches.
  7. Risk `.danger` → `.warning("High risk: …")`.
  8. The project root is in, or contains, an active directory → `.warning("Project appears to be open in …")`.
  9. Otherwise `.allowed`.
- `ActiveProjectDetector`:
  - `static func currentWorkingDirectories() async -> [URL]` uses `proc_listallpids` + `proc_pidinfo(PROC_PIDVNODEPATHINFO)` to collect the cwd of the user's processes.
  - Results are filtered to processes named `Xcode`, `Code`, `Cursor`, `Windsurf`, `studio` (Android Studio), `idea`, `zsh`, `bash`, `fish`, `node`, `java`, `gradle`, `dart`, `flutter`.
  - Best effort: permission errors are ignored.
- `CleanExecutor: CleanExecuting`, initialized with `init(shell: ShellRunning = ProcessShellRunner(), sizer: SizeCalculator = .init(), fileManager: FileManagerProtocol wrapper = .default, journal: CleanJournaling? = nil)`:
  - Items run sequentially, in input order.
  - `dryRun` → each item becomes `.dryRun` with `freedBytes = sizeBytes` and nothing is touched.
  - For a `.delete` action:
    - Re-check right before acting that the path exists and is not a symlink. Otherwise → `.skipped`.
    - `.trash` mode uses `FileManager.trashItem(at:resultingItemURL:)` and keeps `trashURL`.
    - `.permanent` mode uses `removeItem`.
    - `freedBytes` = the size measured just before deletion.
  - For a `.command` action: measure the size before, run the command (10 min timeout), measure after, and set `freedBytes = max(0, before - after)`. Non-zero exit → `.failed` with stderr in `message`.
  - Errors on one item never stop the run.
  - Report progress after each item.
  - When a journal is set and not `dryRun`, append the report.
  - `putBack`: for each `.cleaned` item with a `trashURL`, move it back to the original `candidate.url`. If the destination exists → `.failed("Destination exists")`.
- `JSONJournal: CleanJournaling`: an actor storing `[CleanReport]` at a file URL (default `AppPaths.journalFile`). Atomic writes, newest first, capped at 500 reports. `lifetimeFreedBytes` sums the non-dry-run reports.

**Tests** (temp dirs, fake `ShellRunning`, fake git where needed):
- each guard rule, including a fixture git repo with a tracked file inside `dist/` that must be blocked
- a symlink candidate is blocked
- a path outside the roots is blocked
- `$HOME` is blocked
- pinned is blocked
- danger gives a warning
- active dir gives a warning
- the executor:
  - dry run deletes nothing
  - permanent delete removes the item and reports freed bytes
  - trash mode sets `trashURL`, and `putBack` restores it
  - a command action calls the fake shell with the exact args, and a failing exit gives `.failed`
  - an item missing at clean time gives `.skipped`
  - one failure doesn't stop the run
  - the journal is appended
- journal round trip, ordering, and lifetime total

---

### Task 4: Secrets vault

**Owns:** `Sources/CleanerKit/Vault/`, `Tests/CleanerKitTests/Vault*Tests.swift`.

- `SecretPatterns`: `static let defaults: [String]`. These are the file-name globs from spec §F: `.env`, `.env.*`, `.dev.vars`, `*.jks`, `*.keystore`, `key.properties`, `google-services.json`, `GoogleService-Info.plist`, `*.p12`, `*.p8`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision`, `id_rsa*`, `id_ed25519*`, `*.ppk`, `credentials.json`, `service-account*.json`, `secrets.*`, `terraform.tfvars`, `*.tfstate`, `.npmrc`, `.pypirc`, `.netrc`, `sentry.properties`, `master.key`, `appsettings.*.json`, `docker-compose.override.yml`.
  - `optional` (off by default, exposed for the UI): `local.properties`, `.firebaserc`, `.env.example`.
  - `.env.example`, `.env.sample` and `.env.template` are **excluded** unless explicitly added.
- `ContentScanner`: regex rules for AWS access keys (`AKIA[0-9A-Z]{16}`), GitHub tokens (`gh[pousr]_[A-Za-z0-9]{36,}`), Stripe (`sk_live_[0-9a-zA-Z]{24,}`), OpenAI-style (`sk-[A-Za-z0-9_-]{32,}`), Slack (`xox[baprs]-…`), Google API keys (`AIza[0-9A-Za-z_-]{35}`) and `-----BEGIN [A-Z ]*PRIVATE KEY-----`.
  - `func scan(_ url: URL, maxBytes: Int64) -> String?` returns the matched rule name. It skips binary files (a NUL in the first 8 KB). It never returns or logs the secret value.
- `SecretFinder: SecretFinding`, initialized with `init(git: GitClient = .init(), sizer…)`:
  - For each root, find the git repos: dirs containing `.git`, without descending into artifact dirs (`node_modules`, `build`, `.venv`, `target`, `Pods`, `.dart_tool`, `.gradle`, `DerivedData`).
  - **In a git repo**: candidates come from `ignoredPaths` (→ `.ignoredMatch`) and `untrackedPaths` (→ `.untrackedMatch`) whose last path component matches a pattern.
    - An ignored *directory* entry is walked unless its name is one of the artifact dirs above.
    - `alwaysCollect` names match anywhere in the repo, tracked or not (→ `.alwaysCollect`). Find them by walking, skipping artifact dirs.
    - With `includeUncommittedWork`, every untracked file that is not ignored → `.uncommittedWork`.
    - With `scanContents`, untracked or ignored text files under the size cap that `ContentScanner` flags → `.contentMatch`.
  - **Outside git repos** (a plain walk, skipping artifact dirs and symlinks): pattern matches → `.patternMatch`, plus `alwaysCollect`.
  - Skip files larger than `maxFileSizeBytes` and anything under `excludedPaths`.
  - Fill `git` and `pathInRepository`. `vaultPath` = `"<root.lastPathComponent>/<relative to root>"`.
  - The same file is reported once.
- `VaultExporter: VaultExporting`, initialized with `init(shell: ShellRunning = ProcessShellRunner(), now:)`:
  - **folder**:
    - Copy each file to `destination/<vaultPath>`. Create parent dirs with mode `0700` and set file mode `0600`.
    - **Incremental**: skip a file when its sha256 matches the existing copy (counted as `unchangedCount`).
    - **Versions**: before overwriting a changed file, move the old copy to `destination/.versions/<vaultPath>/<ISO8601 timestamp>` and keep only the newest `keepVersions`.
    - Write `destination/manifest.json` (merge entries by vaultPath, keeping the latest).
    - Create an empty `destination/.metadata_never_index`.
  - **zip**: stage a folder export in a temp dir, then run `/usr/bin/ditto -c -k --sequesterRsrc --keepParent <staging> <destination>`.
  - **encryptedImage**: requires a password, otherwise throw `VaultError.passwordRequired`.
    - Stage the folder export, then run `/usr/bin/hdiutil create -srcfolder <staging> -volname "Cleaner Vault" -encryption AES-256 -stdinpass -format UDZO -ov <destination>`, passing the password on stdin.
    - Delete the staging dir afterwards in every case.
  - sha256 uses CryptoKit, streamed in chunks.
- `VaultRestorer: VaultRestoring`:
  - `open`:
    - A folder → read `manifest.json`.
    - A `.zip` → `ditto -x -k` into a temp dir.
    - A `.dmg` → `hdiutil attach -stdinpass -nobrowse -readonly -mountpoint <temp>`, then read the manifest at the mount root.
  - `close` detaches or deletes the temp dir.
  - `planRestore(.originalPaths)` → destination = `entry.sourcePath`.
  - `planRestore(.matchGitRemote(searchRoots:))`:
    - Find git repos under the search roots and read their remote URLs.
    - Normalize the URLs: strip `.git`, `git@host:` becomes `https://host/`, lowercase the host.
    - Map each entry with `gitRemoteURL` + `pathInRepository` to `<matching repo root>/<pathInRepository>`. Unmatched entries are left out.
  - `identical` = the destination exists with the same sha256.
  - `restore`:
    - Create dirs, copy files, set `0600`.
    - Skip identical files.
    - Skip an existing destination unless `overwrite`.
    - Collect failures without stopping.

**Tests** (temp git repos):
- a repo with `.gitignore` containing `.env`, `*.jks` and `node_modules/`, plus files `.env`, `android/app/upload.jks`, `node_modules/x/.env` and a tracked `pubspec.yaml`:
  - finds `.env` (ignoredMatch), `upload.jks` and `pubspec.yaml` (alwaysCollect)
  - does **not** find `node_modules/x/.env`
- `.env.example` is excluded
- a non-git dir gives `.patternMatch`
- `includeUncommittedWork` picks up `notes.txt`
- `ContentScanner` flags an AWS key in an untracked `config.ts` and ignores a binary file
- the size cap is respected
- folder export:
  - mirror layout `Root/app/android/app/upload.jks`
  - mode `0600`
  - manifest sha256 matches
  - a second export of unchanged files gives `copiedCount 0`
  - a change produces a `.versions` copy
  - `keepVersions` pruning works
- zip export can be listed with `zipinfo`
- encrypted image round trip: create, open with the password, restore, compare bytes
  - Guard this test with `.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil"))`.
  - A wrong password throws.
- restore by git remote into a fresh `git clone` of a fixture repo (use a `file://` remote) puts the secrets in the right place
- the conflict and overwrite flags behave as described

---

### Task 5: Global cache providers

**Owns:** `Sources/CleanerKit/Caches/`, `Tests/CleanerKitTests/CacheProviderTests.swift`.

- `protocol CacheProvider: Sendable { var id: String { get }; func detect(_ context: CacheContext) async -> [CacheGroup] }`.
- `struct CacheContext: Sendable { var home: URL; var shell: ShellRunning; var sizer: SizeCalculator; var fileExists: @Sendable (URL) -> Bool }`, plus a `static func live()`.
- `GlobalCacheScanner: CacheScanning`: `init(providers: [CacheProvider] = CacheProviders.all, context: CacheContext = .live())`. Runs the providers concurrently. Groups with no candidates are dropped. Results are sorted by `totalBytes` descending.
- Each group's candidates use `kind: .globalCache`, `ecosystemID: category.rawValue`, a `regenerateHint` (e.g. "Re-downloaded automatically by Gradle") and an appropriate `risk`. Sizes come from the sizer for paths; for command-based items, from the path the command cleans.
- **Providers** (paths are relative to `context.home` unless absolute). Use the tool-native command when its executable resolves (`resolveExecutable`); otherwise fall back to `.delete` of the path.
  - **Xcode** (category `.xcode`):
    - `Library/Developer/Xcode/DerivedData`: one candidate per child folder, safe.
    - `Library/Developer/Xcode/Archives`: one candidate per `.xcarchive`, danger, note "Contains dSYMs needed to symbolicate crash reports".
    - `Library/Developer/Xcode/{iOS,watchOS,tvOS,visionOS} DeviceSupport/*`: per version, safe.
    - `Library/Developer/CoreSimulator/Caches`: safe.
    - `Library/Developer/Xcode/UserData/Previews`: safe.
    - Unavailable simulators: a `.command("xcrun", ["simctl","delete","unavailable"])` candidate, sized as 0 with the note "Size unknown until cleaned". Only shown if `xcrun simctl list devices unavailable -j` returns any.
    - Simulator runtimes: list them with `xcrun simctl runtime list -j`. Each one becomes a caution candidate `.command("xcrun", ["simctl","runtime","delete", <identifier>])`, sized from the JSON `sizeBytes` field when present.
  - **Android** (`.android`):
    - `.gradle/caches`: safe.
    - `.gradle/wrapper/dists/*`: per version; all but the newest version are safe, the newest is caution.
    - `.android/cache`: safe.
    - Android SDK (`$ANDROID_HOME`, or `Library/Android/sdk`): `build-tools/*`, `ndk/*`, `system-images/*/*/*` and `platforms/*` per version; caution for all but the newest of each kind.
    - `.android/avd/*.avd`: danger.
  - **Package managers** (`.packageManager`). Each item is "path → command if available":
    - npm `.npm/_cacache` → `npm cache clean --force`
    - Yarn `Library/Caches/Yarn` → `yarn cache clean`
    - pnpm `Library/pnpm/store` → `pnpm store prune`
    - Bun `.bun/install/cache`
    - pip `Library/Caches/pip` → `pip3 cache purge`
    - uv `.cache/uv` → `uv cache clean`
    - Poetry `Library/Caches/pypoetry`
    - conda `{miniconda3,anaconda3,miniforge3}/pkgs` → `conda clean -a -y`
    - Cargo `.cargo/registry/cache`, `.cargo/registry/src`, `.cargo/git/checkouts`
    - Go `go/pkg/mod` → `go clean -modcache`
    - Maven `.m2/repository` (caution)
    - CocoaPods `Library/Caches/CocoaPods` → `pod cache clean --all`
    - Carthage `Library/Caches/org.carthage.CarthageKit`
    - pub `.pub-cache` (caution) → `flutter pub cache clean -f` if flutter exists, else `dart pub cache clean -f`
    - Composer `Library/Caches/composer`
    - gem `.gem`
    - NuGet `.nuget/packages`
    - Deno `Library/Caches/deno`
    - Homebrew → `brew cleanup --prune=all`, sized from `brew --cache`
  - **Version managers** (`.versionManager`). One candidate per installed version. The active or newest version is danger, the others caution:
    - nvm `.nvm/versions/node/*`, fnm `.local/share/fnm/node-versions/*` (or `Library/Application Support/fnm/node-versions/*`), Volta `.volta/tools/image/node/*`
    - pyenv `.pyenv/versions/*`
    - rustup `.rustup/toolchains/*`
    - SDKMAN `.sdkman/candidates/*/*` (skipping `current`)
    - fvm `fvm/versions/*` and `.fvm/versions/*`
    - asdf `.asdf/installs/*/*`, mise `.local/share/mise/installs/*/*`
  - **Containers** (`.container`): runs only if `docker` resolves and `docker info` succeeds within 5 s.
    - Parse `docker system df --format '{{json .}}'`.
    - Candidates:
      - build cache → `docker builder prune -af`
      - dangling and unused images → `docker image prune -af`
      - stopped containers → `docker container prune -f`
      - unused volumes → `docker volume prune -af`, danger
    - Sizes come from the `Reclaimable` field, parsed from strings like `"1.2GB (40%)"`.
    - Also an info-only group (no candidates, `detail` text) reporting the size of the Docker Desktop disk image: `Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`.
    - OrbStack and Colima use the same `docker` command via the current context.
  - **Browser/testing** (`.browserTesting`): `Library/Caches/ms-playwright`, `.cache/puppeteer`, `Library/Caches/Cypress`, `Library/Caches/electron`, `Library/Caches/node-gyp`, `.node-gyp`.
  - **IDE** (`.ide`):
    - JetBrains: `Library/Caches/JetBrains/*` and `Library/Logs/JetBrains/*`. For a product with several versions, all but the newest are safe.
    - VS Code-family: `{.vscode,.cursor,.windsurf}/extensions`. Group by extension id without the version; older versions are safe.
    - `Library/Application Support/{Code,Cursor}/{Cache,CachedData,CachedExtensionVSIXs}`: safe.
  - **AI models** (`.aiModels`, all danger): `.cache/huggingface/hub/*`, `.ollama/models` (via `ollama rm` per model when `ollama list` works, otherwise one `.delete` candidate for the dir), `.lmstudio/models/*/*` and `.cache/lm-studio/models/*/*`.
  - **Misc** (`.misc`): `Library/Logs/DiagnosticReports` (safe); `Library/Application Support/MobileSync/Backup/*` (danger, note "iOS device backup — cannot be regenerated").
- `CacheProviders.all` lists every provider.

**Tests** use a temp fake home with fixture dirs and a `FakeShell` that records calls and returns scripted outputs:
- DerivedData children become separate candidates with the right sizes
- Archives are danger
- with `npm` resolvable the npm candidate uses the command action, otherwise it falls back to delete
- the Gradle wrapper newest version is caution and the older ones safe
- the nvm version list
- `docker system df` JSON fixture parsing, including the "1.2GB (40%)" format
- the unavailable-simulator candidate shows only when the JSON has entries
- empty groups are dropped
- results are sorted by size
- **no test touches the real `$HOME`**: assert every candidate path starts with the fake home, or is an `.command` action

---

### Task 6: App UI — design system and every screen, using mock services

**Owns:** `App/` except `App/CleanerApp.swift` scene composition (you may edit `RootView.swift` and add files). Add `App/Services/AppServices.swift` and `App/Services/PreviewServices.swift`.

- `AppServices` struct (in App) holds `any ProjectScanning`, `any CacheScanning`, `any SafetyEvaluating`, `any CleanExecuting`, `any CleanJournaling`, `any SecretFinding`, `any VaultExporting`, `any VaultRestoring`, `SettingsStore`.
  - `static let preview: AppServices` uses in-app mock implementations (in `PreviewServices.swift`) that return realistic fake data with small `Task.sleep` delays: ~15 projects across ecosystems, cache groups, journal entries and secret files.
  - The app uses `.preview` until Task 7 swaps in `.live`.
- `@Observable @MainActor final class AppModel`:
  - Settings, plus load/save via the store.
  - Scan state: idle/scanning(progress)/done, projects, cache groups, selection (`Set<Candidate.ID>`), safety verdicts.
  - Clean flow state: confirm → progress → result.
  - Journal, vault findings, and export/restore state.
  - Computed totals and filters (search text, ecosystem, risk, min size, stale only).
  - All service calls are `async` methods. Inject it via `.environment(model)`.
- **DesignSystem/**:
  - `GlassActionBar`: a floating bottom bar in a `GlassEffectContainer`. It shows the selection count and total size, with a `.glassProminent` "Clean" button and a `.glass` "Clear" button, and morphs with `glassEffectID` when shown or hidden.
  - `RiskBadge`, `EcosystemIcon`, `SizeText` (`ByteCountFormatter.file`), `ScanProgressRing` (animated ring + symbol effect), `StatTile`, `SectionHeaderView`, `EmptyStateView`.
- **Features**:
  - `Dashboard/`:
    - free/total disk from `URLResourceValues.volumeAvailableCapacityForImportantUsage` and `volumeTotalCapacity` on the home volume
    - a reclaimable total
    - a Swift Charts `SectorMark` donut by category
    - a top-10 offenders list
    - lifetime freed
    - a "Scan" `.glassProminent` toolbar button
  - `Projects/`:
    - a `Table` grouped by project, with expandable rows showing candidates (use `OutlineGroup`/`DisclosureTableRow`)
    - sortable columns: Name, Ecosystems, Last activity, Reclaimable, Risk
    - multi-select checkboxes
    - `.searchable`, plus a filter menu in the toolbar
    - an `.inspector` showing the selected project's or candidate's details: path, rule, regenerate hint with a copy button, git info, unpushed/stash warnings and safety verdict
    - context menu: Reveal in Finder, Open in Terminal, Copy path, Pin project, Exclude
  - `Caches/`: a sectioned list by `CacheCategory`, with expandable groups, per-item toggles, risk badges, notes, and a "command" chip when the action is `.command`.
  - `Clean/`:
    - `CleanConfirmationSheet`: the item list, total, a Permanent vs Trash `Picker` (default from settings), danger items highlighted, a required acknowledgment toggle when any danger item is present, blocked items listed separately and greyed out, and a "Dry run" button
    - `CleanProgressView`
    - `CleanResultView`: freed total with a celebratory symbol effect, plus failures
  - `Vault/`:
    - collect options (roots, toggles for uncommitted work and content scan, always-collect list editor)
    - a findings table grouped by project, with reason badges and selection
    - export sheet: format picker (Folder/Zip/Encrypted image), destination picker (`NSSavePanel`/`NSOpenPanel`), password + confirm fields for encrypted, an iCloud/Dropbox path warning, and a result view
    - restore flow: open a vault (with a password prompt for .dmg), strategy picker (original paths / match by git remote with search roots), an action table with conflict badges and an overwrite toggle, then results
    - masked preview: the file name and size only, plus a "Reveal in Finder" button. Values are never shown inline.
  - `History/`: a journal list with date, mode, freed and item count, a detail view, a "Put Back" button for trash-mode reports, and a lifetime total header.
  - `Rules/`:
    - a list of the bundled rules grouped by ecosystem, with enable toggles (bound to `ruleOverrides`)
    - a custom rule editor sheet (id, ecosystem picker, markers token field, target, risk, regenerate) with validation messages
  - `Onboarding/`: a 4-step `TabView`-free paged flow: Welcome → pick scan roots → Full Disk Access (explanation, a button to open `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, and a "Check again" button that tests readability of `~/Library/Safari`) → first scan. Shown when `!settings.hasCompletedOnboarding`.
  - `Settings/`: a `Settings` scene with `TabView` tabs General (roots, excluded, stale days, delete mode), Vault, Automation (schedule toggles, low-space threshold, menu bar, launch at login), and Rules. Bind to `AppModel.settings` and save on change.
- Keyboard shortcuts: ⌘R scan, ⌘⌫ clean selection, ⌘I toggle inspector.
- Every view has a `#Preview` using `AppServices.preview`.
- **Accept:** `make build` succeeds with zero warnings in App files, and launching shows a fully navigable UI with mock data and working flows (clean confirm → progress → result) against the mocks.

---

### Task 7: App integration — live services

**Owns:** `App/Services/LiveServices.swift`, minimal edits in `App/` to switch to live services, `App/Platform/` (Finder/Terminal helpers).

- `AppServices.live`:
  - `ProjectScanner`, `GlobalCacheScanner`, `SafetyGuard` (pinned projects from settings, `activeDirectories: ActiveProjectDetector.currentWorkingDirectories`), `CleanExecutor(journal:)`, `JSONJournal`, `SecretFinder`, `VaultExporter`, `VaultRestorer`, `SettingsStore()`.
  - Preview data stays available only for `#Preview`.
- `AppModel`:
  - **Scan**: builds `ScanOptions` from the settings; persists results through `ScanCache` and loads the cache on launch so the window shows the last results immediately.
  - **Safety**: evaluates after each scan and before cleaning.
  - **Vault-before-clean**: when `requireVaultBeforeClean` is on, run a vault collect + folder export to `settings.vault.destination ?? AppPaths.defaultVaultDirectory` for the affected projects before cleaning.
  - **After a clean**: refresh the disk numbers and remove the cleaned candidates from the model (no full rescan).
- `Platform/`:
  - `Finder.reveal(_:)` via `NSWorkspace.activateFileViewerSelecting`
  - `Terminal.open(_:)` (Terminal.app via `NSWorkspace.open` with app URL)
  - `Editor.open(_:)`: VS Code if `code` resolves, else Finder
- Encrypted vault passwords: save to the Keychain (`kSecClassGenericPassword`, service `com.prabhatkumar.Cleaner.vault`, account = destination path), protected with `.userPresence` access control so Touch ID gates reads. Offer "Remember in Keychain".
- Drag-and-drop: dropping folders onto the window or the Dock icon adds scan roots (`onDrop` + `NSApplicationDelegate application(_:open:)`).
- **Accept:** `make build`; a manual run against a fixture dir (create `/tmp`-style fixture projects in the scratch area) scans, shows candidates, cleans in Trash mode, and Put Back works.

### Task 8: CLI

**Owns:** `Sources/CleanerCLI/`, `Tests/CleanerKitTests/CLITests.swift` (test the formatting helpers only).

- Subcommands (ArgumentParser, async):
  - `scan [paths...] [--json] [--stale-only] [--min-size 100MB]`: table output (project, ecosystems, reclaimable, last activity) or JSON `[Project]`.
  - `clean [paths...] [--dry-run] [--trash] [--stale-only] [--rule id]... [--yes]`: scan, run the safety guard, and print a plan. Without `--yes` it prompts `Proceed? [y/N]`, and it refuses on a non-TTY without `--yes`.
  - `caches [--json]` and `caches clean <group-id>... [--dry-run] [--yes]`.
  - `vault collect <paths...> --to <dest> [--format folder|zip|dmg] [--uncommitted] [--scan-contents]`. For dmg, the password is read with `readpassphrase` and confirmed.
  - `vault restore <vault> [--by-remote <searchRoot>...] [--overwrite] [--dry-run]`.
  - `history [--json]`.
- Paths default to the settings' `scanRoots` when omitted. Sizes are human-readable. Exit codes: 0 ok, 1 error, 2 nothing to do.
- Helpers: `parseSize("100MB") -> Int64` and table formatting, with tests.
- **Accept:** `make cli`; `cleaner scan <fixture> --json` gives valid JSON; `cleaner clean <fixture> --dry-run --yes` deletes nothing.

### Task 9: Automation — menu bar, alerts, scheduler, login item, intents, widgets

**Owns:** `App/Automation/`, `App/MenuBar/`, `App/Intents/`, `Widgets/`, the `project.yml` widget target, and scene additions in `App/CleanerApp.swift`.

- `MenuBarExtra` (`.window` style), toggled by `settings.showMenuBarExtra`:
  - a free-space gauge
  - the reclaimable total from the last scan
  - "Quick clean safe items": stale projects' `.safe` candidates plus `.safe` caches, with a confirmation inside the popover
  - the last clean result
  - "Open Cleaner"
- `LowSpaceMonitor`:
  - Checks every 15 min and on wake (`NSWorkspace.didWakeNotification`).
  - When free space is below the threshold, posts a `UNUserNotification` with a "Clean safe items" action, firing at most once every 6 h.
- `Scheduler`: `NSBackgroundActivityScheduler` jobs for auto-scan, auto-clean of stale projects (safe rules only, mode from settings, journaled), and auto vault snapshot (folder format only). Each posts a summary notification. They run only while the app or the login item is running.
- Launch at login via `SMAppService.mainApp.register()/unregister()`, bound to the setting. When launched at login, run as an accessory app (menu bar only) until the user opens the window.
- App Intents (`AppShortcutsProvider`): `ScanProjectsIntent`, `CleanStaleArtifactsIntent(dryRun: Bool)`, `SnapshotSecretsIntent`, `FreeUpSpaceIntent(gigabytes: Int)`. They run headless through CleanerKit and return a string summary.
- URL scheme `cleaner://scan?path=…` and `cleaner://clean-safe` (`CFBundleURLTypes` in `project.yml` info properties).
- Services menu entry "Scan with Cleaner" (`NSServices` in Info.plist, handled by a provider object).
- **Widget extension** `CleanerWidgets` (WidgetKit, small and medium sizes): free space and reclaimable.
  - Data comes from a JSON snapshot the app writes to an App Group container `group.com.prabhatkumar.Cleaner`.
  - Add the app group entitlement to both targets in `project.yml`.
  - The widget target is sandboxed; that is required for widgets.
  - If the build can't sign the app group locally, keep the code but make sure `make build` still succeeds (`CODE_SIGN_IDENTITY=-`), and document it.
- **Accept:** `make build`; the menu bar extra appears; a manual threshold check triggers the notification path (log it).

### Task 10: Insights and one-click recipes

**Owns:** `Sources/CleanerKit/Insights/`, `Sources/CleanerKit/Recipes/`, their tests, `App/Features/Insights/`, `App/Features/Recipes/`, and the Dashboard additions in `App/Features/Dashboard/`.

- `InsightsEngine.suggestions(projects:caches:) -> [Insight]` (`Insight {id, title, detail, symbolName, estimatedBytes}`). Rules:
  - ≥5 `node_modules` → "Switch to pnpm/Bun to deduplicate (N copies, X GB)".
  - ≥3 Python venvs → "Use uv with a global cache".
  - Unavailable simulators or old runtimes exist → suggest them.
  - DerivedData > 10 GB.
  - Docker reclaimable > 5 GB.
  - Stale projects total > 10 GB.
- `FreeUpPlanner.plan(target: Int64, projects:caches:verdicts:) -> [Candidate]`:
  - Greedy, ordered: stale `.safe` project artifacts by size desc, then `.safe` caches, then non-stale `.safe` artifacts, then `.caution` (only if still short).
  - Never includes `.danger` or blocked items.
  - Stops once the target is met.
- `ArchiveRecipe.run(project:vaultDestination:archiveDirectory:zip:)`:
  1. vault collect + folder export for the project
  2. clean its artifacts (permanent)
  3. optionally `ditto -c -k --keepParent` the project into the archive directory, verify the zip, and only then move the original to the Trash
  - Returns a step-by-step report.
- `MigrationBundle.export(roots:to:)`:
  - Writes `repos.json` (path, remote, branch for every repo) next to a vault export.
  - `MigrationBundle.cloneScript(...)` generates a `restore.sh` that clones each repo to the same relative path; after cloning, the user runs a vault restore by remote.
- `PreArchiveCheck.risks(projects:)`: dirty repos, unpushed commits, stashes.
- App:
  - an Insights card list on the Dashboard
  - a Recipes sidebar section (add `.recipes` to `SidebarItem`, symbol `wand.and.stars`) with Free up X GB (a slider/field → planned list → clean sheet), Archive project, and New-Mac migration
  - a treemap view: a custom `Canvas` squarified treemap of reclaimable space by project or by ecosystem, with hover tooltips
  - a trend chart from the journal
- **Tests**:
  - the planner's ordering and target stop
  - the planner excludes danger and blocked items
  - each insight's thresholds
  - the archive recipe on a fixture (fake shell) only trashes after the zip is verified
  - the migration repos.json content

### Task 11: Release, updates, open-source hygiene

**Owns:** `LICENSE` (MIT, "Prabhat Kumar"), `README.md` (full), `CONTRIBUTING.md`, `docs/rules.md` (how to add a rule + JSON schema), `.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md`, `.github/workflows/release.yml`, `scripts/release.sh`, `scripts/make-dmg.sh`, `Casks/cleaner.rb` (template), `App/Updates/`, and the Sparkle package entry in `project.yml`.

- Sparkle 2 via SPM (`https://github.com/sparkle-project/Sparkle`, from 2.6.0).
  - `UpdaterController` wraps `SPUStandardUpdaterController`, with a "Check for Updates…" menu command.
  - `SUFeedURL` = `https://github.com/<owner>/cleaner/releases/latest/download/appcast.xml` (placeholder owner), and `SUPublicEDKey` comes from a build setting.
  - With no key configured the updater is disabled.
- `release.yml`, on tag `v*`:
  1. import the signing cert from secrets
  2. archive
  3. export with Developer ID
  4. notarize (`xcrun notarytool submit --wait`) and staple
  5. build the DMG with `scripts/make-dmg.sh` (`hdiutil` with an Applications symlink)
  6. sign the appcast (`generate_appcast`)
  7. create the GitHub Release with the DMG and appcast
  8. print the cask sha256
- README:
  - features, screenshots placeholder, install (DMG, Homebrew cask, build from source)
  - the Full Disk Access explanation
  - a safety model summary, CLI usage, privacy statement and license
- **Accept:** `make build` still succeeds; `scripts/make-dmg.sh` produces a DMG from a local Release build (ad-hoc signed).

### Task 12: Split the spec into docs/

**Owns:** `docs/*.md` (not `docs/plans/`).

Split `docs/plans/feature-plan.md` into the files listed in its "Delivery phases" step 0: `docs/README.md` index and `docs/01-features.md` through `docs/10-open-source-release.md`. Keep the content faithful and expand it into clear developer documentation. Each file links back to the index. `docs/02-cleaning-rules.md` documents the `Rule` JSON schema exactly as defined in Task 1's contract. `docs/07-architecture.md` describes the module layout and protocols from Task 1.
