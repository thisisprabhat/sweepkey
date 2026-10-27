import Foundation
@testable import SweepkeyKit

let vaultGitAvailable: Bool = {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    p.arguments = ["-p"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}()

let hdiutilAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")

@discardableResult
func vaultGit(_ args: [String], in dir: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args
    p.currentDirectoryURL = dir
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

func writeText(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// Fixture: <dir>/Root/app (git repo).
func makeFixtureRepo(in dir: URL) throws -> (root: URL, app: URL) {
    let root = dir.appendingPathComponent("Root", isDirectory: true)
    let app = root.appendingPathComponent("app", isDirectory: true)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    try vaultGit(["init", "-q"], in: app)
    try writeText(".env\n*.jks\nnode_modules/\n", to: app.appendingPathComponent(".gitignore"))
    try writeText("SECRET=1\n", to: app.appendingPathComponent(".env"))
    try writeText("KEYSTORE", to: app.appendingPathComponent("android/app/upload.jks"))
    try writeText("X=1\n", to: app.appendingPathComponent("node_modules/x/.env"))
    try writeText("name: app\n", to: app.appendingPathComponent("pubspec.yaml"))
    try vaultGit(["add", ".gitignore", "pubspec.yaml"], in: app)
    try vaultGit(["commit", "-q", "-m", "init"], in: app)
    return (root, app)
}

func makeFile(
    _ url: URL, root: URL, reason: SecretReason = .patternMatch, git: GitInfo? = nil, pathInRepo: String? = nil
) throws -> SecretFile {
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    let rel = url.path.dropFirst(root.path.count + 1)
    return SecretFile(
        sourceURL: url, scanRoot: root, vaultPath: root.lastPathComponent + "/" + rel,
        reason: reason, matchedRule: "x", sizeBytes: size, git: git, pathInRepository: pathInRepo)
}
