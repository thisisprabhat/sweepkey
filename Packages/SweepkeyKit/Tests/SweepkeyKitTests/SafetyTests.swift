import Foundation
import Testing
@testable import SweepkeyKit

private let gitAvailable: Bool = {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    p.arguments = ["-p"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}()

private func runGit(_ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args
    p.currentDirectoryURL = dir
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    #expect(p.terminationStatus == 0)
}

private func cand(
    _ url: URL, kind: CandidateKind = .projectArtifact, risk: RiskLevel = .safe,
    project: URL? = nil, action: CleanAction = .delete
) -> Candidate {
    Candidate(
        id: "r|\(url.path)", url: url, kind: kind, title: url.lastPathComponent, ecosystemID: "javascript",
        ruleID: "r", risk: risk, sizeBytes: 1, projectRoot: project, action: action)
}

private func verdict(_ g: SafetyGuard, _ c: Candidate, roots: [URL]) async -> SafetyVerdict {
    await g.evaluate([c], scanRoots: roots)[c.id]!
}

private func isBlocked(_ v: SafetyVerdict) -> Bool { if case .blocked = v { true } else { false } }

@Suite struct SafetyTests {
    @Test func rootHomeScanRootAndSystemBlocked() async throws {
        try await withTempDir { dir in
            let home = dir.appendingPathComponent("home")
            let root = home.appendingPathComponent("Projects")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let g = SafetyGuard(home: home)
            #expect(isBlocked(await verdict(g, cand(URL(fileURLWithPath: "/")), roots: [root])))
            #expect(isBlocked(await verdict(g, cand(home), roots: [root])))
            #expect(isBlocked(await verdict(g, cand(root), roots: [root])))
            for p in ["/System/Library/x", "/usr/lib", "/bin", "/sbin/x", "/Library/Caches", "/Applications/Foo.app"] {
                #expect(isBlocked(await verdict(g, cand(URL(fileURLWithPath: p)), roots: [root])), "\(p)")
            }
        }
    }

    @Test func trailingSlashAndDirectoryFlagCannotDefeatEquality() async throws {
        try await withTempDir { dir in
            let users = dir.appendingPathComponent("Users")
            let home = users.appendingPathComponent("me")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let g = SafetyGuard(home: URL(fileURLWithPath: home.path + "/", isDirectory: true))
            // Scan root is an ancestor of home; candidate is home itself in various spellings.
            for spelling in [home.path, home.path + "/", home.path + "//"] {
                for isDir in [true, false] {
                    let c = cand(URL(fileURLWithPath: spelling, isDirectory: isDir), project: users)
                    #expect(isBlocked(await verdict(g, c, roots: [URL(fileURLWithPath: users.path + "/", isDirectory: true)])),
                            "\(spelling) \(isDir)")
                }
            }
            // Candidate equal to a scan root with differing directory flag.
            let c = cand(URL(fileURLWithPath: users.path, isDirectory: false))
            #expect(isBlocked(await verdict(g, c, roots: [URL(fileURLWithPath: users.path, isDirectory: true)])))
        }
    }

    @Test func systemPrefixIsCaseInsensitive() async throws {
        let g = SafetyGuard(home: URL(fileURLWithPath: "/nonexistent-home"))
        for p in ["/system/library/x", "/USR/lib", "/applications/Foo.app"] {
            #expect(isBlocked(await verdict(g, cand(URL(fileURLWithPath: p)), roots: [URL(fileURLWithPath: "/")])), "\(p)")
        }
    }

    @Test func deleteUnderUsrLocalBlocked() async throws {
        let g = SafetyGuard(home: URL(fileURLWithPath: "/nonexistent-home"))
        let c = cand(URL(fileURLWithPath: "/usr/local/Cellar"), kind: .globalCache)
        #expect(isBlocked(await verdict(g, c, roots: [])))
    }

    @Test func symlinkBlocked() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let real = root.appendingPathComponent("app/real")
            try write(5, to: real.appendingPathComponent("f"))
            let link = root.appendingPathComponent("app/node_modules")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let g = SafetyGuard(home: dir)
            #expect(await verdict(g, cand(link, project: root.appendingPathComponent("app")), roots: [root])
                == .blocked("Symlink"))
        }
    }

    @Test func outsideRootsBlocked() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let other = dir.appendingPathComponent("Other/app/node_modules")
            try write(1, to: other.appendingPathComponent("f"))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let g = SafetyGuard(home: dir.appendingPathComponent("nohome"))
            #expect(isBlocked(await verdict(g, cand(other), roots: [root])))
        }
    }

    @Test func globalCacheMustBeUnderHome() async throws {
        try await withTempDir { dir in
            let home = dir.appendingPathComponent("home")
            let inHome = home.appendingPathComponent("Library/Caches/x")
            let outside = dir.appendingPathComponent("elsewhere/x")
            try write(1, to: inHome.appendingPathComponent("f"))
            try write(1, to: outside.appendingPathComponent("f"))
            let g = SafetyGuard(home: home)
            #expect(await verdict(g, cand(inHome, kind: .globalCache), roots: []) == .allowed)
            #expect(isBlocked(await verdict(g, cand(outside, kind: .globalCache), roots: [])))
            // Commands skip containment rules.
            let cmd = cand(outside, kind: .globalCache, action: .command(executable: "brew", arguments: ["cleanup"]))
            #expect(await verdict(g, cmd, roots: []) == .allowed)
            // ...but rule 1 still applies.
            let sys = cand(URL(fileURLWithPath: "/System/x"), kind: .globalCache,
                           action: .command(executable: "x", arguments: []))
            #expect(isBlocked(await verdict(g, sys, roots: [])))
            // Homebrew-managed locations are fine for commands.
            let brew = cand(URL(fileURLWithPath: "/opt/homebrew/Cache"), kind: .globalCache,
                            action: .command(executable: "brew", arguments: ["cleanup"]))
            #expect(await verdict(g, brew, roots: []) == .allowed)
            let local = cand(URL(fileURLWithPath: "/usr/local/Cellar"), kind: .globalCache,
                             action: .command(executable: "brew", arguments: ["cleanup"]))
            #expect(await verdict(g, local, roots: []) == .allowed)
        }
    }

    @Test func pinnedBlocked() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let nm = proj.appendingPathComponent("node_modules")
            try write(1, to: nm.appendingPathComponent("f"))
            let g = SafetyGuard(home: dir.appendingPathComponent("h"), pinnedProjects: [proj])
            #expect(await verdict(g, cand(nm, project: proj), roots: [root]) == .blocked("Pinned project"))
        }
    }

    @Test func dangerWarns() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let t = proj.appendingPathComponent("build")
            try write(1, to: t.appendingPathComponent("f"))
            let g = SafetyGuard(home: dir.appendingPathComponent("h"))
            guard case let .warning(msg) = await verdict(g, cand(t, risk: .danger, project: proj), roots: [root])
            else { Issue.record("expected warning"); return }
            #expect(msg.hasPrefix("High risk"))
        }
    }

    @Test func activeDirectoryWarns() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let t = proj.appendingPathComponent("build")
            try write(1, to: t.appendingPathComponent("f"))
            let sub = proj.appendingPathComponent("src")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for active in [proj, sub] {
                let g = SafetyGuard(home: dir.appendingPathComponent("h"), activeDirectories: { [active] })
                guard case let .warning(msg) = await verdict(g, cand(t, project: proj), roots: [root])
                else { Issue.record("expected warning"); return }
                #expect(msg.hasPrefix("Project appears to be open in"))
            }
            let unrelated = SafetyGuard(home: dir.appendingPathComponent("h"),
                                        activeDirectories: { [root.appendingPathComponent("other")] })
            #expect(await verdict(unrelated, cand(t, project: proj), roots: [root]) == .allowed)
        }
    }

    @Test func allowedByDefault() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let t = proj.appendingPathComponent("node_modules")
            try write(1, to: t.appendingPathComponent("f"))
            let g = SafetyGuard(home: dir.appendingPathComponent("h"))
            #expect(await verdict(g, cand(t, project: proj), roots: [root]) == .allowed)
        }
    }

    @Test(.enabled(if: gitAvailable)) func gitTrackedBlocked() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            try write(1, to: proj.appendingPathComponent("dist/tracked.js"))
            try write(1, to: proj.appendingPathComponent("build/ignored.o"))
            try "build/\n".write(to: proj.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
            try runGit(["init", "-q"], in: proj)
            try runGit(["add", "."], in: proj)
            try runGit(["commit", "-q", "-m", "init"], in: proj)
            let g = SafetyGuard(home: dir.appendingPathComponent("h"))
            let dist = proj.appendingPathComponent("dist")
            #expect(await verdict(g, cand(dist, project: proj), roots: [root])
                == .blocked("Contains files tracked by git"))
            let build = proj.appendingPathComponent("build")
            #expect(await verdict(g, cand(build, project: proj), roots: [root]) == .allowed)
        }
    }

    private struct FailingGitShell: ShellRunning {
        func run(_ executable: String, arguments: [String], currentDirectory: URL?, input: Data?, timeout: Duration)
            async throws -> ShellResult {
            ShellResult(exitCode: 128, stdout: "", stderr: "fatal: broken")
        }
    }

    @Test(.enabled(if: gitAvailable)) func gitFailureFailsClosed() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            try write(1, to: proj.appendingPathComponent("build/o"))
            try runGit(["init", "-q"], in: proj)
            let g = SafetyGuard(gitShell: FailingGitShell(), home: dir.appendingPathComponent("h"))
            #expect(await verdict(g, cand(proj.appendingPathComponent("build"), project: proj), roots: [root])
                == .blocked("Could not verify git status"))
        }
    }

    // MARK: Final review fixes

    /// Scripted git: `xcode-select -p` succeeds when `available`; every git command fails.
    private final class ScriptedGit: ShellRunning, @unchecked Sendable {
        let available: Bool
        private let lock = NSLock()
        private var _calls: [String] = []
        init(available: Bool) { self.available = available }
        var calls: [String] { lock.withLock { _calls } }
        func run(_ executable: String, arguments: [String], currentDirectory: URL?, input: Data?, timeout: Duration)
            async throws -> ShellResult {
            lock.withLock { _calls.append(([executable] + arguments).joined(separator: " ")) }
            if executable == "xcode-select" {
                return ShellResult(exitCode: available ? 0 : 2, stdout: "", stderr: "")
            }
            return ShellResult(exitCode: 128, stdout: "", stderr: "fatal: not a git repository")
        }
    }

    @Test func pinnedMonorepoProtectsNestedProjects() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let mono = root.appendingPathComponent("mono")
            let pkg = mono.appendingPathComponent("packages/a")
            let nested = pkg.appendingPathComponent("node_modules")
            try write(1, to: nested.appendingPathComponent("f"))
            let sibling = root.appendingPathComponent("monolith")
            let siblingNM = sibling.appendingPathComponent("node_modules")
            try write(1, to: siblingNM.appendingPathComponent("f"))
            let g = SafetyGuard(git: GitClient(shell: ScriptedGit(available: false)),
                                home: dir.appendingPathComponent("h"), pinnedProjects: [mono])
            #expect(await verdict(g, cand(nested, project: pkg), roots: [root]) == .blocked("Pinned project"))
            // Same string prefix ("mono" vs "monolith") is not containment.
            #expect(await verdict(g, cand(siblingNM, project: sibling), roots: [root]) == .allowed)
        }
    }

    @Test func gitEntryWithFailingGitIsBlocked() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let build = proj.appendingPathComponent("build")
            try write(1, to: build.appendingPathComponent("o"))
            try FileManager.default.createDirectory(at: proj.appendingPathComponent(".git"), withIntermediateDirectories: true)
            for available in [true, false] {
                let shell = ScriptedGit(available: available)
                let g = SafetyGuard(git: GitClient(shell: shell), gitShell: shell, home: dir.appendingPathComponent("h"))
                #expect(await verdict(g, cand(build, project: proj), roots: [root]) == .blocked("Could not verify git status"),
                        "available: \(available)")
                if !available {
                    #expect(!shell.calls.contains { $0.contains("rev-parse") }, "git must not run without the CLT")
                }
            }
        }
    }

    @Test func gitFileEntryCountsAsRepository() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("worktree")
            let build = proj.appendingPathComponent("build")
            try write(1, to: build.appendingPathComponent("o"))
            try writeText("gitdir: /elsewhere/.git/worktrees/x\n", to: proj.appendingPathComponent(".git"))
            let shell = ScriptedGit(available: true)
            let g = SafetyGuard(git: GitClient(shell: shell), gitShell: shell, home: dir.appendingPathComponent("h"))
            #expect(await verdict(g, cand(build, project: proj), roots: [root]) == .blocked("Could not verify git status"))
        }
    }

    @Test func noGitEntryWithFailingGitIsNotBlockedByGitRule() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let build = proj.appendingPathComponent("build")
            try write(1, to: build.appendingPathComponent("o"))
            for available in [true, false] {
                let shell = ScriptedGit(available: available)
                let g = SafetyGuard(git: GitClient(shell: shell), gitShell: shell, home: dir.appendingPathComponent("h"))
                #expect(await verdict(g, cand(build, project: proj), roots: [root]) == .allowed)
            }
        }
    }

    @Test func gitAvailabilityCheckedOncePerEvaluation() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            var cands: [Candidate] = []
            for i in 0..<20 {
                let proj = root.appendingPathComponent("p\(i)")
                let nm = proj.appendingPathComponent("node_modules")
                try write(1, to: nm.appendingPathComponent("f"))
                cands.append(cand(nm, project: proj))
            }
            let shell = ScriptedGit(available: false)
            let g = SafetyGuard(git: GitClient(shell: shell), gitShell: shell, home: dir.appendingPathComponent("h"))
            let result = await g.evaluate(cands, scanRoots: [root])
            #expect(result.count == 20 && result.values.allSatisfy { $0 == .allowed })
            #expect(shell.calls.filter { $0.hasPrefix("xcode-select") }.count == 1)
        }
    }

    @Test func gitMetadataIsAlwaysBlocked() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("Projects")
            let proj = root.appendingPathComponent("app")
            let gitDir = proj.appendingPathComponent(".git")
            try write(1, to: gitDir.appendingPathComponent("objects/pack/x"))
            let g = SafetyGuard(git: GitClient(shell: ScriptedGit(available: false)), home: dir.appendingPathComponent("h"))
            #expect(await verdict(g, cand(gitDir, project: proj), roots: [root]) == .blocked("Git metadata (.git)"))
            #expect(await verdict(g, cand(gitDir.appendingPathComponent("objects"), project: proj), roots: [root])
                == .blocked("Git metadata (.git)"))
            let cache = cand(dir.appendingPathComponent("h/.GIT/x"), kind: .globalCache)
            #expect(await verdict(g, cache, roots: []) == .blocked("Git metadata (.git)"))
        }
    }
}
