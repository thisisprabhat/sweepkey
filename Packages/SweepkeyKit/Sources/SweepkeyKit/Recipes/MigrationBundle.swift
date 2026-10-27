import Foundation

public struct RepoEntry: Codable, Hashable, Sendable {
    /// Original absolute path.
    public var path: String
    /// "<root name>/<path relative to root>", where the repo is cloned relative to the target base.
    public var relativePath: String
    public var remote: String?
    public var branch: String?

    public init(path: String, relativePath: String, remote: String?, branch: String?) {
        self.path = path
        self.relativePath = relativePath
        self.remote = remote
        self.branch = branch
    }
}

public struct MigrationResult: Sendable {
    public var directory: URL
    public var reposURL: URL
    public var scriptURL: URL
    public var vaultURL: URL
    public var repos: [RepoEntry]
    public var vault: VaultExportResult?
}

public enum MigrationBundle {
    /// Finds git repositories under `roots` (does not descend into repos or dependency folders).
    public static func discoverRepos(roots: [URL], maxDepth: Int = 6) -> [(root: URL, repo: URL)] {
        let skip: Set<String> = ["node_modules", ".build", "Pods", "venv", ".venv", "target", "DerivedData"]
        var found: [(URL, URL)] = []
        let fm = FileManager.default
        func walk(_ dir: URL, root: URL, depth: Int) {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                found.append((root, dir))
                return
            }
            guard depth < maxDepth, let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            // Children are built from `dir` so paths keep the caller's spelling (no /private rewrite).
            for name in names.sorted() where !skip.contains(name) {
                let kid = dir.appendingPathComponent(name, isDirectory: true)
                let v = try? kid.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard v?.isDirectory == true, v?.isSymbolicLink != true else { continue }
                walk(kid, root: root, depth: depth + 1)
            }
        }
        for root in roots { walk(root, root: root, depth: 0) }
        return found.map { (root: $0.0, repo: $0.1) }
    }

    public static func entry(for info: GitInfo, root: URL) -> RepoEntry {
        let rootComps = root.standardizedFileURL.pathComponents
        let comps = info.repositoryRoot.standardizedFileURL.pathComponents
        let tail = comps.count > rootComps.count && Array(comps.prefix(rootComps.count)) == rootComps
            ? Array(comps.dropFirst(rootComps.count)) : [info.repositoryRoot.lastPathComponent]
        return RepoEntry(
            path: info.repositoryRoot.path,
            relativePath: ([root.lastPathComponent] + tail).joined(separator: "/"),
            remote: info.remoteURL, branch: info.branch)
    }

    /// Writes `repos.json`, `restore.sh` and a folder vault export into `directory`.
    /// `collect` carries the user's vault settings; its roots are always replaced by `roots`.
    public static func export(
        roots: [URL], to directory: URL, secrets: any SecretFinding, exporter: any VaultExporting,
        git: GitClient = GitClient(), collect: VaultCollectOptions? = nil, keepVersions: Int = 5
    ) async throws -> MigrationResult {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var entries: [RepoEntry] = []
        for (root, repo) in discoverRepos(roots: roots) {
            guard var info = await git.info(forRepository: repo) else { continue }
            info.repositoryRoot = repo  // keep the discovered path (git reports a symlink-resolved one)
            entries.append(entry(for: info, root: root))
        }
        let reposURL = directory.appendingPathComponent("repos.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: reposURL, options: .atomic)

        let scriptURL = directory.appendingPathComponent("restore.sh")
        try Data(cloneScript(repos: entries).utf8).write(to: scriptURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let vaultURL = directory.appendingPathComponent("vault", isDirectory: true)
        var options = collect ?? VaultCollectOptions(roots: roots)
        options.roots = roots
        let files = try await secrets.findSecrets(options)
        let vault = files.isEmpty ? nil : try await exporter.export(
            VaultExportRequest(files: files, destination: vaultURL, format: .folder, keepVersions: keepVersions))
        return MigrationResult(
            directory: directory, reposURL: reposURL, scriptURL: scriptURL, vaultURL: vaultURL,
            repos: entries, vault: vault)
    }

    /// POSIX single-quoting: wrap in '...' and turn each embedded ' into '\''.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A `restore.sh` that clones each repo under `$1` (default `$HOME`) at its relative path.
    /// Existing targets are skipped; the script never deletes anything.
    public static func cloneScript(repos: [RepoEntry]) -> String {
        var lines = [
            "#!/bin/bash",
            "set -euo pipefail",
            "export GIT_ALLOW_PROTOCOL=https:ssh:git:file",
            "BASE=\"${1:-$HOME}\"",
            "status=0",
            "",
        ]
        for repo in repos {
            let comps = repo.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard let remote = repo.remote, !remote.isEmpty, !remote.hasPrefix("-"),
                  !repo.relativePath.hasPrefix("/"), !comps.contains(".."), !comps.contains("") else { continue }
            let target = "\"$BASE\"/" + shellQuote(repo.relativePath)
            lines.append("if [ -e \(target) ]; then")
            lines.append("  printf 'skip (exists): %s\\n' \(shellQuote(repo.relativePath))")
            lines.append("else")
            lines.append("  mkdir -p -- \"$(dirname -- \(target))\"")
            var clone = "git clone -- \(shellQuote(remote)) \(target)"
            if let branch = repo.branch, !branch.isEmpty, !branch.hasPrefix("-") {
                clone += " && git -C \(target) checkout \(shellQuote(branch)) --"
            }
            lines.append("  if ! { \(clone); }; then")
            lines.append("    printf 'FAILED: %s\\n' \(shellQuote(repo.relativePath)) >&2")
            lines.append("    status=1")
            lines.append("  fi")
            lines.append("fi")
        }
        lines.append("")
        lines.append("echo 'Done. Now restore the vault by git remote.'")
        lines.append("exit \"$status\"")
        return lines.joined(separator: "\n") + "\n"
    }
}
