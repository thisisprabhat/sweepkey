import Foundation
import Testing
@testable import CleanerKit

@Suite struct VaultFinderTests {
    @Test(.enabled(if: gitAvailable))
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

    @Test(.enabled(if: gitAvailable))
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

    @Test(.enabled(if: gitAvailable))
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

    @Test(.enabled(if: gitAvailable))
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
        }
    }

    @Test
    func slashPatternsMatchSuffix() {
        #expect(SecretPatterns.firstMatch(relativePath: "a/config/master.key") != nil)
        #expect(SecretPatterns.firstMatch(relativePath: "a/other/x.txt", extra: ["config/x.txt"]) == nil)
        #expect(SecretPatterns.firstMatch(relativePath: "a/config/x.txt", extra: ["config/x.txt"]) == "config/x.txt")
    }

    @Test(.enabled(if: gitAvailable))
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

    @Test(.enabled(if: gitAvailable))
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
