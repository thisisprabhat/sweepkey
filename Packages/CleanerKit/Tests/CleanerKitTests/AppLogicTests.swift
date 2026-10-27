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

    @Test func approximateOnlyForCleanedZeroFreed() {
        let c = candidate("x", size: 500)
        #expect(AppLogic.isApproximate(CleanItemResult(candidate: c, status: .cleaned, freedBytes: 0)))
        #expect(!AppLogic.isApproximate(CleanItemResult(candidate: c, status: .cleaned, freedBytes: 10)))
        #expect(!AppLogic.isApproximate(CleanItemResult(candidate: c, status: .failed, freedBytes: 0)))
        #expect(!AppLogic.isApproximate(CleanItemResult(candidate: candidate("z", size: 0), status: .cleaned, freedBytes: 0)))
    }
}
