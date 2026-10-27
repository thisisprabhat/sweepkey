import CleanerKit
import Foundation

/// Small pure helpers, kept free of UI and services so they are easy to test.
enum AppLogic {
    /// Standardizes, resolves symlinks and de-duplicates, preserving order. The executor skips
    /// paths through symlinks and restore fails under symlinked parents, so every root goes
    /// through this before reaching a service.
    static func resolve(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }.filter { seen.insert($0.path).inserted }
    }

    /// Keeps only existing directories (for drag-and-drop), resolved.
    static func directories(from urls: [URL]) -> [URL] {
        resolve(urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        })
    }

    /// Splits candidates into cleanable and blocked. A candidate with no verdict is blocked.
    static func partition(
        _ candidates: [Candidate], verdicts: [Candidate.ID: SafetyVerdict]
    ) -> (cleanable: [Candidate], blocked: [Candidate]) {
        var cleanable: [Candidate] = []
        var blocked: [Candidate] = []
        for candidate in candidates {
            if verdicts[candidate.id]?.isAllowed ?? false { cleanable.append(candidate) } else { blocked.append(candidate) }
        }
        return (cleanable, blocked)
    }

    /// Result rows whose size could not be measured (command actions such as Docker).
    static func isApproximate(_ item: CleanItemResult) -> Bool {
        item.status == .cleaned && item.freedBytes == 0 && item.candidate.sizeBytes > 0
    }
}
