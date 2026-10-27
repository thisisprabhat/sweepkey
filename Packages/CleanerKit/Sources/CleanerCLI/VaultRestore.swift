import ArgumentParser
import CleanerKit
import Foundation

struct VaultRestore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore", abstract: "Restore files from a vault (folder, zip or dmg).")

    @Argument(help: "The vault folder, .zip or .dmg.")
    var vault: String

    @Option(name: .customLong("by-remote"), help: "Match repositories by git remote under this search root (repeatable).")
    var byRemote: [String] = []

    @Flag(help: "Overwrite files that already exist and differ.")
    var overwrite = false

    @Flag(name: .customLong("dry-run"), help: "Only print the plan.")
    var dryRun = false

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var yes = false

    func run() async throws {
        let url = resolvedURL(vault)
        var password: String?
        if url.pathExtension.lowercased() == "dmg" {
            guard let entered = readPassword("Vault password: "), !entered.isEmpty else {
                throw CLIError("A password is required to open an encrypted vault.")
            }
            password = entered
        }
        let restorer = VaultRestorer()
        let opened = try await restorer.open(url, password: password)
        do {
            try await restore(opened, with: restorer)
        } catch {
            await restorer.close(opened)
            throw error
        }
        await restorer.close(opened)
    }

    private func restore(_ opened: OpenedVault, with restorer: VaultRestorer) async throws {
        let strategy: RestoreStrategy = byRemote.isEmpty
            ? .originalPaths : .matchGitRemote(searchRoots: byRemote.map(resolvedURL))
        let actions = try await restorer.planRestore(opened, strategy: strategy)
        guard !actions.isEmpty else {
            print("Nothing to restore.")
            throw ExitCode(2)
        }

        print("Restore plan:")
        print(CLIFormatting.table(
            headers: ["File", "Destination", "State"],
            rows: actions.map { a in
                let state = !a.destinationExists ? "new" : (a.identical ? "identical" : (overwrite ? "overwrite" : "differs, skipped"))
                return [a.entry.vaultPath, a.destinationURL.path, state]
            }))
        if dryRun {
            print("\nDry run: nothing was restored.")
            return
        }
        if !yes {
            guard standardInputIsTTY else {
                printError("Refusing to restore without confirmation on a non-interactive terminal. Pass --yes.")
                throw ExitCode.failure
            }
            guard confirm("\nRestore \(actions.count) file(s) to the destinations above? [y/N]") else {
                print("Aborted.")
                throw ExitCode.failure
            }
        }
        let result = try await restorer.restore(actions, overwrite: overwrite)
        print("\nRestored \(result.restored.count), skipped \(result.skipped.count), failed \(result.failed.count).")
        for (path, reason) in result.failed.sorted(by: { $0.key < $1.key }) {
            printError("failed: \(path): \(reason)")
        }
        if !result.failed.isEmpty { throw ExitCode.failure }
    }
}
