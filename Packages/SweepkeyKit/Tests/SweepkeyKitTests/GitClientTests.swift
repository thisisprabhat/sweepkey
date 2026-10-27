import Testing
import Foundation
@testable import SweepkeyKit

private let gitAvailable: Bool = {
    guard let r = Process.runSync("/usr/bin/xcode-select", ["-p"]) else { return false }
    return r == 0
}()

private extension Process {
    static func runSync(_ path: String, _ args: [String]) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

@Suite(.enabled(if: gitAvailable)) struct GitClientTests {
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
        try await withTempDir { dir in
            #expect(await git.repositoryRoot(containing: dir) == nil)
        }
    }

    @Test func ignoredPathsListed() async throws {
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
        try await withTempDir { dir in
            try await makeRepo(dir)
            try "changed".write(to: dir.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
            #expect(await git.info(forRepository: dir)?.isDirty == true)
        }
    }

    @Test func ignoredPathsThrowsOutsideRepo() async throws {
        try await withTempDir { dir in
            await #expect(throws: GitError.self) { _ = try await git.ignoredPaths(repositoryRoot: dir) }
            await #expect(throws: GitError.self) { _ = try await git.untrackedPaths(repositoryRoot: dir) }
        }
    }

    @Test func globCharactersInNamesAreLiteral() async throws {
        try await withTempDir { dir in
            try await makeRepo(dir)
            let sub = dir.appending(path: "a[1]")
            try write(10, to: sub.appending(path: "f.txt"))
            try await sh(["add", "."], in: dir)
            try await sh(["commit", "-q", "-m", "glob"], in: dir)
            try FileManager.default.createDirectory(at: dir.appending(path: "a1"), withIntermediateDirectories: true)
            try write(10, to: dir.appending(path: "a1/g.txt"))
            #expect(await git.hasTrackedFiles(at: sub, repositoryRoot: dir))
            #expect(!(await git.hasTrackedFiles(at: dir.appending(path: "a1"), repositoryRoot: dir)))
        }
    }
}
