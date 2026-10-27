import Foundation
import Testing
@testable import CleanerKit

@Suite struct AutomationLogicTests {
    private func cand(_ id: String, _ risk: RiskLevel, _ size: Int64 = 10) -> Candidate {
        Candidate(
            id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), kind: .projectArtifact, title: id,
            ecosystemID: "node", ruleID: "r", risk: risk, sizeBytes: size)
    }

    private func project(_ name: String, stale: Bool, _ cands: [Candidate]) -> Project {
        Project(url: URL(fileURLWithPath: "/p/\(name)"), name: name, candidates: cands, isStale: stale)
    }

    private func cache(_ cands: [Candidate]) -> CacheGroup {
        CacheGroup(id: "c", title: "c", category: .xcode, symbolName: "x", candidates: cands)
    }

    @Test func selectionExcludesNonStaleAndNonSafe() {
        let projects = [
            project("fresh", stale: false, [cand("a", .safe)]),
            project("old", stale: true, [cand("b", .safe), cand("c", .caution)]),
        ]
        let picked = SafeCleanSelection.candidates(
            projects: projects, cacheGroups: [cache([cand("d", .safe), cand("e", .caution)])])
        #expect(Set(picked.map(\.id)) == ["b", "d"])
    }

    @Test func largestFirstBoundaries() {
        let items = [cand("a", .safe, 5), cand("b", .safe, 10), cand("c", .safe, 1)]
        #expect(SafeCleanSelection.largestFirst(upTo: 0, from: items).isEmpty)
        #expect(SafeCleanSelection.largestFirst(upTo: 10, from: items).map(\.id) == ["b"])
        #expect(SafeCleanSelection.largestFirst(upTo: 11, from: items).map(\.id) == ["b", "a"])
        #expect(SafeCleanSelection.largestFirst(upTo: 1000, from: items).count == 3)
    }

    @Test func policy() {
        let now = Date()
        func alert(_ free: Int64, last: Date? = nil, enabled: Bool = true) -> Bool {
            LowSpacePolicy.shouldAlert(freeBytes: free, thresholdGB: 10, lastAlert: last, now: now, enabled: enabled)
        }
        #expect(alert(10_000_000_000 - 1))
        #expect(!alert(10_000_000_000))
        #expect(!alert(1, enabled: false))
        #expect(!alert(1, last: now.addingTimeInterval(-6 * 3600 + 1)))
        #expect(alert(1, last: now.addingTimeInterval(-6 * 3600)))
    }

    @Test func plannerRoots() {
        let projects = ["/a/b", "/a/b/sub"]
        let roots = ["/a"]
        #expect(FSEventsPlanner.affectedRoot(for: "/a/bc/file", projectPaths: projects, scanRoots: roots) == "/a/bc")
        #expect(FSEventsPlanner.affectedRoot(for: "/a/b/x", projectPaths: projects, scanRoots: roots) == "/a/b")
        #expect(FSEventsPlanner.affectedRoot(for: "/a/b/sub/x", projectPaths: projects, scanRoots: roots) == "/a/b/sub")
        #expect(FSEventsPlanner.affectedRoot(for: "/a/new", projectPaths: [], scanRoots: roots) == "/a/new")
        #expect(FSEventsPlanner.affectedRoot(for: "/a/new/f.txt", projectPaths: [], scanRoots: roots) == "/a/new")
        #expect(FSEventsPlanner.affectedRoot(for: "/a", projectPaths: [], scanRoots: roots) == nil)
        #expect(FSEventsPlanner.affectedRoot(for: "/z/q", projectPaths: [], scanRoots: roots) == nil)
    }

    @Test func plannerNoise() {
        #expect(FSEventsPlanner.isNoise("/a/b/.git/index", artifactPaths: []))
        #expect(FSEventsPlanner.isNoise("/a/b/.git", artifactPaths: []))
        #expect(FSEventsPlanner.isNoise("/a/b/.DS_Store", artifactPaths: []))
        #expect(FSEventsPlanner.isNoise("/a/b/node_modules/x/y", artifactPaths: ["/a/b/node_modules"]))
        #expect(!FSEventsPlanner.isNoise("/a/b/node_modules_other/x", artifactPaths: ["/a/b/node_modules"]))
        #expect(!FSEventsPlanner.isNoise("/a/b/src/main.swift", artifactPaths: ["/a/b/node_modules"]))
    }
}
