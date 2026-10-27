import Foundation

public enum GitError: Error, Sendable, Equatable {
    case commandFailed(String)
}

public struct GitClient: Sendable {
    private let shell: ShellRunning
    private let gitPath: String

    public init(shell: ShellRunning = ProcessShellRunner(), gitPath: String = "/usr/bin/git") {
        self.shell = shell
        self.gitPath = gitPath
    }

    /// True only if `xcode-select -p` succeeds, so the CLT install prompt is never triggered.
    public func isAvailable() async -> Bool {
        guard let r = try? await shell.run("xcode-select", ["-p"]) else { return false }
        return r.succeeded
    }

    private func git(_ args: [String], in dir: URL) async throws -> ShellResult {
        try await shell.run(gitPath, arguments: args, currentDirectory: dir, input: nil, timeout: .seconds(60))
    }

    public func repositoryRoot(containing url: URL) async -> URL? {
        let dir = url.isDirectory ? url : url.deletingLastPathComponent()
        guard let r = try? await git(["rev-parse", "--show-toplevel"], in: dir), r.succeeded else { return nil }
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Note: `isDirty` is true when there are any changes, including untracked files.
    public func info(forRepository root: URL) async -> GitInfo? {
        guard let inside = try? await git(["rev-parse", "--is-inside-work-tree"], in: root),
              inside.succeeded else { return nil }

        func out(_ args: [String]) async -> String? {
            guard let r = try? await git(args, in: root), r.succeeded else { return nil }
            let s = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        let branch = await out(["symbolic-ref", "--short", "-q", "HEAD"])
        let head = await out(["rev-parse", "HEAD"])
        let remote = await out(["config", "--get", "remote.origin.url"])
        var lastDate: Date?
        if let s = await out(["log", "-1", "--format=%ct"]), let t = TimeInterval(s) {
            lastDate = Date(timeIntervalSince1970: t)
        }
        let dirty = (try? await git(["status", "--porcelain"], in: root))
            .map { $0.succeeded && !$0.stdout.isEmpty } ?? false
        var unpushed: Int?
        if await out(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]) != nil,
           let s = await out(["rev-list", "--count", "@{upstream}..HEAD"]) {
            unpushed = Int(s)
        }
        let stashCount = (await out(["stash", "list"]))?
            .split(separator: "\n", omittingEmptySubsequences: true).count ?? 0

        return GitInfo(
            repositoryRoot: root, remoteURL: remote, branch: branch, headCommit: head,
            lastCommitDate: lastDate, isDirty: dirty, unpushedCommitCount: unpushed,
            stashCount: stashCount)
    }

    public func hasTrackedFiles(at path: URL, repositoryRoot: URL) async -> Bool {
        let root = repositoryRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let comps = path.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let rel: String
        if comps.count >= root.count, Array(comps.prefix(root.count)) == root {
            let tail = comps.dropFirst(root.count)
            rel = tail.isEmpty ? "." : tail.joined(separator: "/")
        } else {
            return false
        }
        guard let r = try? await git(["ls-files", "-z", "--", ":(literal)\(rel)"], in: repositoryRoot), r.succeeded else {
            return false
        }
        return !r.stdout.isEmpty
    }

    public func ignoredPaths(repositoryRoot: URL) async throws -> [String] {
        let r = try await git(
            ["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"],
            in: repositoryRoot)
        try Self.requireSuccess(r)
        return Self.splitNUL(r.stdout)
    }

    public func untrackedPaths(repositoryRoot: URL) async throws -> [String] {
        let r = try await git(["ls-files", "-z", "--others", "--exclude-standard"], in: repositoryRoot)
        try Self.requireSuccess(r)
        return Self.splitNUL(r.stdout)
    }

    private static func requireSuccess(_ r: ShellResult) throws {
        guard r.succeeded else {
            throw GitError.commandFailed(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func splitNUL(_ s: String) -> [String] {
        s.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
    }
}
