import ArgumentParser
import SweepkeyKit
import Foundation

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan", abstract: "Scan for reclaimable project artifacts.")

    @Argument(help: "Directories to scan (default: the scan roots from settings).")
    var paths: [String] = []

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    @Flag(name: .customLong("stale-only"), help: "Only show stale projects.")
    var staleOnly = false

    @Option(name: .customLong("min-size"), help: "Hide projects reclaiming less than this (e.g. 100MB).")
    var minSize: String?

    func run() async throws {
        var minBytes: Int64 = 0
        if let minSize {
            guard let parsed = CLIFormatting.parseSize(minSize) else {
                throw CLIError("Invalid size '\(minSize)'. Use e.g. 100MB or 1.5GB.")
            }
            minBytes = parsed
        }
        let settings = SettingsStore().load()
        let roots = try resolveRoots(paths, settings: settings)
        let projects = try await scanProjects(roots: roots, settings: settings, staleOnly: staleOnly)
            .filter { $0.reclaimableBytes >= minBytes }

        if json {
            print(try jsonString(projects))
            return
        }
        guard !projects.isEmpty else {
            print("Nothing to clean.")
            throw ExitCode(2)
        }
        let rows = projects.map { p in
            [
                p.name,
                p.ecosystemIDs.map { Ecosystem.named($0).name }.joined(separator: ", "),
                CLIFormatting.formatBytes(p.reclaimableBytes),
                CLIFormatting.formatAge(p.lastActivity) + (p.isStale ? " (stale)" : ""),
            ]
        }
        print(CLIFormatting.table(
            headers: ["Project", "Ecosystems", "Reclaimable", "Last activity"], rows: rows, rightAligned: [2]))
        let total = projects.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        print("\n\(projects.count) project(s), \(CLIFormatting.formatBytes(total)) reclaimable.")
    }
}
