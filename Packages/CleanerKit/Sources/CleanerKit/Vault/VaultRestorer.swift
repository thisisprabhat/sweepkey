import Foundation

public struct VaultRestorer: VaultRestoring {
    private let shell: ShellRunning
    private let git: GitClient

    public init(shell: ShellRunning = ProcessShellRunner(), git: GitClient = .init()) {
        self.shell = shell
        self.git = git
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
        try fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        if vaultURL.pathExtension.lowercased() == "dmg" {
            guard let password, !password.isEmpty else {
                try? fm.removeItem(at: temp)
                throw VaultError.passwordRequired
            }
            let mount = temp.appendingPathComponent("mount", isDirectory: true)
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            let res = try await shell.run(
                "/usr/bin/hdiutil",
                arguments: ["attach", "-stdinpass", "-nobrowse", "-readonly", "-mountpoint", mount.path, vaultURL.path],
                currentDirectory: nil, input: Data(password.utf8), timeout: .seconds(120))
            guard res.succeeded else {
                try? fm.removeItem(at: temp)
                let err = res.stderr.lowercased()
                if err.contains("authentication") || err.contains("passphrase") || err.contains("password") {
                    throw VaultError.wrongPassword
                }
                throw VaultError.commandFailed("hdiutil attach: " + res.stderr)
            }
            do {
                return OpenedVault(manifest: try readManifest(in: mount), root: mount, mountPoint: mount)
            } catch {
                _ = try? await shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
                try? fm.removeItem(at: temp)
                throw error
            }
        }

        // zip
        let res = try await shell.run(
            "/usr/bin/ditto", arguments: ["-x", "-k", vaultURL.path, temp.path],
            currentDirectory: nil, input: nil, timeout: .seconds(600))
        guard res.succeeded else {
            try? fm.removeItem(at: temp)
            throw VaultError.commandFailed("ditto: " + res.stderr)
        }
        do {
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
        var actions: [RestoreAction] = []
        switch strategy {
        case .originalPaths:
            for e in vault.manifest.entries {
                actions.append(action(e, vault: vault, destination: URL(fileURLWithPath: e.sourcePath)))
            }
        case .matchGitRemote(let searchRoots):
            var byRemote: [String: URL] = [:]
            for repo in findRepositories(under: searchRoots) {
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
        return actions
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

        if !s.contains("://"), let at = s.firstIndex(of: "@"), let colon = s[at...].firstIndex(of: ":") {
            let host = s[s.index(after: at)..<colon].lowercased()
            let path = s[s.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "https://\(host)/\(path)"
        }
        if let comps = URLComponents(string: s), let scheme = comps.scheme?.lowercased(), scheme != "file",
           let host = comps.host?.lowercased() {
            let path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "https://\(host)\(comps.port.map { ":\($0)" } ?? "")/\(path)"
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
            let exists = (try? fm.attributesOfItem(atPath: dest.path)) != nil
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
            do {
                guard VaultExporter.isSafe(id), !a.vaultFileURL.isSymlink,
                      try VaultHashing.sha256(of: a.vaultFileURL) == a.entry.sha256 else {
                    result.failed[id] = "vault copy is missing or does not match its recorded checksum"
                    continue
                }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if exists { try fm.removeItem(at: dest) }
                try fm.copyItem(at: a.vaultFileURL, to: dest)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
                result.restored.append(id)
            } catch {
                result.failed[id] = error.localizedDescription
            }
        }
        return result
    }
}
