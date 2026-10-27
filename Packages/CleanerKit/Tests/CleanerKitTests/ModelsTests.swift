import Testing
import Foundation
@testable import CleanerKit

@Suite struct ModelsTests {
    @Test func riskOrdering() {
        #expect(RiskLevel.safe < .caution)
        #expect(RiskLevel.caution < .danger)
        #expect(RiskLevel.allCases.sorted() == [.safe, .caution, .danger])
        #expect(RiskLevel.danger > .safe)
    }

    @Test func candidateCodableWithCommandAction() throws {
        let c = Candidate(
            id: "docker.prune|/x", url: URL(fileURLWithPath: "/tmp/x"), kind: .globalCache,
            title: "Docker", ecosystemID: "container", ruleID: "docker.prune", risk: .caution,
            sizeBytes: 123, lastModified: Date(timeIntervalSince1970: 1000),
            note: "n", action: .command(executable: "docker", arguments: ["system", "prune", "-f"]))
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(Candidate.self, from: data) == c)
    }

    @Test func candidateDefaultActionIsDelete() {
        let c = Candidate(id: "a|b", url: URL(fileURLWithPath: "/tmp/b"), kind: .projectArtifact,
                          title: "t", ecosystemID: "generic", ruleID: "a", risk: .safe, sizeBytes: 1)
        #expect(c.action == .delete)
    }

    @Test func ecosystemLookup() {
        #expect(Ecosystem.named("nope").id == "generic")
        #expect(Ecosystem.named("rust").name == "Rust")
        #expect(Ecosystem.builtIn.count == 21)
        #expect(Set(Ecosystem.builtIn.map(\.id)).count == 21)
    }

    @Test func derivedValues() {
        func cand(_ id: String, _ size: Int64) -> Candidate {
            Candidate(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), kind: .projectArtifact, title: id,
                      ecosystemID: "generic", ruleID: "r", risk: .safe, sizeBytes: size)
        }
        let a = cand("a", 10), b = cand("b", 32)
        #expect(Project(url: URL(fileURLWithPath: "/tmp/p"), name: "p", candidates: [a, b]).reclaimableBytes == 42)
        #expect(CacheGroup(id: "g", title: "g", category: .xcode, symbolName: "hammer", candidates: [a, b]).totalBytes == 42)
        let report = CleanReport(startedAt: Date(), finishedAt: Date(), mode: .trash, dryRun: false, items: [
            CleanItemResult(candidate: a, status: .cleaned, freedBytes: 10),
            CleanItemResult(candidate: b, status: .failed, freedBytes: 32),
            CleanItemResult(candidate: b, status: .dryRun, freedBytes: 32),
        ])
        #expect(report.freedBytes == 10)
    }

    @Test func safetyVerdict() {
        #expect(SafetyVerdict.allowed.isAllowed)
        #expect(SafetyVerdict.warning("w").isAllowed)
        #expect(!SafetyVerdict.blocked("b").isAllowed)
    }

    @Test func cacheCategoryMetadata() {
        for c in CacheCategory.allCases {
            #expect(!c.displayName.isEmpty)
            #expect(!c.symbolName.isEmpty)
        }
        #expect(CacheCategory.aiModels.symbolName == "brain")
    }

    @Test func vaultDefaults() {
        let o = VaultCollectOptions(roots: [])
        #expect(o.alwaysCollect == ["pubspec.yaml"])
        #expect(o.maxFileSizeBytes == 10_485_760)
        #expect(VaultManifest(createdAt: Date(), hostName: "h", entries: []).formatVersion == 1)
    }
}
