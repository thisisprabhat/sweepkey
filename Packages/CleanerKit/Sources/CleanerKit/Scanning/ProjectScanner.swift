import Foundation

public struct ProjectScanner: ProjectScanning {
    private let sizer: SizeCalculator
    private let git: GitClient
    private let rules: [Rule]?
    private let now: @Sendable () -> Date
    private let home: URL

    /// - Parameters:
    ///   - rules: base rule set; `nil` loads the bundled rules. Overrides and custom rules from
    ///     `ScanOptions` are applied on top.
    ///   - home: the user's home directory (its direct `Library` child is skipped). Injectable for tests.
    public init(
        sizer: SizeCalculator = .init(), git: GitClient = .init(), rules: [Rule]? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.sizer = sizer
        self.git = git
        self.rules = rules
        self.now = now
        self.home = home
    }

    public func scan(_ options: ScanOptions) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(options, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    private struct WalkContext: Sendable {
        /// Rules that are switched off; their targets are neither reported nor descended into.
        var disabled: [Rule] = []
        var excluded: [String]
        var libraryPaths: Set<String>
    }

    private struct WalkResult: Sendable {
        var directory: URL
        var childDirs: [URL]
        var matches: [RuleMatch]
        var ignorePatterns: [String]
        var suppressed: [URL]
    }

    private struct Draft: Sendable {
        var directory: URL
        var targets: [(rule: Rule, url: URL)]
        var markers: [URL]
        var ecosystemIDs: [String]
    }

    private enum Output: Sendable {
        case walked(WalkResult)
        case done(Project)
    }

    private actor GitCache {
        private var tasks: [String: Task<GitInfo?, Never>] = [:]

        private static func normalized(_ path: String) -> String {
            path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        }

        /// A known repository root containing `dir`, unless a nested `.git` sits in between.
        private func knownRoot(for dir: URL) -> String? {
            var current = dir
            while true {
                let key = Self.normalized(current.path)
                if tasks[key] != nil { return key }
                if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) { return nil }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path || parent.path.isEmpty { return nil }
                current = parent
            }
        }

        func info(forProject dir: URL, git: GitClient) async -> GitInfo? {
            if let key = knownRoot(for: dir), let existing = tasks[key] { return await existing.value }
            guard let root = await git.repositoryRoot(containing: dir) else { return nil }
            let key = Self.normalized(root.path)
            if let existing = tasks[key] { return await existing.value }
            let task = Task { await git.info(forRepository: root) }
            tasks[key] = task
            return await task.value
        }
    }

    /// Equivalent spellings of a path (as given, symlink-resolved, and with the /private prefix macOS hides).
    private static func pathForms(_ url: URL) -> [String] {
        let plain = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        var forms = [plain, resolved]
        for p in ["/var/", "/tmp/", "/etc/"] where resolved.hasPrefix(p) { forms.append("/private" + resolved) }
        return Array(Set(forms))
    }

    private static func isExcluded(_ path: String, _ excluded: [String]) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func walk(_ dir: URL, rules: [Rule], context: WalkContext) -> WalkResult {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])) ?? []
        var names: [String] = []
        var childDirs: [URL] = []
        for entry in entries {
            let name = entry.lastPathComponent
            names.append(name)
            let v = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isSymbolicLink != true, v?.isDirectory == true else { continue }
            if name == ".git" || name == ".Trash" || name == "node_modules" { continue }
            // Build children from the caller's own prefix so paths are stable (no /private/var rewriting).
            let child = dir.appendingPathComponent(name, isDirectory: false)
            if context.libraryPaths.contains(child.path) { continue }
            if isExcluded(child.path, context.excluded) { continue }
            childDirs.append(child)
        }
        let matches = RuleMatcher.matches(in: dir, childNames: names, rules: rules)
        let suppressed = context.disabled.isEmpty ? [] :
            RuleMatcher.matches(in: dir, childNames: names, rules: context.disabled).flatMap(\.targets)
        var patterns: [String] = []
        if !matches.isEmpty, names.contains(".cleanerignore"),
           let text = try? String(contentsOf: dir.appendingPathComponent(".cleanerignore"), encoding: .utf8) {
            patterns = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .map { p in
                    var s = p
                    if s.hasPrefix("./") { s.removeFirst(2) }
                    while s.count > 1, s.hasSuffix("/") { s.removeLast() }
                    return s
                }
        }
        return WalkResult(directory: dir, childDirs: childDirs, matches: matches, ignorePatterns: patterns, suppressed: suppressed)
    }

    private static func isIgnored(relative: String, patterns: [String]) -> Bool {
        let last = relative.split(separator: "/").last.map(String.init) ?? relative
        return patterns.contains { Glob.matches($0, relative) || Glob.matches($0, last) }
    }

    private func finish(_ draft: Draft, options: ScanOptions, gitCache: GitCache) async -> Project {
        let sizes = await sizer.allocatedSizes(of: draft.targets.map(\.url), maxConcurrency: 4)
        let candidates = draft.targets.map { t in
            Candidate(
                id: "\(t.rule.id)|\(t.url.path)", url: t.url, kind: .projectArtifact,
                title: t.url.lastPathComponent, ecosystemID: t.rule.ecosystemID, ruleID: t.rule.id,
                risk: t.rule.risk, sizeBytes: sizes[t.url] ?? 0, lastModified: modificationDate(t.url),
                projectRoot: draft.directory, regenerateHint: t.rule.regenerate, note: t.rule.note)
        }
        var gitInfo: GitInfo?
        if options.includeGitInfo {
            gitInfo = await gitCache.info(forProject: draft.directory, git: git)
        }
        let dates = draft.markers.compactMap(modificationDate) + [gitInfo?.lastCommitDate].compactMap { $0 }
        let lastActivity = dates.max()
        let cutoff = now().addingTimeInterval(-Double(options.staleAfterDays) * 86_400)
        return Project(
            url: draft.directory, name: draft.directory.lastPathComponent,
            ecosystemIDs: draft.ecosystemIDs, candidates: candidates, git: gitInfo,
            lastActivity: lastActivity, isStale: lastActivity.map { $0 < cutoff } ?? false)
    }

    private func run(
        _ options: ScanOptions, _ continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) async throws {
        let startedAt = now()
        let base = try rules ?? RuleSet.bundled()
        let active = RuleSet(rules: base).effectiveRules(
            overrides: options.ruleOverrides, custom: options.customRules)
        let activeIDs = Set(active.map(\.id))
        let context = WalkContext(
            disabled: (base + options.customRules).filter { !activeIDs.contains($0.id) },
            excluded: options.excludedPaths.flatMap { Self.pathForms($0) },
            libraryPaths: Set(Self.pathForms(home.appendingPathComponent("Library"))))
        let limit = max(1, options.maxConcurrency)
        let gitCache = GitCache()

        var queue: [URL] = options.roots.map { URL(fileURLWithPath: $0.standardizedFileURL.path, isDirectory: false) }
            .filter { $0.isDirectory && !Self.isExcluded($0.path, context.excluded) }
        var queueIndex = 0
        var drafts: [Draft] = []
        var claimed = Set<String>()
        var running = 0
        var visited = 0
        var projectsFound = 0
        var candidateCount = 0
        var bytesFound: Int64 = 0
        var lastProgress = Date.distantPast
        var dirsSinceProgress = 0

        try await withThrowingTaskGroup(of: Output.self) { group in
            while true {
                try Task.checkCancellation()
                while running < limit {
                    if let draft = drafts.popLast() {
                        group.addTask { .done(await finish(draft, options: options, gitCache: gitCache)) }
                    } else if queueIndex < queue.count {
                        let dir = queue[queueIndex]
                        queueIndex += 1
                        group.addTask { .walked(Self.walk(dir, rules: active, context: context)) }
                    } else {
                        break
                    }
                    running += 1
                }
                guard running > 0, let output = try await group.next() else { break }
                running -= 1

                switch output {
                case .walked(let result):
                    visited += 1
                    dirsSinceProgress += 1
                    var noDescend = Set(result.suppressed.map(\.path))
                    var targets: [(rule: Rule, url: URL)] = []
                    var markers: [URL] = []
                    var ecosystems: [String] = []
                    let wholeIgnored = result.ignorePatterns.contains("*")
                    let dirPrefix = result.directory.path + "/"
                    for match in result.matches {
                        var contributed = false
                        for target in match.targets {
                            noDescend.insert(target.path)
                            if wholeIgnored || claimed.contains(target.path) { continue }
                            let rel = target.path.hasPrefix(dirPrefix) ? String(target.path.dropFirst(dirPrefix.count)) : target.lastPathComponent
                            if Self.isIgnored(relative: rel, patterns: result.ignorePatterns) { continue }
                            claimed.insert(target.path)
                            targets.append((match.rule, target))
                            contributed = true
                        }
                        if contributed {
                            markers.append(contentsOf: match.markers)
                            if !ecosystems.contains(match.rule.ecosystemID) { ecosystems.append(match.rule.ecosystemID) }
                        }
                    }
                    for child in result.childDirs where !noDescend.contains(child.path) && !claimed.contains(child.path) {
                        queue.append(child)
                    }
                    if !targets.isEmpty {
                        drafts.append(Draft(directory: result.directory, targets: targets, markers: markers, ecosystemIDs: ecosystems))
                    }
                    let nowDate = Date()
                    if dirsSinceProgress >= 500 || nowDate.timeIntervalSince(lastProgress) >= 0.1 {
                        lastProgress = nowDate
                        dirsSinceProgress = 0
                        continuation.yield(.progress(ScanProgress(
                            directoriesVisited: visited, currentPath: result.directory.path,
                            projectsFound: projectsFound, bytesFound: bytesFound)))
                    }
                case .done(let project):
                    projectsFound += 1
                    candidateCount += project.candidates.count
                    bytesFound += project.reclaimableBytes
                    continuation.yield(.project(project))
                }
            }
        }

        try Task.checkCancellation()
        continuation.yield(.finished(ScanSummary(
            projectCount: projectsFound, candidateCount: candidateCount, totalBytes: bytesFound,
            startedAt: startedAt, finishedAt: now())))
    }
}
