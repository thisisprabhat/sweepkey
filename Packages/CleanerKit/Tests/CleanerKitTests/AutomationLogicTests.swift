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

    @Test func selectionExcludesNonStaleAndNonSafe() {
        let projects = [
            project("fresh", stale: false, [cand("a", .safe)]),
            project("old", stale: true, [cand("b", .safe), cand("c", .caution), cand("f", .danger)]),
        ]
        let picked = SafeCleanSelection.candidates(projects: projects)
        #expect(picked.map(\.id) == ["b"])
    }

    @Test func selectionNeverIncludesCaches() {
        var safeCache = cand("d", .safe)
        safeCache.kind = .globalCache
        // Even a global-cache candidate attached to a stale project is excluded.
        let projects = [project("old", stale: true, [cand("b", .safe), safeCache])]
        #expect(SafeCleanSelection.candidates(projects: projects).map(\.id) == ["b"])
        #expect(SafeCleanSelection.candidates(projects: []).isEmpty)
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

    // MARK: Scheduler clock

    @Test func scheduleActions() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86400
        #expect(SchedulePlanner.action(enabled: false, lastRun: now, interval: day, now: now) == .forget)
        #expect(SchedulePlanner.action(enabled: true, lastRun: nil, interval: day, now: now) == .startClock)
        #expect(SchedulePlanner.action(enabled: true, lastRun: now.addingTimeInterval(-day), interval: day, now: now) == .run)
        // Overdue by many intervals (app closed for a week): still a single run.
        #expect(SchedulePlanner.action(enabled: true, lastRun: now.addingTimeInterval(-7 * day), interval: day, now: now) == .run)
        #expect(SchedulePlanner.action(enabled: true, lastRun: now.addingTimeInterval(-3600), interval: day, now: now)
            == .wait(day - 3600))
        #expect(SchedulePlanner.action(enabled: true, lastRun: now.addingTimeInterval(60), interval: day, now: now) == .startClock)
        #expect(SchedulePlanner.checkInterval(for: 7 * day) == 3600)
        #expect(SchedulePlanner.checkInterval(for: 3600) == 15 * 60)
        #expect(SchedulePlanner.checkInterval(for: 4 * 3600) == 3600)
    }

    @Test func scheduleStateRoundTripsAndToleratesCorruption() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sched-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ScheduleStateStore(fileURL: dir.appendingPathComponent("schedule.json"))
        #expect(store.load() == ScheduleState())
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try store.save(ScheduleState(lastRun: ["job": date]))
        #expect(store.load().lastRun["job"] == date)
        try Data("garbage".utf8).write(to: store.fileURL)
        #expect(store.load() == ScheduleState())
    }

    // MARK: Path scans

    @Test func pathScanPolicy() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("paths-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home")
        let root = home.appendingPathComponent("Projects")
        let inside = root.appendingPathComponent("app")
        let elsewhere = home.appendingPathComponent("Downloads/thing")
        for d in [inside, elsewhere] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        func decide(_ url: URL) -> PathScanPolicy.Decision { PathScanPolicy.decide(url, scanRoots: [root], home: home) }
        #expect(decide(URL(fileURLWithPath: "/")) != .scan && decide(URL(fileURLWithPath: "/")) != .confirm)
        if case .reject = decide(home) {} else { Issue.record("home must be rejected") }
        for system in ["/System/Library", "/usr/local", "/Library", "/Applications", "/bin", "/Volumes", "/private/etc"] {
            if case .reject = decide(URL(fileURLWithPath: system)) {} else { Issue.record("\(system) must be rejected") }
        }
        #expect(decide(root) == .scan)
        #expect(decide(inside) == .scan)
        #expect(decide(elsewhere) == .confirm)
        #expect(decide(URL(fileURLWithPath: "/Volumes/External/Projects")) == .confirm)
    }

    @Test func mergeKeepsOtherProjectsAndPersistsOnlyScanRoots() {
        func project(_ path: String, _ size: Int64) -> Project {
            let url = URL(fileURLWithPath: path)
            let c = Candidate(id: "r|\(path)/nm", url: url.appendingPathComponent("nm"), kind: .projectArtifact,
                              title: "nm", ecosystemID: "javascript", ruleID: "r", risk: .safe, sizeBytes: size)
            return Project(url: url, name: url.lastPathComponent, candidates: [c])
        }
        let existing = [project("/r/a", 10), project("/r/b", 20), project("/r/b/sub", 5)]
        let merged = ScanMerge.merge(existing: existing, found: [project("/r/b", 1), project("/x/new", 30)],
                                     replacing: [URL(fileURLWithPath: "/r/b"), URL(fileURLWithPath: "/x")])
        #expect(merged.map(\.url.path) == ["/x/new", "/r/a", "/r/b"])
        #expect(merged.first { $0.url.path == "/r/b" }?.reclaimableBytes == 1)
        let saved = ScanMerge.persistable(merged, scanRoots: [URL(fileURLWithPath: "/r")])
        #expect(saved.map(\.url.path) == ["/r/a", "/r/b"])
    }
}
