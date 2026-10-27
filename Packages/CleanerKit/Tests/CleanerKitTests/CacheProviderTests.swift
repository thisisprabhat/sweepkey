import Foundation
import Testing
@testable import CleanerKit

final class CacheFakeShell: ShellRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private let responses: [String: String]
    init(_ responses: [String: String] = [:]) { self.responses = responses }
    var calls: [String] { lock.withLock { _calls } }

    func run(_ executable: String, arguments: [String], currentDirectory: URL?,
             input: Data?, timeout: Duration) async throws -> ShellResult {
        let key = ([executable] + arguments).joined(separator: " ")
        lock.withLock { _calls.append(key) }
        guard let out = responses[key] else { throw ShellError.executableNotFound(executable) }
        return ShellResult(exitCode: 0, stdout: out, stderr: "")
    }
}

private func context(_ home: URL, shell: CacheFakeShell = CacheFakeShell(), tools: Set<String> = []) -> CacheContext {
    CacheContext(
        home: home, shell: shell, sizer: SizeCalculator(),
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        resolve: { tools.contains($0) ? "/fake/bin/\($0)" : nil })
}

private func mkdir(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func assertContained(_ groups: [CacheGroup], in home: URL) {
    for c in groups.flatMap(\.candidates) {
        if case .command = c.action { continue }
        #expect(c.url.path.hasPrefix(home.path), "\(c.url.path) escapes fake home")
    }
}

@Suite struct CacheProviderTests {
    @Test func derivedDataChildrenAreSeparateCandidates() async throws {
        try await withTempDir { home in
            let dd = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            try write(10_000, to: dd.appendingPathComponent("AppA-abc/file"))
            try write(50_000, to: dd.appendingPathComponent("AppB-def/file"))
            let groups = await XcodeProvider().detect(context(home))
            let g = try #require(groups.first { $0.id == "xcode.derivedData" })
            #expect(g.candidates.count == 2)
            let a = try #require(g.candidates.first { $0.title == "AppA-abc" })
            let b = try #require(g.candidates.first { $0.title == "AppB-def" })
            #expect(a.sizeBytes >= 10_000 && a.sizeBytes < b.sizeBytes)
            #expect(a.risk == .safe && a.kind == .globalCache && a.ecosystemID == "xcode")
            #expect(a.id == "xcode.derivedData|\(a.url.path)")
            assertContained(groups, in: home)
        }
    }

    @Test func archivesAreDanger() async throws {
        try await withTempDir { home in
            let a = home.appendingPathComponent("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive")
            try write(100, to: a.appendingPathComponent("Info.plist"))
            let groups = await XcodeProvider().detect(context(home))
            let g = try #require(groups.first { $0.id == "xcode.archives" })
            #expect(g.candidates.count == 1)
            #expect(g.candidates[0].risk == .danger)
            #expect(g.candidates[0].note == "Contains dSYMs needed to symbolicate crash reports")
        }
    }

    @Test func unavailableSimulatorsOnlyWhenListed() async throws {
        try await withTempDir { home in
            let key = "xcrun simctl list devices unavailable -j"
            let withEntries = CacheFakeShell([key: #"{"devices":{"rt":[{"udid":"1"}]}}"#])
            let g1 = await XcodeProvider().detect(context(home, shell: withEntries, tools: ["xcrun"]))
            let sims1 = try #require(g1.first { $0.id == "xcode.simulators" })
            let c = try #require(sims1.candidates.first { $0.ruleID == "xcode.unavailableSimulators" })
            #expect(c.action == .command(executable: "xcrun", arguments: ["simctl", "delete", "unavailable"]))
            #expect(c.sizeBytes == 0 && c.note == "Size unknown until cleaned")

            let empty = CacheFakeShell([key: #"{"devices":{"rt":[]}}"#])
            let g2 = await XcodeProvider().detect(context(home, shell: empty, tools: ["xcrun"]))
            #expect(!g2.flatMap(\.candidates).contains { $0.ruleID == "xcode.unavailableSimulators" })
        }
    }

    @Test func simulatorRuntimesUseJSONSize() async throws {
        try await withTempDir { home in
            let json = #"{"AAA-1":{"identifier":"AAA-1","version":"18.0","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":7000000000}}"#
            let shell = CacheFakeShell([
                "xcrun simctl list devices unavailable -j": #"{"devices":{}}"#,
                "xcrun simctl runtime list -j": json,
            ])
            let groups = await XcodeProvider().detect(context(home, shell: shell, tools: ["xcrun"]))
            let c = try #require(groups.flatMap(\.candidates).first { $0.ruleID == "xcode.runtime.AAA-1" })
            #expect(c.risk == .caution && c.sizeBytes == 7_000_000_000)
            #expect(c.action == .command(executable: "xcrun", arguments: ["simctl", "runtime", "delete", "AAA-1"]))
        }
    }

    @Test func npmUsesCommandWhenResolvable() async throws {
        try await withTempDir { home in
            try write(1000, to: home.appendingPathComponent(".npm/_cacache/x"))
            let with = await PackageManagerProvider().detect(context(home, tools: ["npm"]))
            let c1 = try #require(with.flatMap(\.candidates).first { $0.ruleID == "pm.npm" })
            #expect(c1.action == .command(executable: "npm", arguments: ["cache", "clean", "--force"]))
            #expect(c1.sizeBytes >= 1000)

            let without = await PackageManagerProvider().detect(context(home))
            let c2 = try #require(without.flatMap(\.candidates).first { $0.ruleID == "pm.npm" })
            #expect(c2.action == .delete)
            assertContained(without, in: home)
        }
    }

    @Test func pubPrefersFlutterThenDartThenDelete() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent(".pub-cache/x"))
            func action(_ tools: Set<String>) async throws -> CleanAction {
                let g = await PackageManagerProvider().detect(context(home, tools: tools))
                return try #require(g.flatMap(\.candidates).first { $0.ruleID == "pm.pub" }).action
            }
            #expect(try await action(["flutter", "dart"]) == .command(executable: "flutter", arguments: ["pub", "cache", "clean", "-f"]))
            #expect(try await action(["dart"]) == .command(executable: "dart", arguments: ["pub", "cache", "clean", "-f"]))
            #expect(try await action([]) == .delete)
        }
    }

    @Test func homebrewSizedFromBrewCache() async throws {
        try await withTempDir { home in
            let cache = home.appendingPathComponent("brewcache")
            try write(4000, to: cache.appendingPathComponent("bottle"))
            let shell = CacheFakeShell(["brew --cache": cache.path + "\n"])
            let g = await PackageManagerProvider().detect(context(home, shell: shell, tools: ["brew"]))
            let c = try #require(g.flatMap(\.candidates).first { $0.ruleID == "pm.homebrew" })
            #expect(c.action == .command(executable: "brew", arguments: ["cleanup", "--prune=all"]))
            #expect(c.sizeBytes >= 4000)
            #expect(c.title.contains("old formula versions"))
        }
    }

    @Test func homebrewWithoutBrewIsPlainDownloads() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent("Library/Caches/Homebrew/x"))
            let g = await PackageManagerProvider().detect(context(home))
            let c = try #require(g.flatMap(\.candidates).first { $0.ruleID == "pm.homebrew" })
            #expect(c.action == .delete)
            #expect(c.title == "Homebrew downloads")
        }
    }

    @Test func gemIsCautionWithHonestHint() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent(".gem/ruby/3.3.0/gems/x"))
            let g = await PackageManagerProvider().detect(context(home))
            let c = try #require(g.flatMap(\.candidates).first { $0.ruleID == "pm.gem" })
            #expect(c.risk == .caution)
            #expect(!(c.regenerateHint ?? "").contains("automatically"))
        }
    }

    @Test func diagnosticReportsAreCautionAndOptIn() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent("Library/Logs/DiagnosticReports/a.ips"))
            let groups = await MiscProvider().detect(context(home))
            let c = try #require(groups.flatMap(\.candidates).first { $0.ruleID == OptInCaches.diagnosticReports })
            #expect(c.risk == .caution)
            // Off by default: the only candidate disappears, and so does its now-empty group.
            #expect(OptInCaches.apply(groups, overrides: [:]).flatMap(\.candidates).isEmpty)
            #expect(OptInCaches.apply(groups, overrides: [OptInCaches.diagnosticReports: false]).isEmpty)
            let on = OptInCaches.apply(groups, overrides: [OptInCaches.diagnosticReports: true])
            #expect(on.flatMap(\.candidates).map(\.ruleID) == [OptInCaches.diagnosticReports])
        }
    }

    @Test func optInFilterKeepsOtherItemsAndInfoGroups() {
        let other = Candidate(
            id: "x|/h/x", url: URL(fileURLWithPath: "/h/x"), kind: .globalCache, title: "x", ecosystemID: "misc",
            ruleID: "misc.iosBackup", risk: .danger, sizeBytes: 1)
        let groups = [
            CacheGroup(id: "misc.other", title: "Other", category: .misc, symbolName: "x", candidates: [other]),
            CacheGroup(id: "container.dockerDisk.info", title: "Info", category: .container, symbolName: "x"),
        ]
        #expect(OptInCaches.apply(groups, overrides: [:]).map(\.id) == ["misc.other", "container.dockerDisk.info"])
    }

    @Test func gradleWrapperNewestIsCaution() async throws {
        try await withTempDir { home in
            let dists = home.appendingPathComponent(".gradle/wrapper/dists")
            for v in ["gradle-8.9-bin", "gradle-8.10-bin", "gradle-7.6-all"] {
                try write(100, to: dists.appendingPathComponent("\(v)/hash/f"))
            }
            let groups = await AndroidProvider().detect(context(home))
            let wrappers = try #require(groups.first { $0.id == "android.gradle" })
                .candidates.filter { $0.ruleID == "android.gradleWrapper" }
            #expect(wrappers.count == 3)
            #expect(wrappers.first { $0.url.lastPathComponent == "gradle-8.10-bin" }?.risk == .caution)
            #expect(wrappers.filter { $0.risk == .safe }.count == 2)
        }
    }

    @Test func androidSDKNewestIsDangerOthersCaution() async throws {
        try await withTempDir { home in
            let sdk = home.appendingPathComponent("Library/Android/sdk/build-tools")
            for v in ["34.0.0", "9.0.0"] { try write(10, to: sdk.appendingPathComponent("\(v)/aapt")) }
            try write(10, to: home.appendingPathComponent(".android/avd/Pixel.avd/config.ini"))
            let groups = await AndroidProvider().detect(context(home))
            let tools = try #require(groups.first { $0.id == "android.sdk" }).candidates
            #expect(tools.first { $0.url.lastPathComponent == "34.0.0" }?.risk == .danger)
            #expect(tools.first { $0.url.lastPathComponent == "9.0.0" }?.risk == .caution)
            #expect(groups.first { $0.id == "android.avd" }?.candidates.first?.risk == .danger)
        }
    }

    @Test func nvmVersionList() async throws {
        try await withTempDir { home in
            let base = home.appendingPathComponent(".nvm/versions/node")
            for v in ["v18.19.0", "v20.11.1", "v9.0.0"] { try write(100, to: base.appendingPathComponent("\(v)/bin/node")) }
            let groups = await VersionManagerProvider().detect(context(home))
            let g = try #require(groups.first { $0.id == "versionManager.nvm" })
            #expect(g.candidates.map(\.url.lastPathComponent).sorted() == ["v18.19.0", "v20.11.1", "v9.0.0"])
            #expect(g.candidates.first { $0.url.lastPathComponent == "v20.11.1" }?.risk == .danger)
            #expect(g.candidates.filter { $0.risk == .caution }.count == 2)
            #expect(g.candidates.allSatisfy { $0.ecosystemID == "versionManager" })
        }
    }

    @Test func dockerSystemDfParsing() async throws {
        try await withTempDir { home in
            let df = """
            {"Type":"Images","Reclaimable":"1.2GB (40%)","Size":"3GB"}
            {"Type":"Containers","Reclaimable":"10MB (100%)"}
            {"Type":"Local Volumes","Reclaimable":"500MB (50%)"}
            {"Type":"Build Cache","Reclaimable":"2GB"}
            """
            let shell = CacheFakeShell(["docker info": "ok", "docker system df --format {{json .}}": df])
            let groups = await ContainerProvider().detect(context(home, shell: shell, tools: ["docker"]))
            let g = try #require(groups.first { $0.id == "container.docker" })
            let images = try #require(g.candidates.first { $0.ruleID == "container.images" })
            #expect(images.sizeBytes == 1_200_000_000)
            #expect(images.action == .command(executable: "docker", arguments: ["image", "prune", "-af"]))
            #expect(images.risk == .caution)
            #expect(g.candidates.first { $0.ruleID == "container.containers" }?.risk == .caution)
            #expect(g.candidates.first { $0.ruleID == "container.buildCache" }?.risk == .safe)
            #expect(g.candidates.first { $0.ruleID == "container.volumes" }?.risk == .danger)
            #expect(g.candidates.first { $0.ruleID == "container.buildCache" }?.sizeBytes == 2_000_000_000)
            #expect(parseHumanSize("1.2GB (40%)") == 1_200_000_000)
        }
    }

    @Test func dockerSkippedWhenUnavailable() async throws {
        try await withTempDir { home in
            #expect(await ContainerProvider().detect(context(home)).isEmpty)
            let noDaemon = CacheFakeShell()
            #expect(await ContainerProvider().detect(context(home, shell: noDaemon, tools: ["docker"])).isEmpty)
        }
    }

    @Test func dockerRawInfoGroup() async throws {
        try await withTempDir { home in
            try write(5000, to: home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"))
            let shell = CacheFakeShell(["docker info": "ok", "docker system df --format {{json .}}": ""])
            let groups = await ContainerProvider().detect(context(home, shell: shell, tools: ["docker"]))
            let info = try #require(groups.first { $0.id == "container.dockerDisk.info" })
            #expect(info.candidates.isEmpty && info.detail != nil)
        }
    }

    @Test func ideOldExtensionVersionsAreSafe() async throws {
        try await withTempDir { home in
            let ext = home.appendingPathComponent(".vscode/extensions")
            for v in ["ms-python.python-2024.2.0", "ms-python.python-2024.10.0", "foo.bar-1.0.0"] {
                try write(10, to: ext.appendingPathComponent("\(v)/package.json"))
            }
            let groups = await IDEProvider().detect(context(home))
            let c = try #require(groups.first { $0.id == "ide.extensions" }).candidates
            #expect(c.count == 1)
            #expect(c[0].url.lastPathComponent == "ms-python.python-2024.2.0" && c[0].risk == .safe)
        }
    }

    @Test func aiModelsAreDangerAndOllamaUsesRm() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent(".cache/huggingface/hub/models--a--b/f"))
            try write(10, to: home.appendingPathComponent(".ollama/models/blobs/x"))
            let list = "NAME ID SIZE MODIFIED\nllama3:8b abc 4.7 GB 2 days ago\n"
            let shell = CacheFakeShell(["ollama list": list])
            let g = await AIModelProvider().detect(context(home, shell: shell, tools: ["ollama"]))
            let cands = try #require(g.first).candidates
            #expect(cands.allSatisfy { $0.risk == .danger })
            let o = try #require(cands.first { $0.ruleID == "ai.ollama.llama3:8b" })
            #expect(o.action == .command(executable: "ollama", arguments: ["rm", "llama3:8b"]))
            #expect(o.sizeBytes == 4_700_000_000)

            let fallback = await AIModelProvider().detect(context(home))
            #expect(fallback.flatMap(\.candidates).contains { $0.ruleID == "ai.ollama" && $0.action == .delete })
        }
    }

    @Test func miscBackupsAreDanger() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent("Library/Application Support/MobileSync/Backup/UDID/Info.plist"))
            let g = await MiscProvider().detect(context(home))
            let b = try #require(g.flatMap(\.candidates).first { $0.ruleID == "misc.iosBackup" })
            #expect(b.risk == .danger && b.note == "iOS device backup — cannot be regenerated")
        }
    }

    @Test func parseHumanSizeTable() {
        let table: [(String, Int64)] = [
            ("512kB", 512_000), ("3MB", 3_000_000), ("1.2GB (40%)", 1_200_000_000),
            ("2TB", 2_000_000_000_000), ("0B", 0), ("4.7 GB", 4_700_000_000),
            ("10 MB", 10_000_000), ("garbage", 0),
        ]
        for (input, expected) in table { #expect(parseHumanSize(input) == expected, "\(input)") }
    }

    @Test func condaSingleCandidateSummed() async throws {
        try await withTempDir { home in
            try write(3000, to: home.appendingPathComponent("miniconda3/pkgs/a"))
            try write(5000, to: home.appendingPathComponent("miniforge3/pkgs/b"))
            let g = await PackageManagerProvider().detect(context(home, tools: ["conda"]))
            let c = g.flatMap(\.candidates).filter { $0.ruleID == "pm.conda" }
            #expect(c.count == 1 && c[0].sizeBytes >= 8000)
            #expect(c[0].url.path.hasSuffix("miniconda3/pkgs"))
            #expect(c[0].action == .command(executable: "conda", arguments: ["clean", "-a", "-y"]))
        }
    }

    @Test func homebrewFallsBackWhenBrewCacheFails() async throws {
        try await withTempDir { home in
            try write(10, to: home.appendingPathComponent("Library/Caches/Homebrew/x"))
            let g = await PackageManagerProvider().detect(context(home, shell: CacheFakeShell(), tools: ["brew"]))
            let c = try #require(g.flatMap(\.candidates).first { $0.ruleID == "pm.homebrew" })
            #expect(c.action == .command(executable: "brew", arguments: ["cleanup", "--prune=all"]))
            #expect(c.url.path.hasSuffix("Library/Caches/Homebrew"))
        }
    }

    @Test func rustupStableIsDanger() async throws {
        try await withTempDir { home in
            let base = home.appendingPathComponent(".rustup/toolchains")
            for v in ["stable-aarch64-apple-darwin", "nightly-2026-01-01-aarch64-apple-darwin"] {
                try write(10, to: base.appendingPathComponent("\(v)/bin/rustc"))
            }
            let g = await VersionManagerProvider().detect(context(home))
            let c = try #require(g.first { $0.id == "versionManager.rustup" }).candidates
            #expect(c.first { $0.url.lastPathComponent.hasPrefix("stable-") }?.risk == .danger)
            #expect(c.first { $0.url.lastPathComponent.hasPrefix("nightly") }?.risk == .caution)
        }
    }

    @Test func extensionWithDigitPublisher() async throws {
        try await withTempDir { home in
            let ext = home.appendingPathComponent(".vscode/extensions")
            for v in ["1password.op-1.2.0", "1password.op-1.10.0"] { try write(10, to: ext.appendingPathComponent("\(v)/p")) }
            let c = try #require(await IDEProvider().detect(context(home)).first { $0.id == "ide.extensions" }).candidates
            #expect(c.count == 1 && c[0].url.lastPathComponent == "1password.op-1.2.0")
        }
    }

    // MARK: scanner

    @Test func realProvidersOnEmptyHomeYieldNoGroups() async throws {
        try await withTempDir { home in
            let groups = await GlobalCacheScanner(context: context(home)).scanCaches()
            #expect(groups.isEmpty)
        }
    }

    @Test func dockerInfoGroupSurvivesScanner() async throws {
        try await withTempDir { home in
            try write(5000, to: home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"))
            let shell = CacheFakeShell(["docker info": "ok", "docker system df --format {{json .}}": ""])
            let groups = await GlobalCacheScanner(context: context(home, shell: shell, tools: ["docker"])).scanCaches()
            #expect(groups.map(\.id) == ["container.dockerDisk.info"])
        }
    }

    struct StubProvider: CacheProvider {
        let id: String
        let groups: [CacheGroup]
        func detect(_ context: CacheContext) async -> [CacheGroup] { groups }
    }

    private func cand(_ id: String, _ size: Int64, home: URL) -> Candidate {
        Candidate(id: id, url: home.appendingPathComponent(id), kind: .globalCache, title: id,
                  ecosystemID: "misc", ruleID: "r", risk: .safe, sizeBytes: size)
    }

    @Test func scannerDropsEmptyGroupsAndSortsBySize() async throws {
        try await withTempDir { home in
            let small = CacheGroup(id: "s", title: "S", category: .misc, symbolName: "x", candidates: [cand("a", 10, home: home)])
            let big = CacheGroup(id: "b", title: "B", category: .misc, symbolName: "x", candidates: [cand("b", 999, home: home)])
            let empty = CacheGroup(id: "e", title: "E", category: .misc, symbolName: "x")
            let info = CacheGroup(id: "i.info", title: "I", category: .container, symbolName: "x", detail: "info only")
            let scanner = GlobalCacheScanner(
                providers: [StubProvider(id: "1", groups: [small, empty]), StubProvider(id: "2", groups: [big, info])],
                context: context(home))
            let result = await scanner.scanCaches()
            #expect(result.map(\.id) == ["b", "s", "i.info"])
        }
    }

    @Test func allProvidersNeverTouchOutsideFakeHome() async throws {
        try await withTempDir { home in
            try write(100, to: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/X/f"))
            try write(100, to: home.appendingPathComponent(".npm/_cacache/f"))
            try write(100, to: home.appendingPathComponent("Library/Logs/DiagnosticReports/r.ips"))
            let groups = await GlobalCacheScanner(context: context(home)).scanCaches()
            #expect(!groups.isEmpty)
            assertContained(groups, in: home)
            #expect(groups.map(\.totalBytes) == groups.map(\.totalBytes).sorted(by: >))
        }
    }
}
