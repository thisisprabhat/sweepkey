import Testing
import Foundation
@testable import CleanerKit

@Suite struct GitClientTests {
    let git = GitClient()
    let shell = ProcessShellRunner()

    private func sh(_ args: [String], in dir: URL) async throws {
        let r = try await shell.run("/usr/bin/git", arguments: args, currentDirectory: dir,
                                    input: nil, timeout: .seconds(30))
        #expect(r.succeeded, "git \(args) failed: \(r.stderr)")
    }

    private func makeRepo(_ dir: URL) async throws {
        try await sh(["init", "-q", "-b", "main"], in: dir)
        try await sh(["config", "user.email", "t@example.com"], in: dir)
        try await sh(["config", "user.name", "T"], in: dir)
        try await sh(["config", "commit.gpgsign", "false"], in: dir)
        try "node_modules/\n.env\n".write(to: dir.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "tracked".write(to: dir.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try await sh(["add", "."], in: dir)
        try await sh(["commit", "-q", "-m", "init"], in: dir)
    }

    @Test func trackedVsUntracked() async throws {
        guard await git.isAvailable() else { return }
        try await withTempDir { dir in
            try await makeRepo(dir)
            try "x".write(to: dir.appending(path: "new.txt"), atomically: true, encoding: .utf8)
            let root = await git.repositoryRoot(containing: dir)
            #expect(root?.resolvingSymlinksInPath() == dir)
            #expect(await git.hasTrackedFiles(at: dir.appending(path: "tracked.txt"), repositoryRoot: dir))
            #expect(await git.hasTrackedFiles(at: dir, repositoryRoot: dir))
            #expect(!(await git.hasTrackedFiles(at: dir.appending(path: "new.txt"), repositoryRoot: dir)))
            let untracked = try await git.untrackedPaths(repositoryRoot: dir)
            #expect(untracked == ["new.txt"])
        }
    }

    @Test func notARepository() async throws {
        guard await git.isAvailable() else { return }
        try await withTempDir { dir in
            #expect(await git.repositoryRoot(containing: dir) == nil)
        }
    }

    @Test func ignoredPathsListed() async throws {
        guard await git.isAvailable() else { return }
        try await withTempDir { dir in
            try await makeRepo(dir)
            try "SECRET=1".write(to: dir.appending(path: ".env"), atomically: true, encoding: .utf8)
            try write(10, to: dir.appending(path: "node_modules/pkg/index.js"))
            let ignored = try await git.ignoredPaths(repositoryRoot: dir)
            #expect(ignored.contains(".env"))
            #expect(ignored.contains("node_modules/"))
        }
    }

    @Test func infoHasBranchAndDate() async throws {
        guard await git.isAvailable() else { return }
        try await withTempDir { dir in
            try await makeRepo(dir)
            let info = await git.info(forRepository: dir)
            #expect(info?.branch == "main")
            #expect(info?.lastCommitDate != nil)
            #expect(info?.headCommit?.count == 40)
            #expect(info?.isDirty == false)
            #expect(info?.stashCount == 0)
            #expect(info?.unpushedCommitCount == nil)
        }
    }

    @Test func dirtyDetected() async throws {
        guard await git.isAvailable() else { return }
        try await withTempDir { dir in
            try await makeRepo(dir)
            try "changed".write(to: dir.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
            #expect(await git.info(forRepository: dir)?.isDirty == true)
        }
    }
}
