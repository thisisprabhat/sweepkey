import Foundation
import Testing
@testable import CleanerKit

private func mk(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func collect(
    _ scanner: ProjectScanner, _ options: ScanOptions
) async throws -> (projects: [Project], summary: ScanSummary?) {
    var projects: [Project] = []
    var summary: ScanSummary?
    for try await event in scanner.scan(options) {
        switch event {
        case .project(let p): projects.append(p)
        case .finished(let s): summary = s
        case .progress: break
        }
    }
    return (projects, summary)
}

private func options(_ root: URL, git: Bool = false, _ tweak: (inout ScanOptions) -> Void = { _ in }) -> ScanOptions {
    var o = ScanOptions(roots: [root], includeGitInfo: git)
    tweak(&o)
    return o
}

@Suite struct ScannerTests {
    let emptyHome = FileManager.default.temporaryDirectory.appendingPathComponent("nohome-\(UUID().uuidString)")

    private func scanner(now: @escaping @Sendable () -> Date = Date.init, home: URL? = nil) -> ProjectScanner {
        ProjectScanner(now: now, home: home ?? emptyHome)
    }

    @Test func jsProjectGivesNodeModules() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("app")
            try write(10, to: p.appendingPathComponent("package.json"))
            try write(10_000, to: p.appendingPathComponent("node_modules/dep/index.js"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.count == 1)
            let c = try #require(r.projects.first?.candidates.first)
            #expect(c.id == "javascript.node_modules|\(p.path)/node_modules")
            #expect(c.title == "node_modules")
            #expect(c.regenerateHint == "npm install")
            #expect(c.projectRoot == p)
            #expect(c.lastModified != nil)
            #expect(r.projects.first?.ecosystemIDs == ["javascript"])
        }
    }

    @Test func buildWithoutMarkerGivesNothing() async throws {
        try await withTempDir { root in
            try write(100, to: root.appendingPathComponent("thing/build/out.bin"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.isEmpty)
            #expect(r.summary?.projectCount == 0)
        }
    }

    @Test func flutterProject() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("fl")
            try write(10, to: p.appendingPathComponent("pubspec.yaml"))
            try write(100, to: p.appendingPathComponent("build/a"))
            try write(100, to: p.appendingPathComponent(".dart_tool/b"))
            try write(100, to: p.appendingPathComponent("ios/Pods/c"))
            try write(10, to: p.appendingPathComponent("android/app/build.gradle"))
            try write(100, to: p.appendingPathComponent("android/app/build/d"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.count == 1)
            let ids = Set(r.projects[0].candidates.map(\.ruleID))
            #expect(ids.isSuperset(of: ["flutter.build", "flutter.dart_tool", "flutter.ios_pods", "flutter.android_app_build"]))
            // the nested gradle rule must not duplicate android/app/build
            let paths = r.projects[0].candidates.map(\.url.path)
            #expect(Set(paths).count == paths.count)
        }
    }

    @Test func rustTargetNeedsCargoToml() async throws {
        try await withTempDir { root in
            let a = root.appendingPathComponent("rs")
            try write(10, to: a.appendingPathComponent("Cargo.toml"))
            try write(100, to: a.appendingPathComponent("target/debug/x"))
            try write(100, to: root.appendingPathComponent("plain/target/x"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.map(\.url) == [a])
            #expect(r.projects[0].candidates.map(\.ruleID) == ["rust.target"])
        }
    }

    @Test func globTargets() async throws {
        try await withTempDir { root in
            let c = root.appendingPathComponent("cm")
            try write(10, to: c.appendingPathComponent("CMakeLists.txt"))
            try write(10, to: c.appendingPathComponent("cmake-build-debug/x"))
            let py = root.appendingPathComponent("py")
            try write(10, to: py.appendingPathComponent("setup.py"))
            try write(10, to: py.appendingPathComponent("pkg.egg-info/PKG-INFO"))
            let r = try await collect(scanner(), options(root))
            let byName = Dictionary(uniqueKeysWithValues: r.projects.map { ($0.name, $0) })
            #expect(byName["cm"]?.candidates.map(\.ruleID) == ["cpp.cmake_build"])
            #expect(byName["py"]?.candidates.map(\.ruleID) == ["python.egg_info"])
        }
    }

    @Test func nestedMonorepoPackagesAreSeparateProjects() async throws {
        try await withTempDir { root in
            let m = root.appendingPathComponent("mono")
            try write(10, to: m.appendingPathComponent("package.json"))
            try write(10, to: m.appendingPathComponent("node_modules/x"))
            let a = m.appendingPathComponent("packages/a")
            try write(10, to: a.appendingPathComponent("package.json"))
            try write(10, to: a.appendingPathComponent("node_modules/y"))
            try write(10, to: a.appendingPathComponent(".next/z"))
            let r = try await collect(scanner(), options(root))
            #expect(Set(r.projects.map(\.url)) == [m, a])
            let pa = try #require(r.projects.first { $0.url == a })
            #expect(Set(pa.candidates.map(\.ruleID)) == ["javascript.node_modules", "javascript.next"])
            let pm = try #require(r.projects.first { $0.url == m })
            #expect(pm.candidates.map(\.ruleID) == ["javascript.node_modules"])
        }
    }

    @Test func doesNotDescendIntoNodeModules() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("app")
            try write(10, to: p.appendingPathComponent("package.json"))
            try write(10, to: p.appendingPathComponent("node_modules/dep/package.json"))
            try write(10, to: p.appendingPathComponent("node_modules/dep/node_modules/q"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.count == 1)
        }
    }

    @Test func symlinkedDirectoryIsNotFollowed() async throws {
        try await withTempDir { root in
            let outside = root.appendingPathComponent("outside/proj")
            try write(10, to: outside.appendingPathComponent("package.json"))
            try write(10, to: outside.appendingPathComponent("node_modules/x"))
            let scanRoot = root.appendingPathComponent("scan")
            try mk(scanRoot)
            try FileManager.default.createSymbolicLink(
                at: scanRoot.appendingPathComponent("link"), withDestinationURL: outside)
            let r = try await collect(scanner(), options(scanRoot))
            #expect(r.projects.isEmpty)
        }
    }

    @Test func excludedPathIsSkipped() async throws {
        try await withTempDir { root in
            for n in ["keep", "skip"] {
                try write(10, to: root.appendingPathComponent("\(n)/package.json"))
                try write(10, to: root.appendingPathComponent("\(n)/node_modules/x"))
            }
            let r = try await collect(scanner(), options(root) { $0.excludedPaths = [root.appendingPathComponent("skip")] })
            #expect(r.projects.map(\.name) == ["keep"])
        }
    }

    @Test func libraryUnderHomeIsSkippedButOtherLibraryIsNot() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent("Library/p/package.json"))
            try write(10, to: home.appendingPathComponent("Library/p/node_modules/x"))
            try write(10, to: home.appendingPathComponent("Projects/Library/p/package.json"))
            try write(10, to: home.appendingPathComponent("Projects/Library/p/node_modules/x"))
            let r = try await collect(scanner(home: home), options(home))
            #expect(r.projects.map(\.url.path) == [home.appendingPathComponent("Projects/Library/p").path])
        }
    }

    @Test func disabledOverrideAndCustomRule() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("app")
            try write(10, to: p.appendingPathComponent("package.json"))
            try write(10, to: p.appendingPathComponent("node_modules/x"))
            try write(10, to: p.appendingPathComponent("coverage/x"))
            try write(10, to: p.appendingPathComponent("my.marker"))
            try write(10, to: p.appendingPathComponent("gen-out/x"))
            let custom = Rule(id: "custom.gen", ecosystemID: "generic", markers: ["my.marker"], target: "gen-out",
                              risk: .caution, enabledByDefault: true)
            let r = try await collect(scanner(), options(root) {
                $0.ruleOverrides = ["javascript.node_modules": false]
                $0.customRules = [custom]
            })
            let ids = Set(r.projects.flatMap { $0.candidates.map(\.ruleID) })
            #expect(ids == ["javascript.coverage", "custom.gen"])
        }
    }

    @Test func cleanerIgnore() async throws {
        try await withTempDir { root in
            let a = root.appendingPathComponent("a")
            try write(10, to: a.appendingPathComponent("package.json"))
            try write(10, to: a.appendingPathComponent("node_modules/x"))
            try write(10, to: a.appendingPathComponent("coverage/x"))
            try Data("# keep modules\nnode_modules\n\n".utf8).write(to: a.appendingPathComponent(".cleanerignore"))
            let b = root.appendingPathComponent("b")
            try write(10, to: b.appendingPathComponent("package.json"))
            try write(10, to: b.appendingPathComponent("node_modules/x"))
            try Data("*\n".utf8).write(to: b.appendingPathComponent(".cleanerignore"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.map(\.name) == ["a"])
            #expect(r.projects[0].candidates.map(\.ruleID) == ["javascript.coverage"])
        }
    }

    @Test func staleFlagUsesInjectedNow() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("app")
            try write(10, to: p.appendingPathComponent("package.json"))
            try write(10, to: p.appendingPathComponent("node_modules/x"))
            let fresh = try await collect(scanner(), options(root))
            #expect(fresh.projects[0].isStale == false)
            #expect(fresh.projects[0].lastActivity != nil)
            let later = try await collect(scanner(now: { Date().addingTimeInterval(60 * 86_400) }), options(root))
            #expect(later.projects[0].isStale)
            let lenient = try await collect(scanner(now: { Date().addingTimeInterval(60 * 86_400) }),
                                            options(root) { $0.staleAfterDays = 90 })
            #expect(lenient.projects[0].isStale == false)
        }
    }

    @Test func sizeMatchesBytesWritten() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("app")
            try write(10, to: p.appendingPathComponent("package.json"))
            try write(50_000, to: p.appendingPathComponent("node_modules/a.bin"))
            try write(70_000, to: p.appendingPathComponent("node_modules/sub/b.bin"))
            let r = try await collect(scanner(), options(root))
            let c = try #require(r.projects.first?.candidates.first)
            #expect(c.sizeBytes >= 120_000)
            #expect(c.sizeBytes < 120_000 + 64 * 1024)
            #expect(c.sizeBytes == SizeCalculator().allocatedSize(of: p.appendingPathComponent("node_modules")))
        }
    }

    @Test func finishedSummaryIsCorrect() async throws {
        try await withTempDir { root in
            for n in ["a", "b"] {
                let p = root.appendingPathComponent(n)
                try write(10, to: p.appendingPathComponent("package.json"))
                try write(20_000, to: p.appendingPathComponent("node_modules/x"))
                try write(20_000, to: p.appendingPathComponent("coverage/x"))
            }
            let r = try await collect(scanner(), options(root) { $0.maxConcurrency = 2 })
            let s = try #require(r.summary)
            #expect(s.projectCount == 2)
            #expect(s.candidateCount == 4)
            #expect(s.totalBytes == r.projects.reduce(0) { $0 + $1.reclaimableBytes })
            #expect(s.finishedAt >= s.startedAt)
        }
    }

    @Test func gitInfoIsAttached() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("app")
            try write(10, to: p.appendingPathComponent("package.json"))
            try write(10, to: p.appendingPathComponent("node_modules/x"))
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.currentDirectoryURL = p
            proc.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "init", "-q"]
            try proc.run(); proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return }
            let commit = Process()
            commit.executableURL = proc.executableURL
            commit.currentDirectoryURL = p
            commit.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"]
            try commit.run(); commit.waitUntilExit()
            guard commit.terminationStatus == 0 else { return }
            let r = try await collect(scanner(), options(root, git: true))
            #expect(r.projects.first?.git?.lastCommitDate != nil)
            let late = try await collect(scanner(now: { Date().addingTimeInterval(90 * 86_400) }), options(root, git: true))
            #expect(late.projects.first?.isStale == true)
        }
    }

    @Test func cancellationStopsTheScan() async throws {
        try await withTempDir { root in
            for i in 0..<60 {
                for j in 0..<20 { try mk(root.appendingPathComponent("d\(i)/e\(j)/f")) }
            }
            let s = scanner()
            let o = options(root)
            let task = Task { () -> (sawProgress: Bool, finished: Bool) in
                var saw = false
                var finished = false
                do {
                    for try await event in s.scan(o) {
                        switch event {
                        case .progress:
                            saw = true
                            withUnsafeCurrentTask { $0?.cancel() }
                        case .finished: finished = true
                        case .project: break
                        }
                    }
                } catch {}
                return (saw, finished)
            }
            let r = await task.value
            #expect(r.sawProgress)
            #expect(r.finished == false)
        }
    }

    @Test func symlinkTargetsAreNeverCandidates() async throws {
        try await withTempDir { root in
            let outside = root.appendingPathComponent("outside")
            try write(10, to: outside.appendingPathComponent("x"))
            let b = root.appendingPathComponent("scan/bz")
            try write(1, to: b.appendingPathComponent("WORKSPACE"))
            try FileManager.default.createSymbolicLink(at: b.appendingPathComponent("bazel-out"), withDestinationURL: outside)
            let js = root.appendingPathComponent("scan/js")
            try write(1, to: js.appendingPathComponent("package.json"))
            try FileManager.default.createSymbolicLink(at: js.appendingPathComponent("node_modules"), withDestinationURL: outside)
            let fl = root.appendingPathComponent("scan/fl")
            try write(1, to: fl.appendingPathComponent("pubspec.yaml"))
            try mk(fl)
            try FileManager.default.createSymbolicLink(at: fl.appendingPathComponent("ios"), withDestinationURL: outside)
            let r = try await collect(scanner(), options(root.appendingPathComponent("scan")))
            #expect(r.projects.isEmpty)
        }
    }

    @Test func unityAndPhpNeedTheirMarkers() async throws {
        try await withTempDir { root in
            let u = root.appendingPathComponent("u")
            try write(1, to: u.appendingPathComponent("Library/x"))
            try write(1, to: u.appendingPathComponent("ProjectSettings/other.asset"))
            let php = root.appendingPathComponent("php")
            try write(1, to: php.appendingPathComponent("vendor/x"))
            var r = try await collect(scanner(), options(root))
            #expect(r.projects.isEmpty)
            try write(1, to: u.appendingPathComponent("ProjectSettings/ProjectVersion.txt"))
            try write(1, to: php.appendingPathComponent("composer.json"))
            r = try await collect(scanner(), options(root))
            #expect(Set(r.projects.flatMap { $0.candidates.map(\.ruleID) }) == ["unity.library", "php.vendor"])
        }
    }

    @Test func disabledRuleTargetsAreNotDescended() async throws {
        try await withTempDir { root in
            let p = root.appendingPathComponent("go")
            try write(1, to: p.appendingPathComponent("go.mod"))
            try write(1, to: p.appendingPathComponent("vendor/inner/package.json"))
            try write(1, to: p.appendingPathComponent("vendor/inner/node_modules/x"))
            let r = try await collect(scanner(), options(root))
            #expect(r.projects.isEmpty)
        }
    }

    @Test func scanCacheRoundTrips() async throws {
        try await withTempDir { dir in
            let cache = ScanCache(url: dir.appendingPathComponent("sub/cache.json"))
            #expect(await cache.load() == nil)
            let p = Project(url: dir.appendingPathComponent("p"), name: "p", ecosystemIDs: ["rust"], lastActivity: Date(timeIntervalSince1970: 1_700_000_000))
            let when = Date(timeIntervalSince1970: 1_700_000_100)
            try await cache.save([p], at: when)
            let snap = try #require(await cache.load())
            #expect(snap.projects == [p])
            #expect(snap.savedAt == when)
            let frac = Date(timeIntervalSince1970: 1_700_000_100.123456)
            try await cache.save([p], at: frac)
            #expect(await cache.load()?.savedAt == frac)
        }
    }
}
