import CoreGraphics
import Foundation
import Testing
@testable import CleanerKit

private let GB: Int64 = 1_073_741_824

private func cand(
    _ name: String, rule: String = "r", size: Int64, risk: RiskLevel = .safe,
    kind: CandidateKind = .projectArtifact
) -> Candidate {
    Candidate(
        id: "\(rule)|/\(name)", url: URL(fileURLWithPath: "/\(name)"), kind: kind, title: name,
        ecosystemID: "generic", ruleID: rule, risk: risk, sizeBytes: size)
}

private func proj(_ name: String, stale: Bool, _ cs: [Candidate]) -> Project {
    Project(url: URL(fileURLWithPath: "/p/\(name)"), name: name, candidates: cs, isStale: stale)
}

private func group(_ cs: [Candidate]) -> CacheGroup {
    CacheGroup(id: "g", title: "g", category: .misc, symbolName: "tray", candidates: cs)
}

private func allowAll(_ cs: [Candidate]) -> [Candidate.ID: SafetyVerdict] {
    Dictionary(uniqueKeysWithValues: cs.map { ($0.id, SafetyVerdict.allowed) })
}

@Suite struct InsightsEngineTests {
    @Test func nodeModulesThreshold() {
        func nodes(_ n: Int) -> [Project] {
            [proj("a", stale: false, (0..<n).map { cand("n\($0)", rule: "javascript.node_modules", size: GB) })]
        }
        #expect(InsightsEngine.suggestions(projects: nodes(4), caches: []).isEmpty)
        let s = InsightsEngine.suggestions(projects: nodes(5), caches: [])
        #expect(s.map(\.id) == ["node-modules-dedupe"])
        #expect(s[0].title.contains("5 copies"))
        #expect(s[0].estimatedBytes == 5 * GB)
    }

    @Test func venvThreshold() {
        func venvs(_ n: Int) -> [Project] {
            [proj("a", stale: false, (0..<n).map { cand("v\($0)", rule: "python.venv", size: GB) })]
        }
        #expect(InsightsEngine.suggestions(projects: venvs(2), caches: []).isEmpty)
        #expect(InsightsEngine.suggestions(projects: venvs(3), caches: []).map(\.id) == ["python-venvs-uv"])
    }

    @Test func simulators() {
        #expect(InsightsEngine.suggestions(projects: [], caches: [group([])]).isEmpty)
        let sim = cand("s", rule: "xcode.unavailableSimulators", size: 0, kind: .globalCache)
        #expect(InsightsEngine.suggestions(projects: [], caches: [group([sim])]).map(\.id) == ["xcode-simulators"])
        let rt = cand("r", rule: "xcode.runtime.abc", size: GB, kind: .globalCache)
        #expect(InsightsEngine.suggestions(projects: [], caches: [group([rt])]).first?.estimatedBytes == GB)
    }

    @Test func derivedDataAndDockerAreStrictlyGreaterThanThreshold() {
        func dd(_ b: Int64) -> [CacheGroup] { [group([cand("d", rule: "xcode.derivedData", size: b, kind: .globalCache)])] }
        #expect(InsightsEngine.suggestions(projects: [], caches: dd(10 * GB)).isEmpty)
        #expect(InsightsEngine.suggestions(projects: [], caches: dd(10 * GB + 1)).map(\.id) == ["derived-data"])
        func dk(_ b: Int64) -> [CacheGroup] { [group([cand("k", rule: "container.images", size: b, kind: .globalCache)])] }
        #expect(InsightsEngine.suggestions(projects: [], caches: dk(5 * GB)).isEmpty)
        #expect(InsightsEngine.suggestions(projects: [], caches: dk(5 * GB + 1)).map(\.id) == ["docker-reclaimable"])
        let info = [group([cand("i", rule: "container.dockerDisk.info", size: 50 * GB, kind: .globalCache)])]
        #expect(InsightsEngine.suggestions(projects: [], caches: info).isEmpty)
    }

    @Test func staleProjects() {
        let a = proj("a", stale: true, [cand("a", size: 10 * GB)])
        #expect(InsightsEngine.suggestions(projects: [a], caches: []).isEmpty)
        let b = proj("b", stale: true, [cand("b", size: 1)])
        #expect(InsightsEngine.suggestions(projects: [a, b], caches: []).map(\.id) == ["stale-projects"])
        let fresh = proj("c", stale: false, [cand("c", size: 20 * GB)])
        #expect(InsightsEngine.suggestions(projects: [fresh], caches: []).isEmpty)
    }

    @Test func trendGroupsByDayAndIgnoresDryRuns() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func report(_ t: TimeInterval, dry: Bool, bytes: Int64) -> CleanReport {
            let item = CleanItemResult(candidate: cand("x", size: bytes), status: dry ? .dryRun : .cleaned, freedBytes: bytes)
            return CleanReport(
                startedAt: Date(timeIntervalSince1970: t), finishedAt: Date(timeIntervalSince1970: t),
                mode: .permanent, dryRun: dry, items: [item])
        }
        let points = InsightsEngine.trend(reports: [
            report(86_400 * 2 + 10, dry: false, bytes: 5), report(86_400 * 2 + 99, dry: false, bytes: 7),
            report(86_400 * 1, dry: false, bytes: 1), report(86_400 * 3, dry: true, bytes: 100),
        ], calendar: cal)
        #expect(points.map(\.freedBytes) == [1, 12])
    }
}

@Suite struct FreeUpPlannerTests {
    @Test func orderingAcrossTiers() {
        let staleBig = cand("staleBig", size: 50), staleSmall = cand("staleSmall", size: 10)
        let cache = cand("cache", rule: "c", size: 80, kind: .globalCache)
        let fresh = cand("fresh", size: 100)
        let caution = cand("caution", size: 500, risk: .caution)
        let projects = [proj("s", stale: true, [staleSmall, staleBig]), proj("f", stale: false, [fresh, caution])]
        let caches = [group([cache])]
        let all = [staleBig, staleSmall, cache, fresh, caution]
        let plan = FreeUpPlanner.plan(target: 10_000, projects: projects, caches: caches, verdicts: allowAll(all))
        #expect(plan.map(\.title) == ["staleBig", "staleSmall", "cache", "fresh", "caution"])
    }

    @Test func stopsOnceTargetMet() {
        let a = cand("a", size: 50), b = cand("b", size: 30), c = cand("c", size: 20)
        let p = [proj("s", stale: true, [a, b, c])]
        let plan = FreeUpPlanner.plan(target: 80, projects: p, caches: [], verdicts: allowAll([a, b, c]))
        #expect(plan.map(\.title) == ["a", "b"])
        #expect(FreeUpPlanner.plan(target: 0, projects: p, caches: [], verdicts: allowAll([a])).isEmpty)
    }

    @Test func cautionOnlyWhenStillShort() {
        let safe = cand("safe", size: 100), caution = cand("caution", size: 100, risk: .caution)
        let p = [proj("s", stale: true, [safe, caution])]
        let v = allowAll([safe, caution])
        #expect(FreeUpPlanner.plan(target: 100, projects: p, caches: [], verdicts: v).map(\.title) == ["safe"])
        #expect(FreeUpPlanner.plan(target: 150, projects: p, caches: [], verdicts: v).map(\.title) == ["safe", "caution"])
    }

    @Test func excludesDangerBlockedAndMissingVerdicts() {
        let danger = cand("danger", size: 100, risk: .danger), blocked = cand("blocked", size: 100)
        let missing = cand("missing", size: 100), ok = cand("ok", size: 1)
        let warn = cand("warn", size: 5)
        let p = [proj("s", stale: true, [danger, blocked, missing, ok, warn])]
        let verdicts: [Candidate.ID: SafetyVerdict] = [
            danger.id: .allowed, blocked.id: .blocked("x"), ok.id: .allowed, warn.id: .warning("w"),
        ]
        let plan = FreeUpPlanner.plan(target: 10_000, projects: p, caches: [], verdicts: verdicts)
        #expect(plan.map(\.title) == ["warn", "ok"])
    }
}

@Suite struct PreArchiveCheckTests {
    @Test func reportsDirtyUnpushedAndStashes() {
        func p(_ git: GitInfo?) -> Project {
            Project(url: URL(fileURLWithPath: "/p/x"), name: "x", git: git)
        }
        let root = URL(fileURLWithPath: "/p/x")
        #expect(PreArchiveCheck.risks(projects: [p(nil)]).isEmpty)
        #expect(PreArchiveCheck.risks(projects: [p(GitInfo(repositoryRoot: root))]).isEmpty)
        let r = PreArchiveCheck.risks(projects: [p(GitInfo(
            repositoryRoot: root, isDirty: true, unpushedCommitCount: 2, stashCount: 1))])
        #expect(r.map(\.kind) == [.dirty, .unpushed(2), .stashes(1)])
    }
}

@Suite struct TreemapTests {
    private let bounds = CGRect(x: 10, y: 20, width: 400, height: 300)

    @Test func tilesBoundsWithProportionalAreas() {
        let weights: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Treemap.layout(weights: weights, in: bounds)
        #expect(rects.count == weights.count)
        let total = weights.reduce(0, +)
        var area = 0.0
        for (w, r) in zip(weights, rects) {
            let a = Double(r.width * r.height)
            area += a
            #expect(abs(a - Double(bounds.width * bounds.height) * w / total) < 0.01)
            #expect(r.minX >= bounds.minX - 0.001 && r.maxX <= bounds.maxX + 0.001)
            #expect(r.minY >= bounds.minY - 0.001 && r.maxY <= bounds.maxY + 0.001)
        }
        #expect(abs(area - Double(bounds.width * bounds.height)) < 0.01)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func zeroEmptyAndInvalidWeights() {
        #expect(Treemap.layout(weights: [], in: bounds).isEmpty)
        #expect(Treemap.layout(weights: [0, 0], in: bounds) == [.zero, .zero])
        let r = Treemap.layout(weights: [0, 5, -1, .nan, 5], in: bounds)
        #expect(r[0] == .zero && r[2] == .zero && r[3] == .zero)
        #expect(abs(Double(r[1].width * r[1].height) - 60_000) < 0.01)
        #expect(Treemap.layout(weights: [1], in: bounds) == [bounds])
        #expect(Treemap.layout(weights: [1, 2], in: .zero) == [.zero, .zero])
    }
}
