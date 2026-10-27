import ArgumentParser

struct VaultCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vault", abstract: "Collect secrets into a vault and restore them.",
        subcommands: [VaultCollect.self, VaultRestore.self])
}
