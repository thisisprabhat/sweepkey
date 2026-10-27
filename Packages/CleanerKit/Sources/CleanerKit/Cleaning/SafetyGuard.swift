import Foundation

public struct SafetyGuard: SafetyEvaluating {
    private let git: GitClient
    private let tracked: GitTrackedCheck
    private let home: URL
    private let pinnedProjects: [URL]
    private let activeDirectories: @Sendable () async -> [URL]

    private static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Library", "/Applications"]
    /// Candidates evaluated at once; each may run two git processes.
    static let maxConcurrency = 8

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
        guard !candidates.isEmpty else { return [:] }
        let active = await activeDirectories().map(Self.resolved)
        // Asked once per evaluation, so a missing Command Line Tools install neither pops the
        // installer per candidate nor slows every verdict.
        let gitAvailable = await git.isAvailable()
        var result: [Candidate.ID: SafetyVerdict] = [:]
        await withTaskGroup(of: (Candidate.ID, SafetyVerdict).self) { group in
            var next = 0
            func addNext() {
                guard next < candidates.count else { return }
                let c = candidates[next]
                next += 1
                group.addTask {
                    (c.id, await verdict(for: c, scanRoots: scanRoots, active: active, gitAvailable: gitAvailable))
                }
            }
            for _ in 0..<Self.maxConcurrency { addNext() }
            for await (id, verdict) in group {
                result[id] = verdict
                addNext()
            }
        }
        return result
    }

    private static func resolved(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    private func isCommand(_ c: Candidate) -> Bool {
        if case .command = c.action { return true }
        return false
    }

    /// True when `url` or one of its ancestors holds a `.git` entry (a directory, or the file a
    /// worktree or submodule uses).
    static func hasGitEntry(atOrAbove url: URL) -> Bool {
        let comps = url.standardizedFileURL.pathComponents
        for count in stride(from: comps.count, through: 1, by: -1) {
            let dir = NSString.path(withComponents: Array(comps.prefix(count)))
            let git = (dir as NSString).appendingPathComponent(".git")
            if (try? FileManager.default.attributesOfItem(atPath: git)) != nil { return true }
        }
        return false
    }

    private static func components(_ url: URL) -> [String] { url.pathComponents.map { $0.lowercased() } }

    /// Equal to, or inside, `ancestor` (resolved, case-insensitive path components).
    private static func isAtOrInside(_ url: URL, _ ancestor: URL) -> Bool {
        let a = components(ancestor), b = components(url)
        return b.count >= a.count && Array(b.prefix(a.count)) == a
    }

    private func verdict(for c: Candidate, scanRoots: [URL], active: [URL], gitAvailable: Bool) async -> SafetyVerdict {
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

        // 1b. Git metadata is never a cleaning target.
        if Self.components(url).contains(".git") || Self.components(c.url.standardizedFileURL).contains(".git") {
            return .blocked("Git metadata (.git)")
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

        // 5. Pinned: the project itself or anything nested in it (a pinned monorepo protects its packages).
        let pins = pinnedProjects.map(Self.resolved)
        if let root = c.projectRoot {
            let r = Self.resolved(root)
            if pins.contains(where: { Self.isAtOrInside(r, $0) }) { return .blocked("Pinned project") }
        }
        if c.kind == .projectArtifact, pins.contains(where: { Self.isAtOrInside(url, $0) }) {
            return .blocked("Pinned project")
        }

        // 6. Git-tracked files (project artifacts only). Fails closed: inside a repository (a
        // `.git` entry above the candidate), git must answer, or the candidate is blocked.
        if c.kind == .projectArtifact, !command {
            let inRepository = Self.hasGitEntry(atOrAbove: url)
            if gitAvailable, let repo = await git.repositoryRoot(containing: c.url) {
                switch await tracked.status(of: c.url, repositoryRoot: repo) {
                case .tracked: return .blocked("Contains files tracked by git")
                case .error: return .blocked("Could not verify git status")
                case .untracked: break
                }
            } else if inRepository {
                return .blocked("Could not verify git status")
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
