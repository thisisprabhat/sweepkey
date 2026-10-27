import Foundation

enum GitTrackedStatus: Equatable, Sendable { case tracked, untracked, error }

/// Fail-closed check for git-tracked files under a path (unlike `GitClient.hasTrackedFiles`,
/// which reports `false` when git itself fails).
struct GitTrackedCheck: Sendable {
    let shell: ShellRunning
    var gitPath = "/usr/bin/git"

    func status(of path: URL, repositoryRoot: URL) async -> GitTrackedStatus {
        let root = repositoryRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let comps = path.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard comps.count >= root.count, Array(comps.prefix(root.count)) == root else { return .error }
        let rel = comps.dropFirst(root.count).joined(separator: "/")
        let spec = rel.isEmpty ? "." : ":(literal)\(rel)"
        guard let r = try? await shell.run(
            gitPath, arguments: ["-C", repositoryRoot.path, "ls-files", "-z", "--", spec],
            currentDirectory: repositoryRoot, input: nil, timeout: .seconds(60)),
            r.succeeded else { return .error }
        return r.stdout.isEmpty ? .untracked : .tracked
    }
}
