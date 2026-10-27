import Foundation

public struct SecretFinder: SecretFinding {
    private let git: GitClient
    private let scanner = ContentScanner()

    public init(git: GitClient = .init()) {
        self.git = git
    }

    private struct Hit {
        var url: URL
        var reason: SecretReason
        var rule: String
        var repo: URL?
    }

    public func findSecrets(_ options: VaultCollectOptions) async throws -> [SecretFile] {
        let gitAvailable = await git.isAvailable()
        let excluded = options.excludedPaths.map { $0.standardizedFileURL }
        var results: [SecretFile] = []
        var seen = Set<String>()

        for rawRoot in options.roots {
            let root = rawRoot.standardizedFileURL
            var hits: [Hit] = []
            var repos: [URL] = []
            var repoInfo: [String: GitInfo?] = [:]

            var ambient: URL?
            if gitAvailable, !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path),
               let r = await git.repositoryRoot(containing: root) {
                ambient = r.standardizedFileURL
            }
            var walked: [(url: URL, repo: URL?)] = []
            walk(root, repo: ambient, repos: &repos, excluded: excluded, into: &walked, gitAvailable: gitAvailable)
            if let ambient { repos.append(ambient) }

            let always = options.alwaysCollect
            for (url, repo) in walked {
                let name = url.lastPathComponent
                if let r = always.first(where: { Glob.matches($0, name) }) {
                    hits.append(Hit(url: url, reason: .alwaysCollect, rule: r, repo: repo))
                } else if repo == nil,
                          let p = SecretPatterns.firstMatch(
                            relativePath: relative(url, to: root), extra: options.extraPatterns) {
                    hits.append(Hit(url: url, reason: .patternMatch, rule: p, repo: nil))
                }
            }

            for repo in repos {
                let ignored = (try? await git.ignoredPaths(repositoryRoot: repo)) ?? []
                let untracked = (try? await git.untrackedPaths(repositoryRoot: repo)) ?? []
                var ignoredFiles: [URL] = []
                for entry in ignored {
                    let isDirEntry = entry.hasSuffix("/")
                    let rel = isDirEntry ? String(entry.dropLast()) : entry
                    if VaultArtifactDirs.containsArtifact(rel) { continue }
                    let url = repo.appendingPathComponent(rel)
                    if isDirEntry {
                        var sub: [(url: URL, repo: URL?)] = []
                        var none: [URL] = []
                        walk(url, repo: nil, repos: &none, excluded: excluded, into: &sub, gitAvailable: false)
                        ignoredFiles += sub.map(\.url)
                    } else {
                        ignoredFiles.append(url)
                    }
                }
                let untrackedFiles = untracked
                    .filter { !$0.hasSuffix("/") && !VaultArtifactDirs.containsArtifact($0) }
                    .map { repo.appendingPathComponent($0) }

                func consider(_ files: [URL], patternReason: SecretReason, work: Bool) {
                    for url in files where isRegular(url) {
                        let rel = relative(url, to: repo)
                        if let p = SecretPatterns.firstMatch(relativePath: rel, extra: options.extraPatterns) {
                            hits.append(Hit(url: url, reason: patternReason, rule: p, repo: repo))
                        } else if work && options.includeUncommittedWork {
                            hits.append(Hit(url: url, reason: .uncommittedWork, rule: "uncommitted work", repo: repo))
                        } else if options.scanContents,
                                  let rule = scanner.scan(url, maxBytes: options.maxFileSizeBytes) {
                            hits.append(Hit(url: url, reason: .contentMatch, rule: rule, repo: repo))
                        }
                    }
                }
                consider(ignoredFiles, patternReason: .ignoredMatch, work: false)
                consider(untrackedFiles, patternReason: .untrackedMatch, work: true)
            }

            for hit in hits {
                let path = hit.url.standardizedFileURL.path
                guard !seen.contains(path), isRegular(hit.url),
                      !excluded.contains(where: { hit.url.standardizedFileURL == $0 || hit.url.isDescendant(of: $0) }),
                      hit.url.standardizedFileURL.isDescendant(of: root) || hit.url.standardizedFileURL == root,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: hit.url.path),
                      let size = (attrs[.size] as? NSNumber)?.int64Value,
                      size <= options.maxFileSizeBytes else { continue }
                seen.insert(path)

                var info: GitInfo?
                var pathInRepo: String?
                if let repo = hit.repo {
                    if repoInfo[repo.path] == nil { repoInfo[repo.path] = .some(await git.info(forRepository: repo)) }
                    info = repoInfo[repo.path] ?? nil
                    pathInRepo = relative(hit.url, to: repo)
                }
                results.append(SecretFile(
                    sourceURL: hit.url.standardizedFileURL, scanRoot: root,
                    vaultPath: root.lastPathComponent + "/" + relative(hit.url, to: root),
                    reason: hit.reason, matchedRule: hit.rule, sizeBytes: size,
                    modified: attrs[.modificationDate] as? Date, git: info, pathInRepository: pathInRepo))
            }
        }
        return results.sorted { $0.vaultPath < $1.vaultPath }
    }

    // MARK: - Helpers

    private func isRegular(_ url: URL) -> Bool {
        guard let t = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
        else { return false }
        return t == .typeRegular && !url.isSymlink
    }

    private func relative(_ url: URL, to base: URL) -> String {
        let b = base.standardizedFileURL.pathComponents
        let c = url.standardizedFileURL.pathComponents
        guard c.count >= b.count, Array(c.prefix(b.count)) == b else { return url.lastPathComponent }
        return c.dropFirst(b.count).joined(separator: "/")
    }

    /// Walks `dir` (skipping artifact dirs, symlinks and excluded paths), recording every regular file
    /// with the innermost enclosing git repo, and appending newly found repos to `repos`.
    private func walk(
        _ dir: URL, repo: URL?, repos: inout [URL], excluded: [URL],
        into files: inout [(url: URL, repo: URL?)], gitAvailable: Bool
    ) {
        let fm = FileManager.default
        var currentRepo = repo
        if gitAvailable, fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
            currentRepo = dir
            repos.append(dir)
        }
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: []) else { return }
        for item in items {
            let name = item.lastPathComponent
            guard let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]),
                  v.isSymbolicLink != true else { continue }
            let std = item.standardizedFileURL
            if excluded.contains(where: { std == $0 || std.isDescendant(of: $0) }) { continue }
            if v.isDirectory == true {
                if VaultArtifactDirs.names.contains(name) { continue }
                walk(item, repo: currentRepo, repos: &repos, excluded: excluded, into: &files, gitAvailable: gitAvailable)
            } else if v.isRegularFile == true {
                files.append((item, currentRepo))
            }
        }
    }
}
