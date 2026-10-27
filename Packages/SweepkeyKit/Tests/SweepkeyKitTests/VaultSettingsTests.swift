import Foundation
import Testing
@testable import SweepkeyKit

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _options: [VaultCollectOptions] = []
    private var _requests: [VaultExportRequest] = []
    func add(_ o: VaultCollectOptions) { lock.withLock { _options.append(o) } }
    func add(_ r: VaultExportRequest) { lock.withLock { _requests.append(r) } }
    var options: [VaultCollectOptions] { lock.withLock { _options } }
    var requests: [VaultExportRequest] { lock.withLock { _requests } }
}

private struct Exporter: VaultExporting {
    var box: Box
    var fail = false
    func export(_ request: VaultExportRequest) async throws -> VaultExportResult {
        box.add(request)
        if fail { throw VaultError.commandFailed("disk full") }
        return VaultExportResult(
            outputURL: request.destination, manifest: VaultManifest(createdAt: Date(), hostName: "h", entries: []),
            copiedCount: request.files.count, unchangedCount: 0)
    }
}

private func artifact(_ project: URL, kind: CandidateKind = .projectArtifact) -> Candidate {
    let url = project.appendingPathComponent("node_modules")
    return Candidate(id: "r|\(url.path)", url: url, kind: kind, title: "node_modules", ecosystemID: "javascript",
                     ruleID: "r", risk: .safe, sizeBytes: 1, projectRoot: kind == .projectArtifact ? project : nil)
}

@Suite struct VaultSettingsTests {
    @Test func collectOptionsComeFromSettings() {
        var settings = SweepkeySettings()
        settings.scanRoots = [URL(fileURLWithPath: "/r/one"), URL(fileURLWithPath: "/r/two")]
        settings.excludedPaths = [URL(fileURLWithPath: "/r/one/skip")]
        settings.vault.extraPatterns = ["*.secret"]
        settings.vault.alwaysCollect = ["Podfile"]
        settings.vault.includeUncommittedWork = true
        settings.vault.scanContents = true
        let o = settings.vaultCollectOptions()
        #expect(o.roots.map(\.path) == ["/r/one", "/r/two"])
        #expect(o.excludedPaths.map(\.path) == ["/r/one/skip"])
        #expect(o.extraPatterns == ["*.secret"] && o.alwaysCollect == ["Podfile"])
        #expect(o.includeUncommittedWork && o.scanContents)
        #expect(settings.vaultCollectOptions(roots: [URL(fileURLWithPath: "/p")]).roots.map(\.path) == ["/p"])
    }

    @Test func overridesLayerOnTopOfSettings() {
        var settings = SweepkeySettings()
        // First launch: no roots yet. Settings added later must show through.
        var overrides = VaultCollectOverrides()
        #expect(overrides.applied(to: settings).roots.isEmpty)
        settings.scanRoots = [URL(fileURLWithPath: "/r/one")]
        settings.vault.scanContents = true
        #expect(overrides.applied(to: settings).roots.map(\.path) == ["/r/one"])
        #expect(overrides.applied(to: settings).scanContents)
        overrides.includeUncommittedWork = true
        overrides.scanContents = false
        let o = overrides.applied(to: settings)
        #expect(o.includeUncommittedWork && !o.scanContents)
        // A later settings change to a field that is not overridden still shows through.
        settings.vault.alwaysCollect = ["Gemfile"]
        #expect(overrides.applied(to: settings).alwaysCollect == ["Gemfile"])
        #expect(!overrides.isEmpty && VaultCollectOverrides().isEmpty)
    }

    @Test func requiredOnlyForRealRunsWithoutBypass() {
        var settings = SweepkeySettings()
        #expect(!VaultBeforeClean.isRequired(settings: settings, dryRun: false, skip: false))
        settings.requireVaultBeforeClean = true
        #expect(VaultBeforeClean.isRequired(settings: settings, dryRun: false, skip: false))
        #expect(!VaultBeforeClean.isRequired(settings: settings, dryRun: true, skip: false))
        #expect(!VaultBeforeClean.isRequired(settings: settings, dryRun: false, skip: true))
    }

    @Test func exportsAffectedProjectsWithSettingsAndRootLayout() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let app = root.appendingPathComponent("app")
            let other = root.appendingPathComponent("other")
            try writeText("A=1", to: app.appendingPathComponent(".env"))
            try writeText("B=1", to: other.appendingPathComponent(".env"))
            var settings = SweepkeySettings()
            settings.scanRoots = [root]
            settings.vault.destination = dir.appendingPathComponent("vault")
            settings.vault.keepVersions = 9
            settings.vault.alwaysCollect = ["Podfile"]
            let box = Box()
            let finder = SecretFinder(git: GitClient(shell: NoGitShell()))
            let outcome = try await VaultBeforeClean.run(
                candidates: [artifact(app), artifact(app), artifact(dir.appendingPathComponent("h"), kind: .globalCache)],
                settings: settings,
                collect: { options in box.add(options); return try await finder.findSecretsWithWarnings(options) },
                exporter: Exporter(box: box))
            #expect(box.options.count == 1)
            #expect(box.options[0].roots == [app.standardizedFileURL.resolvingSymlinksInPath()])
            #expect(box.options[0].alwaysCollect == ["Podfile"])
            let request = try #require(box.requests.first)
            #expect(request.format == .folder && request.keepVersions == 9)
            #expect(request.destination.lastPathComponent == "vault")
            // Same layout a full collection of the scan root produces; the other project is untouched.
            #expect(request.files.map(\.vaultPath) == ["Projects/app/.env"])
            #expect(outcome.result != nil)
        }
    }

    @Test func nothingToDoForCachesAndFailurePropagates() async throws {
        try await withTempDir { dir in
            let box = Box()
            var settings = SweepkeySettings()
            settings.vault.destination = dir.appendingPathComponent("vault")
            let none = try await VaultBeforeClean.run(
                candidates: [artifact(dir, kind: .globalCache)], settings: settings,
                collect: { _ in Issue.record("must not collect"); return ([], []) }, exporter: Exporter(box: box))
            #expect(none.result == nil && box.requests.isEmpty)

            let app = dir.appendingPathComponent("Projects/app")
            try writeText("A=1", to: app.appendingPathComponent(".env"))
            settings.scanRoots = [dir.appendingPathComponent("Projects")]
            let finder = SecretFinder(git: GitClient(shell: NoGitShell()))
            await #expect(throws: VaultError.self) {
                _ = try await VaultBeforeClean.run(
                    candidates: [artifact(app)], settings: settings,
                    collect: { try await finder.findSecretsWithWarnings($0) },
                    exporter: Exporter(box: box, fail: true))
            }
        }
    }
}
