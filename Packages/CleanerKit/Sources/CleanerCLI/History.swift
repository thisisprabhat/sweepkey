import ArgumentParser
import CleanerKit
import Foundation

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history", abstract: "Show past clean runs.")

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func run() async throws {
        let journal = JSONJournal()
        let reports = try await journal.reports()
        if json {
            print(try jsonString(reports))
            return
        }
        guard !reports.isEmpty else {
            print("No history yet.")
            throw ExitCode(2)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        print(CLIFormatting.table(
            headers: ["Date", "Mode", "Items", "Freed"],
            rows: reports.map {
                [
                    formatter.string(from: $0.startedAt),
                    $0.mode.rawValue + ($0.dryRun ? " (dry run)" : ""),
                    String($0.items.count),
                    CLIFormatting.formatBytes($0.freedBytes),
                ]
            },
            rightAligned: [2, 3]))
        print("\nLifetime freed: \(CLIFormatting.formatBytes(try await journal.lifetimeFreedBytes()))")
    }
}
