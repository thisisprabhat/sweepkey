import Foundation

public struct VaultExporter: VaultExporting {
    private let shell: ShellRunning
    private let now: @Sendable () -> Date

    public init(shell: ShellRunning = ProcessShellRunner(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.shell = shell
        self.now = now
    }

    public func export(_ request: VaultExportRequest) async throws -> VaultExportResult {
        switch request.format {
        case .folder:
            let r = try exportFolder(request.files, to: request.destination, keepVersions: request.keepVersions)
            return VaultExportResult(
                outputURL: request.destination, manifest: r.manifest,
                copiedCount: r.copied, unchangedCount: r.unchanged)

        case .zip:
            let (stagingParent, staging) = try makeStaging()
            defer { try? FileManager.default.removeItem(at: stagingParent) }
            let r = try exportFolder(request.files, to: staging, keepVersions: request.keepVersions)
            try prepareOutput(request.destination)
            let res = try await shell.run(
                "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, request.destination.path],
                currentDirectory: nil, input: nil, timeout: .seconds(600))
            guard res.succeeded else { throw VaultError.commandFailed("ditto: " + res.stderr) }
            return VaultExportResult(
                outputURL: request.destination, manifest: r.manifest, copiedCount: r.copied, unchangedCount: r.unchanged)

        case .encryptedImage:
            guard let password = request.password, !password.isEmpty else { throw VaultError.passwordRequired }
            let (stagingParent, staging) = try makeStaging()
            defer { try? FileManager.default.removeItem(at: stagingParent) }
            let r = try exportFolder(request.files, to: staging, keepVersions: request.keepVersions)
            try prepareOutput(request.destination)
            let res = try await shell.run(
                "/usr/bin/hdiutil",
                arguments: [
                    "create", "-srcfolder", staging.path, "-volname", "Cleaner Vault",
                    "-encryption", "AES-256", "-stdinpass", "-format", "UDZO", "-ov", request.destination.path,
                ],
                currentDirectory: nil, input: Data(password.utf8), timeout: .seconds(600))
            guard res.succeeded else { throw VaultError.commandFailed("hdiutil create: " + res.stderr) }
            return VaultExportResult(
                outputURL: request.destination, manifest: r.manifest, copiedCount: r.copied, unchangedCount: r.unchanged)
        }
    }

    // MARK: - Helpers

    private func makeStaging() throws -> (parent: URL, staging: URL) {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanerVaultStage-\(UUID().uuidString)", isDirectory: true)
        let staging = parent.appendingPathComponent("Cleaner Vault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return (parent, staging)
    }

    private func prepareOutput(_ destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
            try fm.removeItem(at: destination)
        }
    }

    private func makeDir(_ dir: URL) throws {
        let fm = FileManager.default
        var missing: [URL] = []
        var cur = dir
        while (try? fm.attributesOfItem(atPath: cur.path)) == nil, cur.path != "/" {
            missing.append(cur)
            cur = cur.deletingLastPathComponent()
        }
        for d in missing.reversed() {
            try fm.createDirectory(at: d, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
    }

    private func exportFolder(
        _ files: [SecretFile], to dest: URL, keepVersions: Int
    ) throws -> (manifest: VaultManifest, copied: Int, unchanged: Int) {
        let fm = FileManager.default
        try makeDir(dest)
        let date = now()
        let stamp = Self.timestamp(date)
        var copied = 0, unchanged = 0

        let manifestURL = dest.appendingPathComponent(VaultCoding.manifestName)
        var entries: [String: VaultManifestEntry] = [:]
        if let data = try? Data(contentsOf: manifestURL),
           let old = try? VaultCoding.decoder().decode(VaultManifest.self, from: data) {
            for e in old.entries { entries[e.vaultPath] = e }
        }

        for file in files {
            guard Self.isSafe(file.vaultPath) else { continue }
            let sha = try VaultHashing.sha256(of: file.sourceURL)
            let target = dest.appendingPathComponent(file.vaultPath)
            try makeDir(target.deletingLastPathComponent())

            let exists = (try? fm.attributesOfItem(atPath: target.path)) != nil
            if exists, (try? VaultHashing.sha256(of: target)) == sha {
                unchanged += 1
            } else {
                if exists {
                    let versionsDir = dest.appendingPathComponent(".versions")
                        .appendingPathComponent(file.vaultPath, isDirectory: true)
                    try makeDir(versionsDir)
                    var version = versionsDir.appendingPathComponent(stamp)
                    var n = 0
                    while (try? fm.attributesOfItem(atPath: version.path)) != nil {
                        n += 1
                        version = versionsDir.appendingPathComponent("\(stamp)-\(n)")
                    }
                    try fm.moveItem(at: target, to: version)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: version.path)
                    prune(versionsDir, keep: keepVersions)
                }
                try fm.copyItem(at: file.sourceURL, to: target)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                copied += 1
            }

            entries[file.vaultPath] = VaultManifestEntry(
                vaultPath: file.vaultPath, sourcePath: file.sourceURL.path, sha256: sha,
                sizeBytes: file.sizeBytes, modified: file.modified, collectedAt: date, reason: file.reason,
                gitRemoteURL: file.git?.remoteURL, gitBranch: file.git?.branch,
                gitHeadCommit: file.git?.headCommit, pathInRepository: file.pathInRepository)
        }

        let manifest = VaultManifest(
            createdAt: date, hostName: ProcessInfo.processInfo.hostName,
            entries: entries.values.sorted { $0.vaultPath < $1.vaultPath })
        try VaultCoding.encoder().encode(manifest).write(to: manifestURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)

        let marker = dest.appendingPathComponent(".metadata_never_index")
        if (try? fm.attributesOfItem(atPath: marker.path)) == nil {
            fm.createFile(atPath: marker.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        }
        return (manifest, copied, unchanged)
    }

    private func prune(_ versionsDir: URL, keep: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: versionsDir.path) else { return }
        let sorted = names.sorted()
        let excess = sorted.count - max(keep, 0)
        guard excess > 0 else { return }
        for name in sorted.prefix(excess) {
            try? fm.removeItem(at: versionsDir.appendingPathComponent(name))
        }
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Rejects absolute paths and parent traversal.
    static func isSafe(_ vaultPath: String) -> Bool {
        !vaultPath.hasPrefix("/") && !vaultPath.split(separator: "/").contains("..") && !vaultPath.isEmpty
    }
}
