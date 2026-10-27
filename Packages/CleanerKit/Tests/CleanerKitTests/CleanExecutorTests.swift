import Foundation
import Testing
@testable import CleanerKit

private final class FakeShell: ShellRunning, @unchecked Sendable {
    struct Call: Equatable { var executable: String; var arguments: [String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var result: ShellResult
    var onRun: (@Sendable () -> Void)?
    init(result: ShellResult = ShellResult(exitCode: 0, stdout: "", stderr: "")) { self.result = result }
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    func run(_ executable: String, arguments: [String], currentDirectory: URL?, input: Data?, timeout: Duration)
        async throws -> ShellResult {
        lock.withLock { _calls.append(Call(executable: executable, arguments: arguments)) }
        onRun?()
        return result
    }
}

private func cand(_ url: URL, size: Int64 = 1, action: CleanAction = .delete) -> Candidate {
    Candidate(
        id: "r|\(url.path)", url: url, kind: .projectArtifact, title: url.lastPathComponent,
        ecosystemID: "generic", ruleID: "r", risk: .safe, sizeBytes: size, action: action)
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CleanProgress] = []
    func add(_ p: CleanProgress) { lock.lock(); items.append(p); lock.unlock() }
    var all: [CleanProgress] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct CleanExecutorTests {
    @Test func dryRunTouchesNothing() async throws {
        try await withTempDir { dir in
            let t = dir.appendingPathComponent("a")
            try write(100, to: t.appendingPathComponent("f"))
            let journal = JSONJournal(fileURL: dir.appendingPathComponent("j.json"))
            let ex = CleanExecutor(shell: FakeShell(), journal: journal)
            let r = await ex.clean([cand(t, size: 42)], mode: .permanent, dryRun: true) { _ in }
            #expect(r.items[0].status == .dryRun)
            #expect(r.items[0].freedBytes == 42)
            #expect(FileManager.default.fileExists(atPath: t.path))
            #expect(try await journal.reports().isEmpty)
        }
    }

    @Test func permanentDeleteFreesBytesAndJournals() async throws {
        try await withTempDir { dir in
            let t = dir.appendingPathComponent("a")
            try write(10_000, to: t.appendingPathComponent("f"))
            let journal = JSONJournal(fileURL: dir.appendingPathComponent("j.json"))
            let ex = CleanExecutor(shell: FakeShell(), journal: journal)
            let col = Collector()
            let r = await ex.clean([cand(t)], mode: .permanent, dryRun: false) { col.add($0) }
            #expect(r.items[0].status == .cleaned)
            #expect(r.items[0].freedBytes >= 10_000)
            #expect(!FileManager.default.fileExists(atPath: t.path))
            #expect(try await journal.reports().map(\.id) == [r.id])
            #expect(col.all.count == 1 && col.all[0].completed == 1 && col.all[0].total == 1)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)) func trashAndPutBack() async throws {
        try await withTempDir { dir in
            let t = dir.appendingPathComponent("a")
            try write(100, to: t.appendingPathComponent("f"))
            let ex = CleanExecutor(shell: FakeShell())
            let r = await ex.clean([cand(t)], mode: .trash, dryRun: false) { _ in }
            defer { if let u = r.items[0].trashURL { try? FileManager.default.removeItem(at: u) } }
            #expect(r.items[0].status == .cleaned)
            let trash = try #require(r.items[0].trashURL)
            #expect(FileManager.default.fileExists(atPath: trash.path))
            #expect(!FileManager.default.fileExists(atPath: t.path))

            let back = await ex.putBack(r.items)
            #expect(back.count == 1 && back[0].status != .failed)
            #expect(FileManager.default.fileExists(atPath: t.appendingPathComponent("f").path))
            #expect(!FileManager.default.fileExists(atPath: trash.path))
        }
    }

    @Test func putBackFailsWhenDestinationExists() async throws {
        try await withTempDir { dir in
            let t = dir.appendingPathComponent("a")
            try write(1, to: t.appendingPathComponent("f"))
            let trashed = dir.appendingPathComponent(".Trash/trashed")
            try write(1, to: trashed)
            let item = CleanItemResult(candidate: cand(t), status: .cleaned, freedBytes: 1, trashURL: trashed)
            let back = await CleanExecutor(shell: FakeShell()).putBack([item])
            #expect(back[0].status == .failed)
            #expect(back[0].message == "Destination exists")
            #expect(FileManager.default.fileExists(atPath: trashed.path))
        }
    }

    @Test func commandActionRunsShellAndMeasuresFreed() async throws {
        try await withTempDir { dir in
            let t = dir.appendingPathComponent("cache")
            try write(50_000, to: t.appendingPathComponent("big"))
            let shell = FakeShell()
            shell.onRun = { try? FileManager.default.removeItem(at: t.appendingPathComponent("big")) }
            let c = cand(t, action: .command(executable: "docker", arguments: ["system", "prune", "-f"]))
            let r = await CleanExecutor(shell: shell).clean([c], mode: .permanent, dryRun: false) { _ in }
            #expect(shell.calls == [.init(executable: "docker", arguments: ["system", "prune", "-f"])])
            #expect(r.items[0].status == .cleaned)
            #expect(r.items[0].freedBytes >= 50_000)
            #expect(FileManager.default.fileExists(atPath: t.path))
        }
    }

    @Test func commandFailureReportsStderr() async throws {
        try await withTempDir { dir in
            let shell = FakeShell(result: ShellResult(exitCode: 1, stdout: "", stderr: "boom\n"))
            let c = cand(dir, action: .command(executable: "x", arguments: []))
            let r = await CleanExecutor(shell: shell).clean([c], mode: .permanent, dryRun: false) { _ in }
            #expect(r.items[0].status == .failed)
            #expect(r.items[0].message == "boom")
        }
    }

    @Test func missingAndSymlinkItemsSkipped() async throws {
        try await withTempDir { dir in
            let real = dir.appendingPathComponent("real")
            try write(1, to: real.appendingPathComponent("f"))
            let link = dir.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let r = await CleanExecutor(shell: FakeShell()).clean(
                [cand(dir.appendingPathComponent("gone")), cand(link)], mode: .permanent, dryRun: false) { _ in }
            #expect(r.items.map(\.status) == [.skipped, .skipped])
            #expect(FileManager.default.fileExists(atPath: real.appendingPathComponent("f").path))
        }
    }

    @Test func oneFailureDoesNotStopRun() async throws {
        try await withTempDir { dir in
            let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
            try write(1, to: a.appendingPathComponent("f"))
            try write(1, to: b.appendingPathComponent("f"))
            let shell = FakeShell(result: ShellResult(exitCode: 2, stdout: "", stderr: "no"))
            let bad = cand(dir, action: .command(executable: "x", arguments: []))
            let r = await CleanExecutor(shell: shell).clean([a, ].map { cand($0) } + [bad, cand(b)],
                                                            mode: .permanent, dryRun: false) { _ in }
            #expect(r.items.map(\.status) == [.cleaned, .failed, .cleaned])
            #expect(!FileManager.default.fileExists(atPath: b.path))
        }
    }

    @Test func cancellationSkipsRemaining() async throws {
        try await withTempDir { dir in
            let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
            try write(1, to: a.appendingPathComponent("f"))
            try write(1, to: b.appendingPathComponent("f"))
            let ex = CleanExecutor(shell: FakeShell())
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await ex.clean([cand(a), cand(b)], mode: .permanent, dryRun: false) { _ in }
            }
            let r = await task.value
            #expect(r.items.map(\.status) == [.skipped, .skipped])
            #expect(r.items.allSatisfy { $0.message == "Cancelled" })
            #expect(FileManager.default.fileExists(atPath: a.path))
        }
    }

    @Test func putBackRefusesNonTrashSource() async throws {
        try await withTempDir { dir in
            let t = dir.appendingPathComponent("a")
            let src = dir.appendingPathComponent("elsewhere/x")
            try write(1, to: src)
            let item = CleanItemResult(candidate: cand(t), status: .cleaned, freedBytes: 1, trashURL: src)
            let back = await CleanExecutor(shell: FakeShell()).putBack([item])
            #expect(back[0].status == .failed)
            #expect(FileManager.default.fileExists(atPath: src.path))
            #expect(!FileManager.default.fileExists(atPath: t.path))
        }
    }

    @Test func refusesSymlinkedAncestorHomeAndRoot() async throws {
        try await withTempDir { dir in
            let real = dir.appendingPathComponent("real")
            try write(1, to: real.appendingPathComponent("sub/f"))
            let link = dir.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let home = dir.appendingPathComponent("home")
            try write(1, to: home.appendingPathComponent("f"))
            let ex = CleanExecutor(shell: FakeShell(), home: home)
            let r = await ex.clean(
                [cand(link.appendingPathComponent("sub")), cand(home), cand(URL(fileURLWithPath: "/"))],
                mode: .permanent, dryRun: false) { _ in }
            #expect(r.items.map(\.status) == [.skipped, .skipped, .skipped])
            #expect(r.items.allSatisfy { $0.message != nil })
            #expect(FileManager.default.fileExists(atPath: real.appendingPathComponent("sub/f").path))
            #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("f").path))
        }
    }

    private struct FailingJournal: CleanJournaling {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "disk full" } }
        func append(_ report: CleanReport) async throws { throw Boom() }
        func reports() async throws -> [CleanReport] { [] }
        func lifetimeFreedBytes() async throws -> Int64 { 0 }
    }

    @Test func journalFailureIsSurfacedOnLastItem() async throws {
        try await withTempDir { dir in
            let a = dir.appendingPathComponent("a")
            try write(1, to: a.appendingPathComponent("f"))
            let r = await CleanExecutor(shell: FakeShell(), journal: FailingJournal())
                .clean([cand(a)], mode: .permanent, dryRun: false) { _ in }
            #expect(r.items[0].status == .cleaned)
            #expect(r.items[0].message?.contains("Journal write failed: disk full") == true)
        }
    }

    @Test func midRunCancellationSkipsRest() async throws {
        try await withTempDir { dir in
            let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
            try write(1, to: a.appendingPathComponent("f"))
            try write(1, to: b.appendingPathComponent("f"))
            let ex = CleanExecutor(shell: FakeShell())
            let task = Task {
                await ex.clean([cand(a), cand(b)], mode: .permanent, dryRun: false) { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            let r = await task.value
            #expect(r.items.map(\.status) == [.cleaned, .skipped])
            #expect(r.items[1].message == "Cancelled")
            #expect(FileManager.default.fileExists(atPath: b.path))
        }
    }
}
