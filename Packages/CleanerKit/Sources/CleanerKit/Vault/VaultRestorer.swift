import Foundation

public struct VaultRestorer: VaultRestoring {
    private let shell: ShellRunning
    private let git: GitClient
    private let trash: @Sendable (URL) throws -> Void

    /// `trash` moves a file that a restore is about to overwrite out of the way (to the Trash by
    /// default), so an overwrite never destroys the only copy. Injectable for tests.
    public init(
        shell: ShellRunning = ProcessShellRunner(), git: GitClient = .init(),
        trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.shell = shell
        self.git = git
        self.trash = trash
    }

    private static let tempPrefix = "CleanerVaultOpen-"

    // MARK: - Open / close

    public func open(_ vaultURL: URL, password: String?) async throws -> OpenedVault {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: vaultURL.path, isDirectory: &isDir) else { throw VaultError.manifestMissing }

        if isDir.boolValue {
            return OpenedVault(manifest: try readManifest(in: vaultURL), root: vaultURL)
        }

        let temp = fm.temporaryDirectory.appendingPathComponent(Self.tempPrefix + UUID().uuidString, isDirectory: true)
        var mount: URL?
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if vaultURL.pathExtension.lowercased() == "dmg" {
                guard let password, !password.isEmpty else { throw VaultError.passwordRequired }
                let mountDir = temp.appendingPathComponent("mount", isDirectory: true)
                try fm.createDirectory(at: mountDir, withIntermediateDirectories: true)
                mount = mountDir
                let res = try await shell.run(
                    "/usr/bin/hdiutil",
                    arguments: ["attach", "-stdinpass", "-nobrowse", "-readonly", "-mountpoint", mountDir.path, vaultURL.path],
                    currentDirectory: nil, input: Data(password.utf8), timeout: .seconds(120))
                guard res.succeeded else {
                    mount = nil  // nothing attached
                    let err = res.stderr.lowercased()
                    if err.contains("authentication") || err.contains("passphrase") || err.contains("password") {
                        throw VaultError.wrongPassword
                    }
                    throw VaultError.commandFailed("hdiutil attach: " + res.stderr)
                }
                return OpenedVault(manifest: try readManifest(in: mountDir), root: mountDir, mountPoint: mountDir)
            }

            let res = try await shell.run(
                "/usr/bin/ditto", arguments: ["-x", "-k", vaultURL.path, temp.path],
                currentDirectory: nil, input: nil, timeout: .seconds(600))
            guard res.succeeded else { throw VaultError.commandFailed("ditto: " + res.stderr) }
            var root = temp
            if !fm.fileExists(atPath: temp.appendingPathComponent(VaultCoding.manifestName).path) {
                let subs = ((try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent != "__MACOSX" && $0.isDirectory }
                if let found = subs.first(where: {
                    fm.fileExists(atPath: $0.appendingPathComponent(VaultCoding.manifestName).path)
                }) { root = found }
            }
            return OpenedVault(manifest: try readManifest(in: root), root: root)
        } catch {
            if let mount {
                let r = try? await shell.run("/usr/bin/hdiutil", ["detach", mount.path])
                if r?.succeeded != true { _ = try? await shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
            }
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    public func close(_ vault: OpenedVault) async {
        let fm = FileManager.default
        if let mount = vault.mountPoint {
            let r = try? await shell.run("/usr/bin/hdiutil", ["detach", mount.path])
            if r?.succeeded != true {
                _ = try? await shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            }
        }
        var cur = vault.root
        while cur.path != "/" {
            if cur.lastPathComponent.hasPrefix(Self.tempPrefix) {
                try? fm.removeItem(at: cur)
                return
            }
            cur = cur.deletingLastPathComponent()
        }
    }

    private func readManifest(in dir: URL) throws -> VaultManifest {
        let url = dir.appendingPathComponent(VaultCoding.manifestName)
        guard let data = try? Data(contentsOf: url) else { throw VaultError.manifestMissing }
        do { return try VaultCoding.decoder().decode(VaultManifest.self, from: data) }
        catch { throw VaultError.manifestMissing }
    }

    // MARK: - Plan

    public func planRestore(_ vault: OpenedVault, strategy: RestoreStrategy) async throws -> [RestoreAction] {
        try await planRestoreWithWarnings(vault, strategy: strategy).actions
    }

    /// Like `planRestore`, and also explains entries that were left out.
    public func planRestoreWithWarnings(
        _ vault: OpenedVault, strategy: RestoreStrategy
    ) async throws -> (actions: [RestoreAction], warnings: [String]) {
        var actions: [RestoreAction] = []
        var warnings: [String] = []
        switch strategy {
        case .originalPaths:
            for e in vault.manifest.entries {
                // A tampered or corrupt manifest must not aim a restore at an unrelated path: the
                // source path has to end with the vault path minus its root folder.
                guard Self.sourceMatchesVaultPath(e) else {
                    warnings.append("Skipped \(e.vaultPath): its recorded source path \(e.sourcePath) does not match the vault path")
                    continue
                }
                actions.append(action(e, vault: vault, destination: URL(fileURLWithPath: e.sourcePath)))
            }
        case .matchGitRemote(let searchRoots):
            var byRemote: [String: URL] = [:]
            let repos = findRepositories(under: searchRoots)
                .sorted { ($0.path.count, $0.path) < ($1.path.count, $1.path) }
            for repo in repos {
                guard let remote = await git.info(forRepository: repo)?.remoteURL else { continue }
                let key = Self.normalizeRemote(remote)
                if byRemote[key] == nil { byRemote[key] = repo }
            }
            for e in vault.manifest.entries {
                guard let remote = e.gitRemoteURL, let rel = e.pathInRepository, VaultExporter.isSafe(rel),
                      let repo = byRemote[Self.normalizeRemote(remote)] else { continue }
                actions.append(action(e, vault: vault, destination: repo.appendingPathComponent(rel)))
            }
        }
        return (actions, warnings)
    }

    /// True when `sourcePath` is absolute, has no `..`, and ends with `vaultPath` minus its first
    /// component (`Projects/app/.env` needs a source ending in `/app/.env`).
    static func sourceMatchesVaultPath(_ e: VaultManifestEntry) -> Bool {
        guard VaultExporter.isSafe(e.vaultPath), e.sourcePath.hasPrefix("/") else { return false }
        let tail = e.vaultPath.split(separator: "/").dropFirst()
        let source = e.sourcePath.split(separator: "/")
        guard !tail.isEmpty, !source.contains(".."), source.count > tail.count else { return false }
        return Array(source.suffix(tail.count)) == Array(tail)
    }

    private func action(_ e: VaultManifestEntry, vault: OpenedVault, destination: URL) -> RestoreAction {
        let exists = (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil
        var identical = false
        if exists, !destination.isSymlink, let sha = try? VaultHashing.sha256(of: destination) {
            identical = sha == e.sha256
        }
        return RestoreAction(
            entry: e, vaultFileURL: vault.root.appendingPathComponent(e.vaultPath),
            destinationURL: destination, destinationExists: exists, identical: identical)
    }

    private func findRepositories(under roots: [URL]) -> [URL] {
        var repos: [URL] = []
        let fm = FileManager.default
        func walk(_ dir: URL) {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { repos.append(dir) }
            guard let items = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
            for item in items where !VaultArtifactDirs.names.contains(item.lastPathComponent) {
                guard let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      v.isDirectory == true, v.isSymbolicLink != true else { continue }
                walk(item)
            }
        }
        for r in roots { walk(r.standardizedFileURL) }
        return repos
    }

    /// Strips `.git`, converts `git@host:path` to `https://host/path`, lowercases the host.
    public static func normalizeRemote(_ remote: String) -> String {
        var s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }

        if !s.contains("://"), let colon = s.firstIndex(of: ":") {
            var host = String(s[..<colon])
            if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
            let path = s[s.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !host.isEmpty, !host.contains("/"), !path.isEmpty {
                return "https://\(host.lowercased())/\(path)"
            }
        }
        if let comps = URLComponents(string: s), let scheme = comps.scheme?.lowercased(), scheme != "file",
           let host = comps.host?.lowercased() {
            let path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let port = comps.port.flatMap { $0 == 22 ? nil : ":\($0)" } ?? ""
            return "https://\(host)\(port)/\(path)"
        }
        return s
    }

    // MARK: - Restore

    public func restore(_ actions: [RestoreAction], overwrite: Bool) async throws -> RestoreResult {
        var result = RestoreResult()
        let fm = FileManager.default
        for a in actions {
            let id = a.entry.vaultPath
            let dest = a.destinationURL
            if dest.isSymlink {
                result.failed[id] = "destination is a symbolic link"
                continue
            }
            if Self.hasSymlinkAncestor(dest) {
                result.failed[id] = "a parent directory of the destination is a symbolic link"
                continue
            }
            let type = (try? fm.attributesOfItem(atPath: dest.path))?[.type] as? FileAttributeType
            let exists = type != nil
            if exists, type != .typeRegular {
                result.failed[id] = "destination exists and is not a regular file"
                continue
            }
            if exists {
                if let sha = try? VaultHashing.sha256(of: dest), sha == a.entry.sha256 {
                    result.skipped.append(id)
                    continue
                }
                if !overwrite {
                    result.skipped.append(id)
                    continue
                }
            }
            let tmp = dest.deletingLastPathComponent()
                .appendingPathComponent(".\(dest.lastPathComponent).cleaner-tmp-\(UUID().uuidString)")
            do {
                guard VaultExporter.isSafe(id), !a.vaultFileURL.isSymlink,
                      try VaultHashing.sha256(of: a.vaultFileURL) == a.entry.sha256 else {
                    result.failed[id] = "vault copy is missing or does not match its recorded checksum"
                    continue
                }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if Self.hasSymlinkAncestor(dest) {
                    result.failed[id] = "a parent directory of the destination is a symbolic link"
                    continue
                }
                try fm.copyItem(at: a.vaultFileURL, to: tmp)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
                if exists {
                    // Keep the file being replaced: it goes to the Trash first. If that fails, the
                    // restore of this file fails and the original stays in place.
                    try trash(dest)
                }
                try fm.moveItem(at: tmp, to: dest)
                result.restored.append(id)
            } catch {
                try? fm.removeItem(at: tmp)
                result.failed[id] = error.localizedDescription
            }
        }
        return result
    }

    /// True if an existing ancestor directory (below the first path level, so /var, /tmp etc. are allowed)
    /// is a symbolic link.
    static func hasSymlinkAncestor(_ dest: URL) -> Bool {
        let comps = dest.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard comps.count > 2 else { return false }
        var path = "/" + comps[1]
        for c in comps.dropFirst(2) {
            path += "/" + c
            guard let t = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
            else { return false }
            if t == .typeSymbolicLink { return true }
        }
        return false
    }
}
