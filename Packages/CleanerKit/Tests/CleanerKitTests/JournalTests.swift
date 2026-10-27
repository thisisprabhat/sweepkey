import Foundation
import Testing
@testable import CleanerKit

private func report(freed: Int64, dryRun: Bool = false) -> CleanReport {
    let c = Candidate(
        id: "r|/x", url: URL(fileURLWithPath: "/x"), kind: .projectArtifact, title: "x",
        ecosystemID: "generic", ruleID: "r", risk: .safe, sizeBytes: freed)
    return CleanReport(
        startedAt: Date(timeIntervalSince1970: 1000), finishedAt: Date(timeIntervalSince1970: 1001),
        mode: .permanent, dryRun: dryRun,
        items: [CleanItemResult(candidate: c, status: dryRun ? .dryRun : .cleaned, freedBytes: freed)])
}

@Suite struct JournalTests {
    @Test func roundTripOrderingAndLifetime() async throws {
        try await withTempDir { dir in
            let file = dir.appendingPathComponent("sub/journal.json")
            let j = JSONJournal(fileURL: file)
            #expect(try await j.reports().isEmpty)
            let a = report(freed: 100), b = report(freed: 200), d = report(freed: 999, dryRun: true)
            try await j.append(a)
            try await j.append(b)
            try await j.append(d)
            let all = try await j.reports()
            #expect(all.map(\.id) == [d.id, b.id, a.id])
            #expect(all[1] == b)
            #expect(try await j.lifetimeFreedBytes() == 300)
            // Persisted across instances.
            #expect(try await JSONJournal(fileURL: file).reports().count == 3)
        }
    }

    @Test func cappedAt500() async throws {
        try await withTempDir { dir in
            let j = JSONJournal(fileURL: dir.appendingPathComponent("j.json"))
            for i in 0..<505 { try await j.append(report(freed: Int64(i))) }
            let all = try await j.reports()
            #expect(all.count == 500)
            #expect(all.first?.freedBytes == 504)
        }
    }

    @Test func corruptFileMovedAsideAndAppendsWork() async throws {
        try await withTempDir { dir in
            let file = dir.appendingPathComponent("journal.json")
            try "not json {{".write(to: file, atomically: true, encoding: .utf8)
            let j = JSONJournal(fileURL: file)
            #expect(try await j.reports().isEmpty)
            let r = report(freed: 7)
            try await j.append(r)
            #expect(try await j.reports().map(\.id) == [r.id])
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(names.contains { $0.hasPrefix("journal.corrupt-") && $0.hasSuffix(".json") })
        }
    }

    @Test func datesRoundTripExactly() async throws {
        try await withTempDir { dir in
            let j = JSONJournal(fileURL: dir.appendingPathComponent("j.json"))
            var r = report(freed: 1)
            r.startedAt = Date(timeIntervalSince1970: 1000.123456)
            try await j.append(r)
            #expect(try await j.reports()[0].startedAt == r.startedAt)
        }
    }
}
