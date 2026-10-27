import ArgumentParser
import SweepkeyKit
import Foundation

enum VaultFormatArgument: String, ExpressibleByArgument, CaseIterable {
    case folder, zip, dmg

    var format: VaultExportFormat {
        switch self {
        case .folder: .folder
        case .zip: .zip
        case .dmg: .encryptedImage
        }
    }

    init(_ format: VaultExportFormat) {
        switch format {
        case .folder: self = .folder
        case .zip: self = .zip
        case .encryptedImage: self = .dmg
        }
    }
}

struct VaultCollect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collect", abstract: "Copy secret files (.env, keys, ...) from project trees into a vault.")

    @Argument(help: "Directories to search.")
    var paths: [String]

    @Option(help: "Destination: a directory for 'folder'; the output file (or a directory to put it in) for zip/dmg.")
    var to: String?

    @Option(help: "Vault format: folder, zip or dmg (encrypted).")
    var format: VaultFormatArgument?

    @Flag(help: "Also collect uncommitted work.")
    var uncommitted = false

    @Flag(name: .customLong("scan-contents"), help: "Also scan file contents for secrets.")
    var scanContents = false

    func run() async throws {
        let settings = SettingsStore().load()
        guard !paths.isEmpty else { throw CLIError("Give at least one path to search.") }
        let roots = try resolveRoots(paths, settings: settings)
        guard let rawDest = to.map(resolvedURL) ?? settings.vault.destination.map(resolvedURL) else {
            throw CLIError("Missing --to <destination> (and no vault destination in settings).")
        }
        let chosen = format ?? VaultFormatArgument(settings.vault.defaultFormat)

        let options = VaultCollectOptions(
            roots: roots,
            excludedPaths: settings.excludedPaths.map(resolvedURL),
            extraPatterns: settings.vault.extraPatterns,
            alwaysCollect: settings.vault.alwaysCollect,
            includeUncommittedWork: uncommitted || settings.vault.includeUncommittedWork,
            scanContents: scanContents || settings.vault.scanContents)
        let found = try await SecretFinder().findSecretsWithWarnings(options)
        for warning in found.warnings { printError("warning: \(warning)") }
        guard !found.files.isEmpty else {
            print("No secret files found.")
            throw ExitCode(2)
        }

        let destination = Self.outputURL(for: rawDest, format: chosen)
        var password: String?
        if chosen == .dmg {
            guard let first = readPassword("Vault password: "), !first.isEmpty else {
                throw CLIError("A password is required for an encrypted vault.")
            }
            guard readPassword("Confirm password: ") == first else {
                throw CLIError("Passwords do not match.")
            }
            password = first
        }

        print(CLIFormatting.table(
            headers: ["File", "Why", "Size"],
            rows: found.files.map { [$0.vaultPath, $0.reason.rawValue, CLIFormatting.formatBytes($0.sizeBytes)] },
            rightAligned: [2]))
        let result = try await VaultExporter().export(VaultExportRequest(
            files: found.files, destination: destination, format: chosen.format,
            password: password, keepVersions: settings.vault.keepVersions))
        print("\nVault written to \(result.outputURL.path): "
            + "\(result.copiedCount) copied, \(result.unchangedCount) unchanged.")
    }

    /// Folder vaults use `--to` as-is. For zip/dmg a directory gets a timestamped file name inside it.
    static func outputURL(for dest: URL, format: VaultFormatArgument, now: Date = Date()) -> URL {
        guard format != .folder else { return dest }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir), isDir.boolValue else {
            return dest
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "Sweepkey-Vault-\(formatter.string(from: now)).\(format == .zip ? "zip" : "dmg")"
        return dest.appendingPathComponent(name)
    }
}
