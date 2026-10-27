import ArgumentParser
import CleanerKit

@main
struct Cleaner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleaner",
        abstract: "Clean regenerable developer artifacts and collect secrets into a vault.",
        discussion: "Exit codes: 0 ok, 1 error, 2 nothing to do.",
        version: CleanerVersion.current,
        subcommands: [
            ScanCommand.self, CleanCommand.self, CachesCommand.self, VaultCommand.self, HistoryCommand.self,
        ]
    )
}

