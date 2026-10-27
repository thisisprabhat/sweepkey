import Foundation
import Testing
@testable import CleanerKit

@Suite struct VaultFinderTests {
    @Test(.enabled(if: vaultGitAvailable))
    func findsIgnoredAndAlwaysCollectButNotArtifacts() async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            let byPath = Dictionary(uniqueKeysWithValues: found.map { ($0.vaultPath, $0) })
            #expect(byPath["Root/app/.env"]?.reason == .ignoredMatch)
            #expect(byPath["Root/app/android/app/upload.jks"]?.reason == .ignoredMatch)
            #expect(byPath["Root/app/pubspec.yaml"]?.reason == .alwaysCollect)
            #expect(byPath["Root/app/pubspec.yaml"]?.pathInRepository == "pubspec.yaml")
            #expect(byPath["Root/app/pubspec.yaml"]?.git?.repositoryRoot.resolvingSymlinksInPath() == app)
            #expect(!found.contains { $0.vaultPath.contains("node_modules") })
            #expect(Set(found.map(\.id)).count == found.count)
        }
    }

    @Test(.enabled(if: vaultGitAvailable))
    func untrackedMatchAndExampleExcluded() async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            try writeText("A=1", to: app.appendingPathComponent("server.pem"))
            try writeText("A=", to: app.appendingPathComponent(".env.example"))
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            #expect(found.first { $0.vaultPath == "Root/app/server.pem" }?.reason == .untrackedMatch)
            #expect(!found.contains { $0.vaultPath.hasSuffix(".env.example") })
            let withExtra = try await SecretFinder().findSecrets(
                VaultCollectOptions(roots: [root], extraPatterns: [".env.example"]))
            #expect(withExtra.contains { $0.vaultPath.hasSuffix(".env.example") })
        }
    }

    @Test
    func nonGitDirGivesPatternMatch() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("plain")
            try writeText("k", to: root.appendingPathComponent("sub/id_rsa"))
            try writeText("k", to: root.appendingPathComponent("node_modules/a/.env"))
            try writeText("hi", to: root.appendingPathComponent("readme.txt"))
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            #expect(found.map(\.vaultPath) == ["plain/sub/id_rsa"])
            #expect(found.first?.reason == .patternMatch)
        }
    }

    @Test(.enabled(if: vaultGitAvailable))
    func uncommittedWorkIncluded() async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            try writeText("todo", to: app.appendingPathComponent("notes.txt"))
            let off = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            #expect(!off.contains { $0.vaultPath.hasSuffix("notes.txt") })
            let on = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root], includeUncommittedWork: true))
            #expect(on.first { $0.vaultPath.hasSuffix("notes.txt") }?.reason == .uncommittedWork)
        }
    }

    @Test(.enabled(if: vaultGitAvailable))
    func contentScanFlagsAwsKeyAndIgnoresBinary() async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            try writeText("const k = 'AKIAABCDEFGHIJKLMNOP'", to: app.appendingPathComponent("config.ts"))
            var bin = Data("AKIAABCDEFGHIJKLMNOP".utf8)
            bin.insert(0, at: 0)
            try bin.write(to: app.appendingPathComponent("blob.dat"))
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root], scanContents: true))
            #expect(found.first { $0.vaultPath.hasSuffix("config.ts") }?.reason == .contentMatch)
            #expect(!found.contains { $0.vaultPath.hasSuffix("blob.dat") })
            let off = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            #expect(!off.contains { $0.vaultPath.hasSuffix("config.ts") })
        }
    }

    @Test
    func contentScannerNeverReturnsValue() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("a.txt")
        try writeText("-----BEGIN RSA PRIVATE KEY-----", to: f)
        let r = ContentScanner().scan(f, maxBytes: 1000)
        #expect(r == "Private key")
        #expect(ContentScanner().scan(f, maxBytes: 5) == nil)
    }

    @Test
    func sizeCapRespectedAndExcludedPaths() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("plain")
            try write(100, to: root.appendingPathComponent("small.pem"))
            try write(5000, to: root.appendingPathComponent("big.pem"))
            try write(10, to: root.appendingPathComponent("skip/x.pem"))
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(
                roots: [root], excludedPaths: [root.appendingPathComponent("skip")], maxFileSizeBytes: 1000))
            #expect(found.map(\.vaultPath) == ["plain/small.pem"])
            let (_, warnings) = try await SecretFinder().findSecretsWithWarnings(VaultCollectOptions(
                roots: [root], excludedPaths: [root.appendingPathComponent("skip")], maxFileSizeBytes: 1000))
            #expect(warnings.count == 1)
            #expect(warnings.first?.contains("big.pem") == true)
        }
    }

    @Test(.enabled(if: vaultGitAvailable))
    func oversizedUncommittedWorkIsWarned() async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            try write(5000, to: app.appendingPathComponent("notes/draft.txt"))
            let (files, warnings) = try await SecretFinder().findSecretsWithWarnings(VaultCollectOptions(
                roots: [root], includeUncommittedWork: true, maxFileSizeBytes: 1000))
            #expect(!files.contains { $0.vaultPath.hasSuffix("draft.txt") })
            #expect(warnings.contains { $0.contains("draft.txt") && $0.contains("uncommittedWork") })
        }
    }

    @Test
    func sameNamedRootsGetDistinctVaultFolders() async throws {
        try await withTempDir { dir in
            let first = dir.appendingPathComponent("a/Projects")
            let second = dir.appendingPathComponent("b/Projects")
            try writeText("A=1", to: first.appendingPathComponent("app/.env"))
            try writeText("B=1", to: second.appendingPathComponent("app/.env"))
            let found = try await SecretFinder(git: GitClient(shell: NoGitShell()))
                .findSecrets(VaultCollectOptions(roots: [first, second]))
            let hash = VaultLayout.shortHash(second.standardizedFileURL.resolvingSymlinksInPath().path)
            #expect(Set(found.map(\.vaultPath)) == ["Projects/app/.env", "Projects-\(hash)/app/.env"])
            #expect(hash.count == 8)
            // Both files survive the export; the manifest is keyed by the distinct vault paths.
            let vault = dir.appendingPathComponent("vault")
            let result = try await VaultExporter().export(.init(files: found, destination: vault, format: .folder))
            #expect(result.copiedCount == 2 && result.manifest.entries.count == 2)
            #expect(try String(contentsOf: vault.appendingPathComponent("Projects/app/.env"), encoding: .utf8) == "A=1")
            #expect(try String(contentsOf: vault.appendingPathComponent("Projects-\(hash)/app/.env"), encoding: .utf8) == "B=1")
            // A single root keeps the plain name, so existing vaults are unchanged.
            let single = try await SecretFinder(git: GitClient(shell: NoGitShell()))
                .findSecrets(VaultCollectOptions(roots: [second]))
            #expect(single.map(\.vaultPath) == ["Projects/app/.env"])
        }
    }

    @Test
    func layoutNamesAndRebase() {
        let a = URL(fileURLWithPath: "/x/Projects"), b = URL(fileURLWithPath: "/y/projects"), c = URL(fileURLWithPath: "/z/Work")
        let names = VaultLayout.rootNames([a, b, c, a])
        #expect(names[0] == "Projects")
        #expect(names[1] == "projects-\(VaultLayout.shortHash("/y/projects"))")
        #expect(names[2] == "Work")
        #expect(names[3] == "Projects")
        let file = SecretFile(
            sourceURL: URL(fileURLWithPath: "/y/projects/app/sub/.env"), scanRoot: URL(fileURLWithPath: "/y/projects/app"),
            vaultPath: "app/sub/.env", reason: .ignoredMatch, matchedRule: ".env", sizeBytes: 1)
        let outside = SecretFile(
            sourceURL: URL(fileURLWithPath: "/elsewhere/app/.env"), scanRoot: URL(fileURLWithPath: "/elsewhere/app"),
            vaultPath: "app/.env", reason: .ignoredMatch, matchedRule: ".env", sizeBytes: 1)
        let rebased = VaultLayout.rebase([file, outside], scanRoots: [a, b, c])
        #expect(rebased[0].vaultPath == "\(names[1])/app/sub/.env")
        #expect(rebased[0].scanRoot.path == "/y/projects")
        #expect(rebased[1].vaultPath == "app/.env")
    }

    @Test
    func slashPatternsMatchSuffix() {
        #expect(SecretPatterns.firstMatch(relativePath: "a/config/master.key") != nil)
        #expect(SecretPatterns.firstMatch(relativePath: "a/other/x.txt", extra: ["config/x.txt"]) == nil)
        #expect(SecretPatterns.firstMatch(relativePath: "a/config/x.txt", extra: ["config/x.txt"]) == "config/x.txt")
    }

    @Test(.enabled(if: vaultGitAvailable))
    func gitFailureFallsBackToPatternWalkWithWarning() async throws {
        struct FailingLsFiles: ShellRunning {
            func run(_ executable: String, arguments: [String], currentDirectory: URL?,
                     input: Data?, timeout: Duration) async throws -> ShellResult {
                if arguments.contains("ls-files") { throw ShellError.launchFailed("boom") }
                return try await ProcessShellRunner().run(
                    executable, arguments: arguments, currentDirectory: currentDirectory,
                    input: input, timeout: timeout)
            }
        }
        try await withTempDir { dir in
            let (root, _) = try makeFixtureRepo(in: dir)
            let finder = SecretFinder(git: GitClient(shell: FailingLsFiles()))
            let (files, warnings) = try await finder.findSecretsWithWarnings(VaultCollectOptions(roots: [root]))
            #expect(warnings.count == 1)
            let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.vaultPath, $0) })
            #expect(byPath["Root/app/.env"]?.reason == .patternMatch)
            #expect(byPath["Root/app/android/app/upload.jks"]?.reason == .patternMatch)
            #expect(byPath["Root/app/pubspec.yaml"]?.reason == .alwaysCollect)
            #expect(!files.contains { $0.vaultPath.contains("node_modules") })
        }
    }

    @Test(.enabled(if: vaultGitAvailable))
    func unresolvedRootStillFindsFiles() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanerKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let (root, _) = try makeFixtureRepo(in: base)
        let found = try await SecretFinder().findSecrets(VaultCollectOptions(
            roots: [root], excludedPaths: [root.appendingPathComponent("app/android")]))
        let paths = found.map(\.vaultPath)
        #expect(paths.contains("Root/app/.env"))
        #expect(paths.contains("Root/app/pubspec.yaml"))
        #expect(!paths.contains { $0.contains("upload.jks") })
    }
}

/// A shell where `xcode-select -p` fails, so the finder never runs git (plain pattern walk).
struct NoGitShell: ShellRunning {
    func run(_ executable: String, arguments: [String], currentDirectory: URL?, input: Data?, timeout: Duration)
        async throws -> ShellResult { ShellResult(exitCode: 1, stdout: "", stderr: "no developer tools") }
}
