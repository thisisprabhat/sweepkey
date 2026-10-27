import SweepkeyKit
import Foundation

/// Realistic fake data for previews and the mock-backed app.
enum MockData {
    static let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
    private static let mb: Int64 = 1_048_576

    private struct Art {
        var rule: String
        var title: String
        var eco: String
        var target: String
        var risk: RiskLevel
        var mb: Int64
        var regen: String?
    }

    private static func project(
        _ name: String, _ ecos: [String], daysAgo: Int, _ arts: [Art],
        dirty: Bool = false, unpushed: Int? = 0, stash: Int = 0, noGit: Bool = false
    ) -> Project {
        let url = home.appendingPathComponent("Projects/\(name)", isDirectory: true)
        let last = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        let candidates = arts.map { art in
            Candidate(
                id: "\(art.rule)|\(url.appendingPathComponent(art.target).path)",
                url: url.appendingPathComponent(art.target), kind: .projectArtifact,
                title: art.title, ecosystemID: art.eco, ruleID: art.rule, risk: art.risk,
                sizeBytes: art.mb * mb, lastModified: last, projectRoot: url,
                regenerateHint: art.regen, note: nil)
        }
        let git = noGit ? nil : GitInfo(
            repositoryRoot: url, remoteURL: "git@github.com:demo/\(name).git", branch: "main",
            headCommit: "a1b2c3d", lastCommitDate: last, isDirty: dirty,
            unpushedCommitCount: unpushed, stashCount: stash)
        return Project(
            url: url, name: name, ecosystemIDs: ecos, candidates: candidates, git: git,
            lastActivity: last, isStale: daysAgo > 30)
    }

    static let projects: [Project] = [
        project("web-dashboard", ["javascript"], daysAgo: 2, [
            Art(rule: "javascript.node_modules", title: "node_modules", eco: "javascript", target: "node_modules", risk: .safe, mb: 612, regen: "npm install"),
            Art(rule: "javascript.next", title: ".next", eco: "javascript", target: ".next", risk: .safe, mb: 180, regen: "npm run build"),
            Art(rule: "javascript.dist", title: "dist", eco: "javascript", target: "dist", risk: .caution, mb: 24, regen: "npm run build"),
        ], dirty: true, unpushed: 2),
        project("api-gateway", ["javascript"], daysAgo: 9, [
            Art(rule: "javascript.node_modules", title: "node_modules", eco: "javascript", target: "node_modules", risk: .safe, mb: 480, regen: "pnpm install"),
        ]),
        project("client-portal", ["javascript"], daysAgo: 4, [
            Art(rule: "javascript.node_modules", title: "node_modules", eco: "javascript", target: "node_modules", risk: .safe, mb: 350, regen: "yarn install"),
        ]),
        project("ml-experiments", ["python"], daysAgo: 45, [
            Art(rule: "python.venv", title: ".venv", eco: "python", target: ".venv", risk: .danger, mb: 2100, regen: "python -m venv .venv && pip install -r requirements.txt"),
            Art(rule: "python.pycache", title: "__pycache__", eco: "python", target: "src/__pycache__", risk: .safe, mb: 12, regen: nil),
            Art(rule: "python.ipynb", title: ".ipynb_checkpoints", eco: "python", target: "notebooks/.ipynb_checkpoints", risk: .safe, mb: 8, regen: nil),
        ], dirty: true, unpushed: nil, stash: 1),
        project("flutter_shop", ["flutter", "android", "swift"], daysAgo: 6, [
            Art(rule: "flutter.build", title: "build", eco: "flutter", target: "build", risk: .safe, mb: 950, regen: "flutter build"),
            Art(rule: "flutter.dart_tool", title: ".dart_tool", eco: "flutter", target: ".dart_tool", risk: .safe, mb: 120, regen: "flutter pub get"),
            Art(rule: "android.gradle", title: ".gradle", eco: "android", target: "android/.gradle", risk: .safe, mb: 340, regen: "./gradlew build"),
            Art(rule: "swift.pods", title: "Pods", eco: "swift", target: "ios/Pods", risk: .safe, mb: 260, regen: "pod install"),
        ]),
        project("android-notes", ["android"], daysAgo: 70, [
            Art(rule: "android.build", title: "build", eco: "android", target: "app/build", risk: .safe, mb: 410, regen: "./gradlew assemble"),
            Art(rule: "android.gradle", title: ".gradle", eco: "android", target: ".gradle", risk: .safe, mb: 220, regen: "./gradlew build"),
        ]),
        project("rust-cli", ["rust"], daysAgo: 12, [
            Art(rule: "rust.target", title: "target", eco: "rust", target: "target", risk: .safe, mb: 3400, regen: "cargo build"),
        ]),
        project("game-engine", ["cpp"], daysAgo: 20, [
            Art(rule: "cpp.build", title: "build", eco: "cpp", target: "build", risk: .safe, mb: 880, regen: "cmake -B build && cmake --build build"),
        ], dirty: true, unpushed: 5, stash: 2),
        project("ios-fitness", ["swift"], daysAgo: 3, [
            Art(rule: "swift.build", title: ".build", eco: "swift", target: ".build", risk: .safe, mb: 540, regen: "swift build"),
            Art(rule: "swift.derived", title: "DerivedData", eco: "swift", target: "DerivedData", risk: .safe, mb: 760, regen: "xcodebuild build"),
        ]),
        project("go-services", ["go"], daysAgo: 15, [
            Art(rule: "go.vendor", title: "vendor", eco: "go", target: "vendor", risk: .caution, mb: 90, regen: "go mod vendor"),
        ]),
        project("kotlin-backend", ["jvm"], daysAgo: 33, [
            Art(rule: "jvm.build", title: "build", eco: "jvm", target: "build", risk: .safe, mb: 300, regen: "./gradlew build"),
            Art(rule: "jvm.gradle", title: ".gradle", eco: "jvm", target: ".gradle", risk: .safe, mb: 150, regen: "./gradlew build"),
        ]),
        project("terraform-infra", ["terraform"], daysAgo: 100, [
            Art(rule: "terraform.dotterraform", title: ".terraform", eco: "terraform", target: ".terraform", risk: .caution, mb: 210, regen: "terraform init"),
        ]),
        project("unity-platformer", ["unity"], daysAgo: 120, [
            Art(rule: "unity.library", title: "Library", eco: "unity", target: "Library", risk: .caution, mb: 4200, regen: "Reopen the project in Unity"),
            Art(rule: "unity.temp", title: "Temp", eco: "unity", target: "Temp", risk: .safe, mb: 35, regen: nil),
        ], noGit: true),
        project("dotnet-billing", ["dotnet"], daysAgo: 8, [
            Art(rule: "dotnet.bin", title: "bin", eco: "dotnet", target: "src/bin", risk: .safe, mb: 60, regen: "dotnet build"),
            Art(rule: "dotnet.obj", title: "obj", eco: "dotnet", target: "src/obj", risk: .safe, mb: 45, regen: "dotnet restore"),
        ]),
        project("ruby-blog", ["ruby"], daysAgo: 200, [
            Art(rule: "ruby.bundle", title: "vendor/bundle", eco: "ruby", target: "vendor/bundle", risk: .caution, mb: 190, regen: "bundle install"),
        ]),
        project("elixir-chat", ["elixir"], daysAgo: 55, [
            Art(rule: "elixir.build", title: "_build", eco: "elixir", target: "_build", risk: .safe, mb: 140, regen: "mix compile"),
            Art(rule: "elixir.deps", title: "deps", eco: "elixir", target: "deps", risk: .caution, mb: 80, regen: "mix deps.get"),
        ]),
        project("old-prototype", ["javascript"], daysAgo: 400, [
            Art(rule: "javascript.node_modules", title: "node_modules", eco: "javascript", target: "node_modules", risk: .safe, mb: 700, regen: "npm install"),
        ], noGit: true),
    ]

    private static func cache(
        _ id: String, _ title: String, _ cat: CacheCategory, _ symbol: String, _ detail: String,
        _ items: [(String, Int64, RiskLevel, CleanAction, String?)]
    ) -> CacheGroup {
        let candidates = items.map { item in
            Candidate(
                id: "\(id)|\(item.0)", url: home.appendingPathComponent("Library/Caches/\(item.0)"),
                kind: .globalCache, title: item.0, ecosystemID: cat.rawValue, ruleID: id,
                risk: item.2, sizeBytes: item.1 * mb, note: item.4, action: item.3)
        }
        return CacheGroup(id: id, title: title, category: cat, symbolName: symbol, detail: detail, candidates: candidates)
    }

    static let cacheGroups: [CacheGroup] = [
        cache("xcode.derivedData", "Derived Data", .xcode, "hammer", "Build products and indexes for every project.", [
            ("DerivedData/ios-fitness", 2100, .safe, .delete, "Rebuilt on next build."),
            ("DerivedData/flutter_shop", 1400, .safe, .delete, nil),
            ("DerivedData/Other", 1300, .safe, .delete, nil),
        ]),
        cache("xcode.deviceSupport", "iOS Device Support", .xcode, "iphone", "Symbols copied from connected devices.", [
            ("iOS DeviceSupport/18.2", 3200, .caution, .delete, "Re-downloaded when a device reconnects."),
        ]),
        cache("xcode.simulators", "Unavailable Simulators", .xcode, "ipad", "Simulators for runtimes that are no longer installed.", [
            ("simctl unavailable", 5100, .caution, .command(executable: "xcrun", arguments: ["simctl", "delete", "unavailable"]), nil),
        ]),
        cache("android.gradleCaches", "Gradle Caches", .android, "apps.iphone", "Downloaded dependencies and build caches.", [
            ("~/.gradle/caches", 3000, .safe, .delete, "Dependencies are re-downloaded."),
        ]),
        cache("pm.npm", "npm cache", .packageManager, "shippingbox", "Cached tarballs from the npm registry.", [
            ("~/.npm/_cacache", 1700, .safe, .delete, nil),
        ]),
        cache("pm.pnpm", "pnpm store", .packageManager, "shippingbox", "Content-addressable package store.", [
            ("pnpm/store", 4300, .caution, .delete, "Hard-linked into projects; removing it is safe but slow to refill."),
        ]),
        cache("pm.homebrew", "Homebrew", .packageManager, "mug", "Old downloads and outdated formula versions.", [
            ("brew cleanup", 900, .safe, .command(executable: "brew", arguments: ["cleanup", "--prune=all"]), nil),
        ]),
        cache("vm.nvm", "Node versions", .versionManager, "square.stack.3d.up", "Installed Node.js versions managed by nvm.", [
            ("nvm/v16.20.2", 210, .caution, .delete, "Unused for 6 months."),
            ("nvm/v18.19.0", 230, .caution, .delete, nil),
        ]),
        cache("container.docker", "Docker", .container, "cube.box", "Stopped containers, dangling images and build cache.", [
            ("docker system prune", 8200, .caution, .command(executable: "docker", arguments: ["system", "prune", "-f"]), "Running containers are kept."),
        ]),
        cache("browser.playwright", "Playwright browsers", .browserTesting, "globe", "Downloaded Chromium, Firefox and WebKit builds.", [
            ("ms-playwright", 1800, .safe, .delete, nil),
        ]),
        cache("ide.jetbrains", "JetBrains caches", .ide, "chevron.left.forwardslash.chevron.right", "Indexes and logs for JetBrains IDEs.", [
            ("JetBrains/IntelliJIdea", 1200, .safe, .delete, nil),
        ]),
        cache("ai.huggingface", "Hugging Face models", .aiModels, "brain", "Downloaded model weights.", [
            ("huggingface/hub", 9600, .danger, .delete, "Large downloads; re-fetching may be slow."),
        ]),
    ]

    private static func secret(_ project: String, _ path: String, _ reason: SecretReason, _ rule: String, _ kb: Int64, dirty: Bool = false) -> SecretFile {
        let root = home.appendingPathComponent("Projects", isDirectory: true)
        let repo = root.appendingPathComponent(project, isDirectory: true)
        return SecretFile(
            sourceURL: repo.appendingPathComponent(path), scanRoot: root,
            vaultPath: "Projects/\(project)/\(path)", reason: reason, matchedRule: rule,
            sizeBytes: kb * 1024, modified: Date().addingTimeInterval(-86_400 * 3),
            git: GitInfo(repositoryRoot: repo, remoteURL: "git@github.com:demo/\(project).git", branch: "main", isDirty: dirty),
            pathInRepository: path)
    }

    static let secrets: [SecretFile] = [
        secret("flutter_shop", "android/upload.jks", .ignoredMatch, "*.jks", 4),
        secret("flutter_shop", "android/key.properties", .ignoredMatch, "key.properties", 1),
        secret("flutter_shop", "pubspec.yaml", .alwaysCollect, "pubspec.yaml", 1),
        secret("web-dashboard", ".env.local", .ignoredMatch, ".env*", 2),
        secret("web-dashboard", "config/service-account.json", .contentMatch, "private_key", 3),
        secret("api-gateway", ".env", .untrackedMatch, ".env*", 1),
        secret("ios-fitness", "GoogleService-Info.plist", .patternMatch, "GoogleService-Info.plist", 2),
        secret("ml-experiments", "notes/draft.py", .uncommittedWork, "uncommitted", 6, dirty: true),
    ]

    static let rules: [Rule] = [
        Rule(id: "javascript.node_modules", ecosystemID: "javascript", markers: ["package.json"], target: "node_modules", risk: .safe, enabledByDefault: true, regenerate: "npm install"),
        Rule(id: "javascript.next", ecosystemID: "javascript", markers: ["next.config.js", "next.config.mjs"], target: ".next", risk: .safe, enabledByDefault: true, regenerate: "npm run build"),
        Rule(id: "javascript.dist", ecosystemID: "javascript", markers: ["package.json"], target: "dist", risk: .caution, enabledByDefault: false, regenerate: "npm run build", note: "Might be committed output."),
        Rule(id: "python.venv", ecosystemID: "python", markers: ["requirements.txt", "pyproject.toml"], target: ".venv", risk: .danger, enabledByDefault: false, regenerate: "python -m venv .venv"),
        Rule(id: "python.pycache", ecosystemID: "python", markers: ["*.py"], target: "__pycache__", risk: .safe, enabledByDefault: true),
        Rule(id: "flutter.build", ecosystemID: "flutter", markers: ["pubspec.yaml"], target: "build", risk: .safe, enabledByDefault: true, regenerate: "flutter build"),
        Rule(id: "rust.target", ecosystemID: "rust", markers: ["Cargo.toml"], target: "target", risk: .safe, enabledByDefault: true, regenerate: "cargo build"),
        Rule(id: "swift.build", ecosystemID: "swift", markers: ["Package.swift"], target: ".build", risk: .safe, enabledByDefault: true, regenerate: "swift build"),
        Rule(id: "go.vendor", ecosystemID: "go", markers: ["go.mod"], target: "vendor", risk: .caution, enabledByDefault: false, regenerate: "go mod vendor"),
        Rule(id: "jvm.build", ecosystemID: "jvm", markers: ["build.gradle", "build.gradle.kts", "pom.xml"], target: "build", risk: .safe, enabledByDefault: true, regenerate: "./gradlew build"),
        Rule(id: "dotnet.obj", ecosystemID: "dotnet", markers: ["*.csproj"], target: "obj", risk: .safe, enabledByDefault: true, regenerate: "dotnet restore"),
        Rule(id: "unity.library", ecosystemID: "unity", markers: ["ProjectSettings"], target: "Library", risk: .caution, enabledByDefault: true, regenerate: "Reopen in Unity"),
    ]
}
