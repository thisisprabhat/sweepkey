import Foundation

/// Locates `rules.json` for shipped binaries.
///
/// SwiftPM's generated `Bundle.module` looks beside `Bundle.main.bundleURL` (not symlink-resolved)
/// and otherwise falls back to the build directory, then traps. A CLI installed through a symlink
/// (Homebrew `binary`) must find the resource bundle next to the *real* executable instead.
enum RuleResources {
    static let bundleName = "SweepkeyKit_SweepkeyKit.bundle"

    /// Directories that may contain the resource bundle, most specific first.
    static func candidateDirectories(
        executablePath: String? = executablePath(),
        mainResourceURL: URL? = Bundle.main.resourceURL
    ) -> [URL] {
        var dirs: [URL] = []
        if let executablePath {
            let real = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
            let dir = real.deletingLastPathComponent()
            dirs.append(dir)
            // App bundle layout: Contents/MacOS/<exe>, resources in Contents/Resources.
            dirs.append(dir.deletingLastPathComponent().appendingPathComponent("Resources"))
        }
        if let mainResourceURL { dirs.append(mainResourceURL) }
        return dirs
    }

    /// URL of `rules.json` found beside the executable, or nil when not found.
    static func rulesURL(
        executablePath: String? = executablePath(),
        mainResourceURL: URL? = Bundle.main.resourceURL
    ) -> URL? {
        for dir in candidateDirectories(executablePath: executablePath, mainResourceURL: mainResourceURL) {
            let bundleURL = dir.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: "rules", withExtension: "json") {
                return url
            }
            let direct = bundleURL.appendingPathComponent("rules.json")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
        }
        return nil
    }

    static func executablePath() -> String? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [UInt8](repeating: 0, count: Int(size))
        let ok = buffer.withUnsafeMutableBytes {
            _NSGetExecutablePath($0.bindMemory(to: CChar.self).baseAddress, &size) == 0
        }
        guard ok else { return CommandLine.arguments.first }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}
