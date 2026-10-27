# Cleaning rules and global caches

← [Index](README.md)

## Per-project rules

Rules are data (JSON), not code, so the community can add more. A rule only matches when one of its marker files exists in the project directory.

| Ecosystem | Targets (matched only when the marker is present) |
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

`*` = off by default or medium risk, because these folders are sometimes committed or hand-written.

Ambiguous names get specific markers: Flutter `build` needs `pubspec.yaml`; Gradle `build` needs a `build.gradle[.kts]` or `settings.gradle[.kts]`; Rust `target` needs `Cargo.toml`; Maven `target` needs `pom.xml`; Scala `target` needs `build.sbt`; PHP `vendor` needs `composer.json`.

### Rule JSON schema

A rule is the JSON encoding of the `Rule` struct (`Core/Models.swift`). The bundled catalog is a JSON array of rules at `Sources/SweepkeyKit/Resources/rules.json`.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Unique id, e.g. `"javascript.node_modules"` |
| `ecosystemID` | string | One of the built-in ecosystem ids (below); unknown ids fall back to `generic` |
| `markers` | string[] | Any-of file names or globs (`"*.csproj"`) that must exist in the project directory |
| `target` | string | Path relative to the project dir. The last segment may be a glob (`cmake-build-*`, `*.egg-info`); may contain `/` (`ios/Pods`) |
| `risk` | `"safe"` \| `"caution"` \| `"danger"` | Ordered safe < caution < danger |
| `enabledByDefault` | bool | Whether the rule is on without a user override |
| `regenerate` | string? | Command that rebuilds the target, e.g. `"npm install"` |
| `note` | string? | Extra explanation shown in the UI |

Example:

```json
{
  "id": "rust.target",
  "ecosystemID": "rust",
  "markers": ["Cargo.toml"],
  "target": "target",
  "risk": "safe",
  "enabledByDefault": true,
  "regenerate": "cargo build",
  "note": "Cargo build output"
}
```

Validation (`RuleSet.validate`) reports an empty id or target, `..` in the target, an absolute target path, or no markers.

Built-in ecosystem ids: `javascript`, `python`, `flutter`, `android`, `jvm`, `rust`, `swift`, `go`, `dotnet`, `cpp`, `elixir`, `haskell`, `ruby`, `php`, `zig`, `scala`, `bazel`, `terraform`, `unity`, `unreal`, `generic`.

Catalog conventions: `*` rules are `enabledByDefault: false` with `risk: caution`; everything else is `safe`, except Unity `Library` and Unreal `DerivedDataCache`, which are `caution`.

### Customization
- Custom rule editor: add a rule with a marker, globs and risk level (validated with `RuleSet.validate`; a `.git` target is rejected). A live preview of what it would match, and rule import/export, are planned for v1.1 ([08](08-roadmap.md)).
- Per-rule enable/disable overrides (`ruleOverrides`, ruleID to enabled) and custom rules (`customRules`) are stored in settings.
- Per-project `.sweepkeyignore` and a global exclude list. Projects can be pinned so they are never cleaned.

## Global developer caches (outside projects)

Where a tool has its own cleanup command, use it instead of deleting files by hand; it is safer and keeps the tool's indexes consistent.

- **Xcode**: DerivedData, Archives (warn that dSYMs live there), iOS/watchOS/tvOS/visionOS DeviceSupport, `xcrun simctl delete unavailable`, old simulator runtimes (`xcrun simctl runtime`), Previews, documentation cache, module caches.
- **Android**: `~/.gradle/caches`, old `~/.gradle/wrapper/dists`, `~/.android/cache`. Old SDK build-tools, NDK and system-images versions are removable, each picked from a list. AVDs are listed with sizes.
- **Package managers**: JS (npm `_cacache`, Yarn v1/berry, `pnpm store prune`, Bun); Python (pip, uv, Poetry, conda `pkgs`); Rust (Cargo registry and git); Go (`go clean -modcache`); JVM (Maven `~/.m2`); Apple (CocoaPods, Carthage); Flutter/Dart (`~/.pub-cache` via `flutter pub cache clean`); Composer, gem, NuGet, Deno, `brew cleanup`.
- **Version managers**: list installed versions with sizes and remove old ones: nvm, fnm, Volta, pyenv, rustup toolchains, SDKMAN, fvm, asdf, mise.
- **Containers**: Docker, OrbStack, Colima. `docker system df` for the breakdown; prune images, build cache, stopped containers and dangling volumes. Show the `Docker.raw` size.
- **Browsers and test tools**: Playwright, Puppeteer, Cypress, Electron, node-gyp caches.
- **IDEs**: JetBrains caches, logs and old version folders; old VS Code, Cursor and Windsurf extension versions and caches.
- **AI/ML models (opt-in, high risk)**: Hugging Face cache, Ollama models, LM Studio models.
- **Misc**: crash and diagnostic reports (`~/Library/Logs/DiagnosticReports`, Caution, opt-in: hidden unless enabled in Settings > General > Caches, also honoured by the CLI) and iOS device backups in `MobileSync` (Danger, strong warning). `~/Library/Caches/*` dev-tool items are planned for v1.1 ([08](08-roadmap.md)).
- **Risk of tool-native cleanups**: `docker image prune -af` and `docker container prune -f` are Caution (they remove locally built images and stopped containers' changes), as is `~/.gem` (user-installed gems, not just a download cache). The Homebrew item runs `brew cleanup --prune=all`, which also removes old installed formula versions, and says so.

Each provider produces `Candidate`s grouped into a `CacheGroup` by `CacheCategory` (`xcode`, `android`, `packageManager`, `versionManager`, `container`, `browserTesting`, `ide`, `aiModels`, `misc`). A candidate's `action` is `.delete` or `.command(executable:arguments:)` for tool-native cleanup (for example `docker system prune -f`). See [07](07-architecture.md).
