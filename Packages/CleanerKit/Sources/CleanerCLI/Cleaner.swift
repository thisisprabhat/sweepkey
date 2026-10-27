import ArgumentParser

@main
struct Cleaner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleaner",
        abstract: "Clean regenerable developer artifacts and collect secrets into a vault.",
        discussion: "Exit codes: 0 ok, 1 error, 2 nothing to do.",
        version: "0.1.0",
        subcommands: [
            ScanCommand.self, CleanCommand.self, CachesCommand.self, VaultCommand.self, HistoryCommand.self,
        ]
    )
}

