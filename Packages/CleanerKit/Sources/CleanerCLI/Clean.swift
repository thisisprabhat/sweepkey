import ArgumentParser
import CleanerKit
import Foundation

struct CleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean", abstract: "Delete reclaimable project artifacts after safety checks.")

    @Argument(help: "Directories to scan (default: the scan roots from settings).")
    var paths: [String] = []

    @Flag(name: .customLong("dry-run"), help: "Show what would be deleted without deleting.")
    var dryRun = false

    @Flag(help: "Move items to the Trash instead of deleting permanently.")
    var trash = false

    @Flag(name: .customLong("stale-only"), help: "Only clean stale projects.")
    var staleOnly = false

    @Option(name: .customLong("rule"), help: "Only clean items from this rule id (repeatable).")
    var rules: [String] = []

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
        let settings = SettingsStore().load()
        let roots = try resolveRoots(paths, settings: settings)
        let projects = try await scanProjects(roots: roots, settings: settings, staleOnly: staleOnly)
        var candidates = projects.flatMap(\.candidates)
        if !rules.isEmpty {
            let wanted = Set(rules)
            candidates = candidates.filter { wanted.contains($0.ruleID) }
        }
        try await runCleanFlow(
            candidates: candidates, scanRoots: roots, settings: settings,
            dryRun: dryRun, trash: trash, yes: yes)
    }
}
