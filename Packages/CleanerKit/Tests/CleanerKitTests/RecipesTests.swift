import Foundation
import Testing
@testable import CleanerKit

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.withLock { items.append(s) } }
    var all: [String] { lock.withLock { items } }
}

private struct FakeFinder: SecretFinding {
    var files: [SecretFile] = []
    var log: Log
    func findSecrets(_ options: VaultCollectOptions) async throws -> [SecretFile] {
        log.add("find"); return files
    }
}

private struct FakeExporter: VaultExporting {
    var log: Log
    var fail = false
    func export(_ request: VaultExportRequest) async throws -> VaultExportResult {
        log.add("export")
        if fail { throw VaultError.commandFailed("boom") }
        return VaultExportResult(
            outputURL: request.destination,
            manifest: VaultManifest(createdAt: Date(), hostName: "h", entries: []), copiedCount: 1, unchangedCount: 0)
    }
}

private struct FakeCleaner: CleanExecuting {
    var log: Log
    var status: CleanItemStatus = .cleaned
    func clean(_ candidates: [Candidate], mode: DeleteMode, dryRun: Bool,
               progress: @escaping @Sendable (CleanProgress) -> Void) async -> CleanReport {
        log.add("clean:" + candidates.map(\.title).joined(separator: ",") + ":\(mode.rawValue)")
        return CleanReport(
            startedAt: Date(), finishedAt: Date(), mode: mode, dryRun: dryRun,
            items: candidates.map { CleanItemResult(candidate: $0, status: status, freedBytes: $0.sizeBytes) })
    }
    func putBack(_ items: [CleanItemResult]) async -> [CleanItemResult] { items }
}

private struct FakeSafety: SafetyEvaluating {
    var verdicts: [String: SafetyVerdict]
    func evaluate(_ candidates: [Candidate], scanRoots: [URL]) async -> [Candidate.ID: SafetyVerdict] {
        Dictionary(uniqueKeysWithValues: candidates.compactMap { c in verdicts[c.title].map { (c.id, $0) } })
    }
}

private final class FakeShell: ShellRunning, @unchecked Sendable {
    var log: Log
    var createZip = true
    var extractExit: Int32 = 0
    init(log: Log) { self.log = log }
    func run(_ executable: String, arguments: [String], currentDirectory: URL?, input: Data?, timeout: Duration)
        async throws -> ShellResult {
        if arguments.first == "-c" {
            log.add("ditto-create")
            if createZip, let out = arguments.last { try Data("zip".utf8).write(to: URL(fileURLWithPath: out)) }
            return ShellResult(exitCode: 0, stdout: "", stderr: "")
        }
        log.add("ditto-extract")
        return ShellResult(exitCode: extractExit, stdout: "", stderr: extractExit == 0 ? "" : "bad zip")
    }
}

private func secretFile(_ dir: URL) -> SecretFile {
    SecretFile(sourceURL: dir.appendingPathComponent(".env"), scanRoot: dir, vaultPath: "p/.env",
               reason: .ignoredMatch, matchedRule: ".env", sizeBytes: 1)
}

private func artifact(_ name: String, in dir: URL) -> Candidate {
    Candidate(id: "r|\(dir.path)/\(name)", url: dir.appendingPathComponent(name), kind: .projectArtifact,
              title: name, ecosystemID: "generic", ruleID: "r", risk: .safe, sizeBytes: 10)
}

@Suite struct ArchiveRecipeTests {
    private func make(
        _ log: Log, dir: URL, shell: FakeShell, cleanStatus: CleanItemStatus = .cleaned,
        verdicts: [String: SafetyVerdict] = ["node_modules": .allowed, "build": .blocked("no")],
        exportFails: Bool = false, project: Project
    ) -> ArchiveRecipe {
        ArchiveRecipe(
            secrets: FakeFinder(files: [secretFile(project.url)], log: log),
            exporter: FakeExporter(log: log, fail: exportFails),
            cleaner: FakeCleaner(log: log, status: cleanStatus),
            safety: FakeSafety(verdicts: verdicts), shell: shell,
            trash: { url in log.add("trash:\(url.lastPathComponent)") })
    }

    private func project(_ dir: URL, git: GitInfo? = nil) -> Project {
        let url = dir.appendingPathComponent("proj", isDirectory: true)
        return Project(url: url, name: "proj", candidates: [artifact("node_modules", in: url), artifact("build", in: url)], git: git)
    }

    @Test func trashesOnlyAfterZipVerified() async throws {
        try await withTempDir { dir in
            let log = Log()
            let p = project(dir)
            let report = await make(log, dir: dir, shell: FakeShell(log: log), project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("vault"),
                archiveDirectory: dir.appendingPathComponent("arch"), zip: true)
            #expect(report.succeeded && report.trashedProject)
            #expect(log.all == ["find", "export", "clean:node_modules:permanent", "ditto-create", "ditto-extract", "trash:proj"])
            #expect(report.steps.map(\.name).contains("Verify zip"))
        }
    }

    @Test func badZipNeverTrashes() async throws {
        try await withTempDir { dir in
            let log = Log()
            let shell = FakeShell(log: log)
            shell.extractExit = 1
            let p = project(dir)
            let report = await make(log, dir: dir, shell: shell, project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("v"),
                archiveDirectory: dir.appendingPathComponent("arch"), zip: true)
            #expect(!report.succeeded && !report.trashedProject)
            #expect(!log.all.contains { $0.hasPrefix("trash") })
        }
    }

    @Test func missingZipNeverTrashes() async throws {
        try await withTempDir { dir in
            let log = Log()
            let shell = FakeShell(log: log)
            shell.createZip = false
            let p = project(dir)
            let report = await make(log, dir: dir, shell: shell, project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("v"),
                archiveDirectory: dir.appendingPathComponent("arch"), zip: true)
            #expect(!report.trashedProject && !log.all.contains("ditto-extract"))
            #expect(report.steps.last?.status == .failed)
        }
    }

    @Test func vaultFailureStopsBeforeCleaning() async throws {
        try await withTempDir { dir in
            let log = Log()
            let p = project(dir)
            let report = await make(log, dir: dir, shell: FakeShell(log: log), exportFails: true, project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("v"), archiveDirectory: nil, zip: false)
            #expect(!report.succeeded)
            #expect(log.all == ["find", "export"])
        }
    }

    @Test func cleanFailureStopsBeforeZip() async throws {
        try await withTempDir { dir in
            let log = Log()
            let p = project(dir)
            let report = await make(log, dir: dir, shell: FakeShell(log: log), cleanStatus: .failed, project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("v"),
                archiveDirectory: dir.appendingPathComponent("arch"), zip: true)
            #expect(!report.succeeded)
            #expect(!log.all.contains("ditto-create"))
        }
    }

    @Test func missingVerdictIsBlocked() async throws {
        try await withTempDir { dir in
            let log = Log()
            let p = project(dir)
            _ = await make(log, dir: dir, shell: FakeShell(log: log), verdicts: [:], project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("v"), archiveDirectory: nil, zip: false)
            #expect(!log.all.contains { $0.hasPrefix("clean") })
        }
    }

    @Test func risksRequireAcknowledgementAndTouchNothing() async throws {
        try await withTempDir { dir in
            let log = Log()
            let p = project(dir, git: GitInfo(repositoryRoot: dir, isDirty: true))
            let recipe = make(log, dir: dir, shell: FakeShell(log: log), project: p)
            let blocked = await recipe.run(
                project: p, vaultDestination: dir.appendingPathComponent("v"), archiveDirectory: nil, zip: false)
            #expect(blocked.requiresAcknowledgement && !blocked.succeeded && blocked.risks.count == 1)
            #expect(log.all.isEmpty)
            let ok = await recipe.run(
                project: p, vaultDestination: dir.appendingPathComponent("v"), archiveDirectory: nil, zip: false,
                acknowledgeRisks: true)
            #expect(ok.succeeded && ok.risks.count == 1)
        }
    }

    @Test func existingZipIsNotOverwritten() async throws {
        try await withTempDir { dir in
            let log = Log()
            let p = project(dir)
            let arch = dir.appendingPathComponent("arch")
            try write(3, to: arch.appendingPathComponent("proj.zip"))
            let report = await make(log, dir: dir, shell: FakeShell(log: log), project: p).run(
                project: p, vaultDestination: dir.appendingPathComponent("v"), archiveDirectory: arch, zip: true)
            #expect(!report.succeeded && !report.trashedProject && !log.all.contains("ditto-create"))
        }
    }
}

@Suite struct MigrationBundleTests {
    @Test func cloneScriptQuotesPathsAndUrls() {
        let repo = RepoEntry(
            path: "/x", relativePath: "Pro jects/it's app", remote: "https://h/o'r;touch pwned", branch: "feat/it's")
        let script = MigrationBundle.cloneScript(repos: [repo])
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("'Pro jects/it'\\''s app'"))
        #expect(script.contains("'https://h/o'\\''r;touch pwned'"))
        #expect(script.contains("'feat/it'\\''s'"))
        #expect(script.contains("git clone -- "))
        #expect(script.contains("if [ -e "))
        #expect(!script.contains("rm "))
    }

    @Test func quoteRoundTripsThroughShell() throws {
        let tricky = "a b'c\"d$e`f;g"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "printf %s " + MigrationBundle.shellQuote(tricky)]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        #expect(String(decoding: data, as: UTF8.self) == tricky)
    }

    @Test func cloneScriptSkipsUnsafeEntries() {
        let repos = [
            RepoEntry(path: "/a", relativePath: "../evil", remote: "https://h/a", branch: nil),
            RepoEntry(path: "/b", relativePath: "/abs", remote: "https://h/b", branch: nil),
            RepoEntry(path: "/c", relativePath: "R/c", remote: nil, branch: nil),
            RepoEntry(path: "/d", relativePath: "R/d", remote: "--upload-pack=x", branch: nil),
            RepoEntry(path: "/e", relativePath: "R/e", remote: "https://h/e", branch: "main"),
        ]
        let script = MigrationBundle.cloneScript(repos: repos)
        #expect(!script.contains("evil") && !script.contains("'/abs'") && !script.contains("R/c") && !script.contains("R/d"))
        #expect(script.contains("'R/e'"))
    }

    @Test func entryUsesRelativePathUnderRoot() {
        let info = GitInfo(
            repositoryRoot: URL(fileURLWithPath: "/Users/me/Projects/a/b"), remoteURL: "git@h:o/b.git", branch: "main")
        let e = MigrationBundle.entry(for: info, root: URL(fileURLWithPath: "/Users/me/Projects"))
        #expect(e.relativePath == "Projects/a/b" && e.remote == "git@h:o/b.git" && e.branch == "main")
        #expect(e.path == "/Users/me/Projects/a/b")
    }

    @Test func exportWritesReposJsonAndScript() async throws {
        guard vaultGitAvailable else { return }
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            try vaultGit(["remote", "add", "origin", "https://example.com/o/app.git"], in: app)
            let log = Log()
            let out = dir.appendingPathComponent("bundle")
            let result = try await MigrationBundle.export(
                roots: [root], to: out, secrets: FakeFinder(files: [], log: log), exporter: FakeExporter(log: log))
            #expect(result.repos.count == 1)
            let data = try Data(contentsOf: out.appendingPathComponent("repos.json"))
            let decoded = try JSONDecoder().decode([RepoEntry].self, from: data)
            #expect(decoded.count == 1)
            #expect(decoded[0].remote == "https://example.com/o/app.git")
            #expect(decoded[0].relativePath == "Root/app")
            #expect(decoded[0].path == app.path)
            #expect(decoded[0].branch != nil)
            let script = try String(contentsOf: out.appendingPathComponent("restore.sh"), encoding: .utf8)
            #expect(script.contains("'Root/app'"))
            #expect(FileManager.default.isExecutableFile(atPath: out.appendingPathComponent("restore.sh").path))
        }
    }
}
