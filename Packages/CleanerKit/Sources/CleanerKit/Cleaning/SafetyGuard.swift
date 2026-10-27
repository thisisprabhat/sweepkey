import Foundation

public struct SafetyGuard: SafetyEvaluating {
    private let git: GitClient
    private let tracked: GitTrackedCheck
    private let home: URL
    private let pinnedProjects: [URL]
    private let activeDirectories: @Sendable () async -> [URL]

    private static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Library", "/Applications"]

    public init(
        git: GitClient = .init(),
        gitShell: ShellRunning = ProcessShellRunner(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pinnedProjects: [URL] = [],
        activeDirectories: @escaping @Sendable () async -> [URL] = { [] }
    ) {
        self.git = git
        self.tracked = GitTrackedCheck(shell: gitShell)
        self.home = home
        self.pinnedProjects = pinnedProjects
        self.activeDirectories = activeDirectories
    }

    public func evaluate(_ candidates: [Candidate], scanRoots: [URL]) async -> [Candidate.ID: SafetyVerdict] {
        let active = await activeDirectories().map(Self.resolved)
        var result: [Candidate.ID: SafetyVerdict] = [:]
        for c in candidates {
            result[c.id] = await verdict(for: c, scanRoots: scanRoots, active: active)
        }
        return result
    }

    private static func resolved(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    private func isCommand(_ c: Candidate) -> Bool {
        if case .command = c.action { return true }
        return false
    }

    private func verdict(for c: Candidate, scanRoots: [URL], active: [URL]) async -> SafetyVerdict {
        let url = Self.resolved(c.url)
        let path = url.path
        let homeURL = Self.resolved(home)
        let roots = scanRoots.map(Self.resolved)
        // Path strings (no trailing slash, case-folded) so directory flags and case cannot defeat equality.
        let key = path.lowercased()
        let rootKeys = Set(roots.map { $0.path.lowercased() })
        let command = isCommand(c)

        // 1. Root, home, scan root, system prefix.
        if path == "/" || key == homeURL.path.lowercased() || rootKeys.contains(key) {
            return .blocked("Protected path")
        }
        for prefix in Self.systemPrefixes {
            let p = prefix.lowercased()
            guard key == p || key.hasPrefix(p + "/") else { continue }
            // Tool-managed locations under /usr/local are legitimate targets for commands.
            if command, prefix == "/usr", key == "/usr/local" || key.hasPrefix("/usr/local/") { continue }
            return .blocked("System path")
        }

        // 2. Symlinks.
        if c.url.isSymlink { return .blocked("Symlink") }

        // 3 & 4. Containment (delete actions only).
        if !command {
            switch c.kind {
            case .projectArtifact:
                if !roots.contains(where: { url.isDescendant(of: $0) }) {
                    return .blocked("Outside scan roots")
                }
            case .globalCache:
                if !url.isDescendant(of: homeURL) { return .blocked("Outside home directory") }
            }
        }

        // 5. Pinned.
        if let root = c.projectRoot {
            let r = Self.resolved(root)
            if pinnedProjects.contains(where: { Self.resolved($0) == r }) { return .blocked("Pinned project") }
        }

        // 6. Git-tracked files (project artifacts only).
        if c.kind == .projectArtifact, !command,
           let repo = await git.repositoryRoot(containing: c.url) {
            switch await tracked.status(of: c.url, repositoryRoot: repo) {
            case .tracked: return .blocked("Contains files tracked by git")
            case .error: return .blocked("Could not verify git status")
            case .untracked: break
            }
        }

        // 7. Danger.
        if c.risk == .danger { return .warning("High risk: \(c.title) may be hard to regenerate") }

        // 8. Active directories.
        if let root = c.projectRoot {
            let r = Self.resolved(root)
            if let dir = active.first(where: { $0 == r || $0.isDescendant(of: r) }) {
                return .warning("Project appears to be open in \(dir.path)")
            }
        }
        return .allowed
    }
}
