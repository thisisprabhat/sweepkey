import ArgumentParser
import SweepkeyKit

@main
struct Sweepkey: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sweepkey",
        abstract: "Clean regenerable developer artifacts and collect secrets into a vault.",
        discussion: "Exit codes: 0 ok, 1 error, 2 nothing to do.",
        version: SweepkeyVersion.current,
        subcommands: [
            ScanCommand.self, CleanCommand.self, CachesCommand.self, VaultCommand.self, HistoryCommand.self,
        ]
    )
}

