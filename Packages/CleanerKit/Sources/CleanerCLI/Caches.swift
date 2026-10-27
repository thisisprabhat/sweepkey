import ArgumentParser
import CleanerKit
import Foundation

struct CachesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "caches", abstract: "List and clean global tool caches.",
        subcommands: [List.self, Clean.self], defaultSubcommand: List.self)

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List cache groups.")

        @Flag(help: "Print JSON instead of a table.")
        var json = false

        func run() async throws {
            let groups = await GlobalCacheScanner().scanCaches()
                .filter { !$0.candidates.isEmpty }
                .sorted { $0.totalBytes > $1.totalBytes }
            if json {
                print(try jsonString(groups.map(GroupSummary.init)))
                return
            }
            guard !groups.isEmpty else {
                print("No caches found.")
                throw ExitCode(2)
            }
            print(CLIFormatting.table(
                headers: ["ID", "Cache", "Category", "Size"],
                rows: groups.map { [$0.id, $0.title, $0.category.displayName, CLIFormatting.formatBytes($0.totalBytes)] },
                rightAligned: [3]))
        }
    }

    struct Clean: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clean", abstract: "Clean the given cache groups (ids from `cleaner caches`).")

        @Argument(help: "Cache group ids.")
        var groupIDs: [String]

        @Flag(name: .customLong("dry-run"), help: "Show what would be deleted without deleting.")
        var dryRun = false

        @Flag(help: "Move items to the Trash instead of deleting permanently.")
        var trash = false

        @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
        var yes = false

        func run() async throws {
            guard !groupIDs.isEmpty else { throw CLIError("Give at least one cache group id.") }
            let groups = await GlobalCacheScanner().scanCaches()
            let known = Set(groups.map(\.id))
            let unknown = groupIDs.filter { !known.contains($0) }
            guard unknown.isEmpty else {
                throw CLIError("Unknown cache group id(s): \(unknown.joined(separator: ", "))")
            }
            let wanted = Set(groupIDs)
            let candidates = groups.filter { wanted.contains($0.id) }.flatMap(\.candidates)
            try await runCleanFlow(
                candidates: candidates, scanRoots: [], settings: SettingsStore().load(),
                dryRun: dryRun, trash: trash, yes: yes)
        }
    }
}

private struct GroupSummary: Encodable {
    var id: String
    var title: String
    var category: String
    var totalBytes: Int64
    var paths: [String]

    init(_ group: CacheGroup) {
        id = group.id
        title = group.title
        category = group.category.rawValue
        totalBytes = group.totalBytes
        paths = group.candidates.map(\.url.path)
    }
}
