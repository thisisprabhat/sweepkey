import ArgumentParser
import CleanerKit
import Foundation

/// Resolves a user-supplied path (tilde, relative, symlinks) to a canonical URL.
func resolvedURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        .standardizedFileURL.resolvingSymlinksInPath()
}

func resolvedURL(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

var standardInputIsTTY: Bool { isatty(STDIN_FILENO) != 0 }

/// Prompts on stdout and reads a line; only "y"/"yes" confirms.
func confirm(_ prompt: String) -> Bool {
    print(prompt, terminator: " ")
    guard let line = readLine() else { return false }
    return ["y", "yes"].contains(line.trimmingCharacters(in: .whitespaces).lowercased())
}

/// Reads a password without echo from the terminal.
func readPassword(_ prompt: String) -> String? {
    var buffer = [CChar](repeating: 0, count: 256)
    guard readpassphrase(prompt, &buffer, buffer.count, 0) != nil else { return nil }
    defer { for i in buffer.indices { buffer[i] = 0 } }
    let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
    return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// Roots from the command line, or the settings' scan roots when none were given. All symlink-resolved.
func resolveRoots(_ paths: [String], settings: CleanerSettings) throws -> [URL] {
    let roots = paths.isEmpty ? settings.scanRoots.map(resolvedURL) : paths.map(resolvedURL)
    guard !roots.isEmpty else {
        throw CLIError("No paths given and no scan roots are configured in Cleaner's settings.")
    }
    for root in roots {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw CLIError("Not a directory: \(root.path)")
        }
    }
    return roots
}

/// Scans `roots` with the user's settings applied and returns the projects, largest first.
func scanProjects(roots: [URL], settings: CleanerSettings, staleOnly: Bool) async throws -> [Project] {
    let options = ScanOptions(
        roots: roots,
        excludedPaths: settings.excludedPaths.map(resolvedURL),
        ruleOverrides: settings.ruleOverrides,
        customRules: settings.customRules,
        staleAfterDays: settings.staleAfterDays
    )
    var projects: [Project] = []
    for try await event in ProjectScanner().scan(options) {
        if case .project(let project) = event { projects.append(project) }
    }
    if staleOnly { projects = projects.filter(\.isStale) }
    return projects.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
}

/// A runtime failure reported as "Error: <message>" with exit code 1.
struct CLIError: Error, CustomStringConvertible, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
    var errorDescription: String? { message }
}
