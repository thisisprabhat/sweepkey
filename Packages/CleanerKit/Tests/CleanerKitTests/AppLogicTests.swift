import Foundation
import Testing
@testable import CleanerKit

@Suite struct AppLogicTests {
    private func candidate(_ id: String, size: Int64 = 100) -> Candidate {
        Candidate(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), kind: .projectArtifact, title: id, ecosystemID: "node",
            ruleID: "r", risk: .safe, sizeBytes: size)
    }

    @Test func resolveDedupesAndResolvesSymlinks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("applogic-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: base) }
        let out = AppLogic.resolve([link, real, real.appendingPathComponent("../real")])
        #expect(out.count == 1)
        #expect(out[0].path == real.resolvingSymlinksInPath().path)
    }

    @Test func directoriesKeepsOnlyExistingFolders() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("applogic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("f.txt")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: base) }
        let out = AppLogic.directories(from: [base, file, base.appendingPathComponent("missing")])
        #expect(out == [base.resolvingSymlinksInPath()])
    }

    @Test func partitionBlocksMissingVerdicts() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c"), d = candidate("d")
        let verdicts: [Candidate.ID: SafetyVerdict] = [a.id: .allowed, b.id: .warning("w"), c.id: .blocked("no")]
        let result = AppLogic.partition([a, b, c, d], verdicts: verdicts)
        #expect(result.cleanable.map(\.id) == [a.id, b.id])
        #expect(result.blocked.map(\.id) == [c.id, d.id])
    }

    @Test func strictPartitionBlocksWarnings() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c"), d = candidate("d")
        let verdicts: [Candidate.ID: SafetyVerdict] = [
            a.id: .allowed, b.id: .warning("Project appears to be open in /p"), c.id: .blocked("no"),
        ]
        let strict = AppLogic.partition([a, b, c, d], verdicts: verdicts, strict: true)
        #expect(strict.cleanable.map(\.id) == [a.id])
        #expect(strict.blocked.map(\.id) == [b.id, c.id, d.id])
        let alias = AppLogic.partitionStrict([a, b, c, d], verdicts: verdicts)
        #expect(alias.cleanable.map(\.id) == strict.cleanable.map(\.id))
        #expect(alias.blocked.map(\.id) == strict.blocked.map(\.id))
    }

    @Test func acknowledgementForWarningsAndDanger() {
        let safe = candidate("s")
        var danger = candidate("d")
        danger.risk = .danger
        #expect(!AppLogic.needsAcknowledgement(safe, verdict: .allowed))
        #expect(!AppLogic.needsAcknowledgement(safe, verdict: nil))
        #expect(AppLogic.needsAcknowledgement(safe, verdict: .warning("open")))
        #expect(AppLogic.needsAcknowledgement(danger, verdict: .allowed))
    }

    @Test func approximateOnlyForCleanedZeroFreed() {
        let c = candidate("x", size: 500)
        #expect(AppLogic.isApproximate(CleanItemResult(candidate: c, status: .cleaned, freedBytes: 0)))
        #expect(!AppLogic.isApproximate(CleanItemResult(candidate: c, status: .cleaned, freedBytes: 10)))
        #expect(!AppLogic.isApproximate(CleanItemResult(candidate: c, status: .failed, freedBytes: 0)))
        #expect(!AppLogic.isApproximate(CleanItemResult(candidate: candidate("z", size: 0), status: .cleaned, freedBytes: 0)))
    }

    @Test func affectedRootsAreDistinctCleanedProjectRoots() {
        var a = candidate("a"), b = candidate("b"), c = candidate("c"), cache = candidate("k")
        a.projectRoot = URL(fileURLWithPath: "/p/one")
        b.projectRoot = URL(fileURLWithPath: "/p/one")
        c.projectRoot = URL(fileURLWithPath: "/p/two")
        cache.kind = .globalCache
        let items = [
            CleanItemResult(candidate: a, status: .cleaned, freedBytes: 1),
            CleanItemResult(candidate: b, status: .cleaned, freedBytes: 1),
            CleanItemResult(candidate: c, status: .failed),
            CleanItemResult(candidate: cache, status: .cleaned, freedBytes: 1),
        ]
        let report = CleanReport(startedAt: .now, finishedAt: .now, mode: .permanent, dryRun: false, items: items)
        #expect(AppLogic.affectedProjectRoots(report).map(\.path) == ["/p/one"])
        var dry = report
        dry.dryRun = true
        #expect(AppLogic.affectedProjectRoots(dry).isEmpty)
    }

    @Test func freeSpaceDelta() {
        #expect(FreeSpaceDelta(before: 100, after: 350).gained == 250)
        #expect(FreeSpaceDelta(before: 100, after: 90).gained == -10)
    }

    @Test func cancelledItemsOnlyCountExecutorCancellations() {
        let items = [
            CleanItemResult(candidate: candidate("a"), status: .skipped, message: CleanExecutor.cancelledMessage),
            CleanItemResult(candidate: candidate("b"), status: .skipped, message: "No longer exists"),
            CleanItemResult(candidate: candidate("c"), status: .cleaned, freedBytes: 1),
        ]
        let report = CleanReport(startedAt: .now, finishedAt: .now, mode: .trash, dryRun: false, items: items)
        #expect(AppLogic.cancelledItems(report).map(\.candidate.id) == ["a"])
    }
}
