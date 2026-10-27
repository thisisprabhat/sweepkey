# Cleaner — native macOS dev-disk cleaner + secrets vault

## Context
You keep hitting low-storage warnings because dev projects pile up regenerable junk (`node_modules`, `.venv`, `build/`, `target/`, DerivedData, Gradle/npm/pub caches…). You want one native macOS app that (1) safely reclaims that space and (2) before anything is deleted or a project is archived, collects the files that **can't** be regenerated and aren't in git (`.env`, `.jks`, keystores, `key.properties`, `google-services.json`, `pubspec.yaml`, …) into a mirror of the original tree (`<root>/dir1/dir1/file.jks`).

Decisions you made:
- Personal use, also released as **open source** → distributed outside the App Store (Developer ID + notarized, **no App Sandbox**, so it can walk `~/`, call `git`, `docker`, `xcrun`, `brew`).
- Default delete mode: **permanent delete**, with a per-clean "Move to Trash" toggle.
- Vault export: **user picks per export** (plain folder, `.zip`, or encrypted disk image).
- Target: **macOS 26 Tahoe+**, SwiftUI + native Liquid Glass. You're on macOS 27 / Xcode 27.

`/Users/prabhatkumar/Projects/utils/cleaner` is empty, so this is a new project.

---

## 1. Full feature set

### A. Scanning and detection
- **Scan roots**: let the user pick multiple roots (e.g. `~/Projects`, `~/StudioProjects`, `~/Developer`) by drag and drop or with a folder picker. Remember them between launches.
- **Project detection from marker files**: a folder is only a candidate when a marker file proves its type. For example, `build/` is only deleted if `build.gradle`, `pubspec.yaml` or `CMakeLists.txt` sits next to it. This stops the app from deleting a random folder that happens to be named `build`.
- **Fast parallel walker**: walk the tree with bounded TaskGroup concurrency and never descend into a matched artifact. Sizes use `totalFileAllocatedSize`. Hard links are counted once (deduplicated by inode). Symlinks are never followed.
- **Live streaming results**: projects appear while the scan is still running. A running "reclaimable" counter updates as it goes, and the scan can be cancelled.
- **Incremental rescans**: cache results in a local store. FSEvents marks folders that changed so a rescan only redoes those.
- **Project metadata**: for each project show the last git commit date, last modified time, branch, remote URL, dirty state, unpushed commits and stashes, and its ecosystem icons.
- **Staleness score**: flag projects untouched for N days (configurable; default 30) as "Stale, safe to clean".

### B. Built-in cleaning rules, per project
Rules are data (JSON), not code, so the community can add more. Each rule has: `id`, `ecosystem`, marker files, target globs, a regenerate command, a risk level, and enabled-by-default.

| Ecosystem | Targets (only matched when the marker is present) |
|---|---|
| JS/TS (package.json) | `node_modules`, `.next`, `.nuxt`, `.output`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.vite`, `.angular/cache`, `.expo`, `.docusaurus`, `storybook-static`, `coverage`, `.vercel`, `.netlify`, `dist`* |
| Python (pyproject/requirements/setup.py) | `.venv`, `venv`, `env`*, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.nox`, `*.egg-info`, `build`, `dist`*, `.ipynb_checkpoints` |
| Flutter/Dart (pubspec.yaml) | `build`, `.dart_tool`, `ios/Pods`, `ios/.symlinks`, `macos/Pods`, `android/.gradle`, `android/app/build`, `.flutter-plugins*` |
| Android/Gradle/Kotlin | `build`, `.gradle`, `.kotlin`, `.cxx`, `.externalNativeBuild`, `out` |
| Maven (pom.xml) | `target` |
| Rust (Cargo.toml) | `target` |
| Swift/iOS | `.build` (SwiftPM), `Pods`, `Carthage/Build`, `DerivedData` kept inside the project |
| Go | `bin`*, `vendor`* |
| .NET | `bin`, `obj` |
| C/C++/CMake | `build`, `cmake-build-*`, `CMakeFiles` |
| Others | Elixir `_build`/`deps`, Haskell `.stack-work`/`dist-newstyle`, Ruby `vendor/bundle`/`.bundle`, PHP `vendor`, Zig `.zig-cache`/`zig-out`, Scala `.bloop`/`.metals`/`target`, Bazel `bazel-*`, Terraform `.terraform`, Unity `Library`/`Temp`/`Obj`, Unreal `Intermediate`/`Binaries`/`DerivedDataCache` |

\* = off by default or marked medium risk, because these folders are sometimes committed or hand-written.

- **Custom rule editor** in Settings: add a rule with a marker, globs and risk level, and live-preview what it would match. Rules can be imported and exported.
- **Per-project ignore file** `.cleanerignore` and a global exclude list. You can also **pin** a project so it is never cleaned.

### C. Global developer caches (outside projects)
Where a tool has its own cleanup command, use that command instead of deleting files by hand. It is safer and keeps the tool's indexes consistent.
- **Xcode**: DerivedData, Archives (warn that dSYMs live there), iOS/watchOS/tvOS/visionOS DeviceSupport, `xcrun simctl delete unavailable`, removing old simulator runtimes (`xcrun simctl runtime`), Previews, the documentation cache and module caches.
- **Android**: `~/.gradle/caches`, old `~/.gradle/wrapper/dists`, `~/.android/cache`. Old SDK build-tools, NDK and system-images versions can be removed, with each version picked from a list. AVDs are listed with their sizes.
- **Package managers**:
  - JS: npm `_cacache`, Yarn (v1 and berry), `pnpm store prune`, Bun
  - Python: pip, uv, Poetry, conda `pkgs`
  - Rust: Cargo registry and git caches
  - Go: `go clean -modcache`
  - JVM: Maven `~/.m2`
  - Apple: CocoaPods, Carthage
  - Flutter/Dart: `~/.pub-cache` (via `flutter pub cache clean`)
  - Others: Composer, gem, NuGet, Deno, `brew cleanup`
- **Version managers**: list installed versions with their sizes and let you remove old ones. Covers nvm, fnm, Volta, pyenv, rustup toolchains, SDKMAN, fvm (Flutter), asdf and mise.
- **Containers**: Docker, OrbStack and Colima. Use `docker system df` for the breakdown and prune images, build cache, stopped containers and dangling volumes. Show the size of the `Docker.raw` disk image.
- **Browsers and test tools**: Playwright browsers, Puppeteer, Cypress, Electron and node-gyp caches.
- **IDEs**: JetBrains caches, logs and old version folders. Also old VS Code, Cursor and Windsurf extension versions and their caches.
- **AI/ML models (opt-in, high risk)**: Hugging Face cache, Ollama models, LM Studio models.
- **Misc (opt-in)**: `~/Library/Caches/*` for dev tools, CrashReporter and diagnostic logs, iOS device backups in `MobileSync` (strong warning).

### D. Safety system (non-negotiable)
- Dry run is the default first step. Nothing is deleted until a confirmation sheet has shown the full list and total size.
- **Git-tracked guard**: if a target folder contains any file tracked by git (`git ls-files <dir>`), skip it and explain why. This protects a `build/` or `dist/` folder that was committed on purpose.
- **Path guards**: never delete outside a scan root, never delete a scan root itself, `~`, `/` or system paths, and never follow a symlink.
- **Active-project guard**: warn when a project is open in Xcode, VS Code, Android Studio or a terminal. This is checked by looking at the working directories of running processes (`proc_pidinfo`).
- **Vault-before-clean**: optionally require a secrets snapshot of a project before its artifacts can be cleaned.
- Risk badges (Safe, Caution, Danger). Danger items need an extra confirmation.
- Show the **"How to regenerate"** command for every item (`npm install`, `flutter pub get`, `pod install`…), with a copy button.
- APFS-clone awareness: label sizes as "up to X freed", because cloned blocks may not actually be freed.

### E. Cleaning execution
- Permanent delete (default) or Move to Trash, chosen per run, with a global default in Settings.
- Progress with a per-item status. Cancellable. Locked or permission-denied items are reported but don't stop the run.
- **Journal / history**: a record of every clean (what, where, size, mode, time). Shows **lifetime space reclaimed**. Trash-mode runs can be undone with "Put Back".
- Rescan automatically after a clean and show the free-space delta before and after.

### F. Secrets vault: collect what git doesn't have
- **Git-aware detection**:
  - For git repos, take the candidates from `git ls-files --others --ignored --exclude-standard` (ignored files) and `--others --exclude-standard` (untracked files), then match them against the sensitive patterns below. Ignored files never touch `node_modules`, `build` or other artifact folders, because those are skipped.
  - Folders that aren't git repos fall back to plain pattern matching.
- **Default sensitive patterns**:
  - **Env files**: `.env`, `.env.*` (`.env.example` is optional), `.dev.vars`
  - **Android and Flutter signing**: `*.jks`, `*.keystore`, `key.properties`, `local.properties`*
  - **Firebase**: `google-services.json`, `GoogleService-Info.plist`, `.firebaserc`*
  - **Certificates and keys**: `*.p12`, `*.p8`/`AuthKey_*.p8`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision`, `id_rsa*`, `*.ppk`
  - **Cloud and service credentials**: `credentials.json`, `service-account*.json`, `secrets.*`, `terraform.tfvars`, `*.tfstate`, `.npmrc`, `.pypirc`, `.netrc`, `sentry.properties`
  - **Framework config**: `config/master.key` (Rails), `appsettings.*.json`, `docker-compose.override.yml`, Fastlane `.env*`
- **"Always collect" list**: files collected even when git tracks them. It starts with **`pubspec.yaml`**, as you asked, and you can edit it.
- **"Uncommitted work" mode (optional)**: also collect any untracked file that isn't ignored, so work you never committed isn't lost when an old project is archived.
- **Content scanner (optional)**: regex and entropy rules in the style of gitleaks, applied to untracked text files. Catches AWS keys, GitHub, Stripe or OpenAI tokens and `-----BEGIN PRIVATE KEY-----` blocks hiding in files the name patterns miss.
- **Mirror layout**: `Vault/<scanRootName>/<relative/project/path>/<file>`, which keeps your `projectRoot/dir1/dir1/file.jks` layout. Unix permissions are kept, and copied secret files are set to `0600`.
- **`manifest.json`** stored in the vault, with one entry per file: source path, SHA-256, size, mtime, git remote URL, branch, HEAD commit, and collected-at time.
- **Export formats, chosen each time**:
  1. Plain folder (gets `.metadata_never_index` so Spotlight doesn't index your secrets)
  2. `.zip`
  3. **Encrypted disk image** made with `hdiutil` (AES-256 sparsebundle or DMG). Any Mac can open it without this app. The password can be saved in Keychain behind Touch ID (LocalAuthentication).
- **Incremental sync and versions**: copy only files whose hash changed, and keep the last N versions of each file. A diff view shows what changed since the last snapshot.
- **Restore**:
  - Restore a file to its original path.
  - Restore by **git remote**: after a fresh clone on a new Mac, the app matches the clone by remote URL and puts its secrets back in place. This also handles projects whose folder moved.
- **Vault browser**: a tree view with values masked by default, reveal and copy on demand, and Quick Look.
- Warnings when the vault destination is in a cloud-synced folder (iCloud Drive or Dropbox) while using plain-folder mode.

### G. Combined workflows ("one-click recipes")
- **Archive project**: snapshot its secrets, clean its artifacts, and optionally zip the whole project and move it to an archive location.
- **Free up X GB**: you enter a target, the app proposes the safest set of items that reaches it (stale projects and safe caches first), and you review it.
- **New-Mac migration**: export the vault and a list of repos (remote URLs and branches) as a bundle. On the new Mac, clone the repos and restore their secrets.
- **Pre-clean safety pass**: report repos with unpushed commits or stashes before they get archived.

### H. Monitoring and automation
- **Menu bar extra** with a glass popover: free space gauge, reclaimable total, "Quick clean safe items" and the last clean.
- **Low-space alert**: when free space drops below a threshold (`volumeAvailableCapacityForImportantUsage`), send a notification with a one-tap action to clean safe items.
- **Scheduled jobs**: run in the background with `NSBackgroundActivityScheduler` and a login item (`SMAppService`). They can do a nightly scan, a weekly auto-clean of stale projects limited to safe rules, and periodic vault snapshots. Each run ends with a summary notification.
- **WidgetKit** desktop and Notification Center widgets showing free space and reclaimable space.
- **App Intents / Shortcuts / Spotlight actions**: "Scan Projects", "Clean stale node_modules", "Snapshot secrets", "Free up 20 GB".
- **CLI companion `cleaner`**, sharing the same core: `scan`, `clean --dry-run`, `vault collect`, `vault restore`, `caches`, `--json` output. Installable through the Homebrew formula.
- **Finder integration**: drop a folder onto the Dock icon or the window, use the Services menu entry "Scan with Cleaner", and open `cleaner://scan?path=` URLs.

### I. Insights
- **Dashboard**: the disk volume broken down as "dev junk vs. everything else", a top-10 list of offenders, and a reclaimable-over-time trend chart built with Swift Charts.
- **Treemap / sunburst** of reclaimable space grouped by project, ecosystem or category.
- **Suggestions**: for example, "42 copies of `node_modules` (18 GB). Switching to pnpm or Bun would deduplicate them", "uv instead of pip venvs", or "12 simulators for unavailable runtimes".

### J. App experience (Liquid Glass, macOS HIG)
- `NavigationSplitView` sidebar (automatically glass on 26) with: **Dashboard, Projects, Global Caches, Vault, History, Rules**, plus Settings.
- Content uses a sortable, multi-select `Table` with a reclaimable size column, plus an `.inspector` side panel for item details: paths, rule, regenerate command, git info.
- Glass is used only on controls and navigation, never on content: toolbar `.buttonStyle(.glass)`, and the primary **Clean** action uses `.glassProminent`. A floating selection bar inside a `GlassEffectContainer` shows "12 items · 23.4 GB · Clean". Morphing transitions use `glassEffectID`.
- The scan view has an animated progress ring and SF Symbols 7 symbol effects. A confirmation sheet summarizes the run, and there is a short success animation with the amount of space freed.
- `.searchable` filtering, plus filters for ecosystem, risk, age and size.
- Onboarding:
  1. Welcome
  2. Pick scan roots
  3. Guided **Full Disk Access** setup, with a deep link to System Settings and a re-check
  4. First scan
- Full keyboard shortcuts (⌘R rescan, ⌘⌫ clean, Space for Quick Look), Reveal in Finder, Open in Terminal or editor, VoiceOver labels, Dynamic Type, and the system accent color. The interface is localizable (String Catalog).
- Privacy: everything stays local and there is no telemetry. Secrets never leave the machine unless you export them.

### K. Open-source project hygiene
- MIT license, README with screenshots, CONTRIBUTING, a rules contribution guide (rules are JSON, so they're easy to PR), and issue and PR templates.
- GitHub Actions: build, unit tests, SwiftLint/SwiftFormat. On tag: archive, sign, **notarize**, staple, publish a DMG to GitHub Releases, and update the Sparkle 2 appcast and the Homebrew cask.
- Sparkle 2 for in-app updates (EdDSA-signed).

---

## 2. Architecture

```
cleaner/
├─ Cleaner.xcodeproj               (folder-synchronized groups → minimal pbxproj churn)
├─ App/                            SwiftUI app target (macOS 26+, Swift 6 strict concurrency)
│  ├─ Features/{Dashboard,Projects,GlobalCaches,Vault,History,Rules,Settings,Onboarding}
│  ├─ MenuBar/                     MenuBarExtra + low-space monitor
│  ├─ Intents/                     App Intents
│  └─ DesignSystem/                glass components, size formatters, risk badges
├─ Widgets/                        WidgetKit extension
├─ Packages/CleanerKit/            Swift package: all logic, no UI, fully unit-tested
│  ├─ Scanning/    FileWalker, SizeCalculator (inode dedupe), ProjectDetector, FSEventsWatcher
│  ├─ Rules/       Rule model, RuleEngine, Resources/rules/*.json
│  ├─ Cleaning/    SafetyGuard, Deleter (remove/trash), Journal
│  ├─ Caches/      CacheProvider protocol + one provider per tool (Xcode, Gradle, Docker, npm…)
│  ├─ Git/         GitClient (runs /usr/bin/git via Process; detects missing CLT)
│  ├─ Vault/       SecretDetector, ContentScanner, VaultWriter{Folder,Zip,EncryptedImage}, Manifest, Restorer
│  ├─ Shell/       async Process runner with timeout + output streaming
│  └─ Store/       SwiftData models: ScanSnapshot, CleanRecord, VaultSnapshot
├─ CLI/                            `cleaner` executable (swift-argument-parser) on CleanerKit
└─ .github/workflows/
```

Key choices:
- **All logic lives in `CleanerKit`**, so the app, the CLI, the widgets and the intents share a single implementation and one test suite.
- `CacheProvider` protocol: `detect() → [CacheItem]`, `size()`, `clean(items, mode)`. A provider prefers the tool's own command and falls back to deleting files.
- `Rule` and `CacheProvider` both produce one `Candidate` type, so the UI, `SafetyGuard` and the journal handle every kind of item the same way.
- Settings use `@AppStorage`/UserDefaults. History and snapshots use SwiftData. Vault passwords are kept in Keychain.
- No App Sandbox and Hardened Runtime on, which notarization requires. Full Disk Access is requested through onboarding.

---

## 3. Delivery phases
0. **Docs first (your request)**: write this plan into `./docs/` in the repo as Markdown files, one per area, so the plan is versioned with the code:
   - `docs/README.md`: index, context and decisions
   - `docs/01-features.md`: overview of sections A–K
   - `docs/02-cleaning-rules.md`: the per-project rules table, the global caches and the rule JSON schema
   - `docs/03-safety.md`: the safety system
   - `docs/04-secrets-vault.md`: detection, patterns, layout, manifest, export formats, restore
   - `docs/05-automation-and-insights.md`: menu bar, scheduler, widgets, intents, CLI, recipes, insights
   - `docs/06-ui-design.md`: Liquid Glass and HIG guidelines, screens
   - `docs/07-architecture.md`: module layout and key types
   - `docs/08-roadmap.md`: phases
   - `docs/09-testing.md`: the verification strategy
   - `docs/10-open-source-release.md`: license, CI, notarization, Sparkle, Homebrew
1. **Foundation**: repo, Xcode project, the `CleanerKit` package, CI, the app shell with sidebar navigation and Liquid Glass components.
2. **MVP clean**:
   - walker, rules engine with the top ecosystems (JS, Python, Flutter, Android, Rust, Swift/iOS, Maven)
   - SafetyGuard
   - Projects view, confirmation sheet, delete/trash, journal
   - CLI `scan`/`clean`
3. **Vault**: git-aware detection, patterns plus the always-collect list (`pubspec.yaml`), mirror layout, manifest, the three export formats, restore (by path and by git remote).
4. **Global caches**: providers for Xcode, simulators, Gradle and SDK, package managers, Docker and version managers.
5. **Automation**: menu bar extra, low-space alert, scheduler, login item, notifications, widgets, App Intents.
6. **Insights and recipes**: dashboard charts, treemap, suggestions, Archive project, Free up X GB, New-Mac migration, content scanner, remaining ecosystems.
7. **Release**: onboarding polish, accessibility, localization scaffolding, notarized DMG, Sparkle, Homebrew cask, docs.

---

## 4. Verification
- **Unit tests (Swift Testing) in CleanerKit** build fixture trees in a temp folder. They cover:
  - one fake project per ecosystem, with checks that each rule matches only when its marker is present
  - a `build/` folder with no marker is never matched
  - a symlink pointing outside the root is not followed
  - a committed `dist/` folder (temp git repo) is rejected by the git-tracked guard
  - hard links are counted once
- **Vault tests**:
  - make a temp git repo with a `.gitignore`d `.env`, a `.jks` and a tracked `pubspec.yaml`
  - collect, then check the mirror layout, the manifest hashes and the `0600` permissions
  - re-clone the repo, restore by remote, and check the bytes match
  - round-trip the encrypted image (`hdiutil attach` with the password)
- **Cache provider tests**: inject a fake shell runner and check that the right native commands are issued (`docker system prune …`, `xcrun simctl delete unavailable`).
- **CLI smoke test**: run `cleaner scan ~/Projects --dry-run --json` on the real machine and compare the reported sizes with `du -sh` on a few targets.
- **UI**: run the app and walk through onboarding → scan → select → dry run → clean in Trash mode → Put Back from History. Do the same for vault export in each format. Add XCUITest coverage for the main flow.
- **Release check**: run `spctl -a -vv` and `stapler validate` on the notarized DMG, and test a Sparkle update from the previous build.
