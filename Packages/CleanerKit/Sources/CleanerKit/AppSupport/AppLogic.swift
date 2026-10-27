import Foundation

/// Small pure helpers, kept free of UI and services so they are easy to test.
public enum AppLogic {
    /// Standardizes, resolves symlinks and de-duplicates, preserving order. The executor skips
    /// paths through symlinks and restore fails under symlinked parents, so every root goes
    /// through this before reaching a service.
    public static func resolve(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }.filter { seen.insert($0.path).inserted }
    }

    /// Keeps only existing directories (for drag-and-drop), resolved.
    public static func directories(from urls: [URL]) -> [URL] {
        resolve(urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        })
    }

    /// Splits candidates into cleanable and blocked. A candidate with no verdict is blocked.
    /// With `strict` (every unattended path), a `.warning` verdict (high risk, or the project looks
    /// open in an editor or terminal) also counts as blocked, because nobody is there to acknowledge it.
    public static func partition(
        _ candidates: [Candidate], verdicts: [Candidate.ID: SafetyVerdict], strict: Bool = false
    ) -> (cleanable: [Candidate], blocked: [Candidate]) {
        var cleanable: [Candidate] = []
        var blocked: [Candidate] = []
        for candidate in candidates {
            if isCleanable(verdicts[candidate.id], strict: strict) {
                cleanable.append(candidate)
            } else {
                blocked.append(candidate)
            }
        }
        return (cleanable, blocked)
    }

    /// `partition(_:verdicts:strict: true)`, for unattended cleans.
    public static func partitionStrict(
        _ candidates: [Candidate], verdicts: [Candidate.ID: SafetyVerdict]
    ) -> (cleanable: [Candidate], blocked: [Candidate]) {
        partition(candidates, verdicts: verdicts, strict: true)
    }

    private static func isCleanable(_ verdict: SafetyVerdict?, strict: Bool) -> Bool {
        switch verdict {
        case .allowed?: true
        case .warning?: !strict
        case .blocked?, nil: false
        }
    }

    /// Candidates whose verdict is a warning; the confirmation sheet asks the user to acknowledge these.
    public static func needsAcknowledgement(_ candidate: Candidate, verdict: SafetyVerdict?) -> Bool {
        if candidate.risk == .danger { return true }
        if case .warning? = verdict { return true }
        return false
    }

    /// Distinct, resolved project roots of the items a real run cleaned, in report order. These are
    /// rescanned after a clean (global caches have no project root and are skipped).
    public static func affectedProjectRoots(_ report: CleanReport) -> [URL] {
        guard !report.dryRun else { return [] }
        return resolve(report.items.filter { $0.status == .cleaned }.compactMap(\.candidate.projectRoot))
    }

    /// Items the executor did not process because the run was cancelled.
    public static func cancelledItems(_ report: CleanReport) -> [CleanItemResult] {
        report.items.filter { $0.status == .skipped && $0.message == CleanExecutor.cancelledMessage }
    }

    /// Result rows whose size could not be measured (command actions such as Docker).
    public static func isApproximate(_ item: CleanItemResult) -> Bool {
        item.status == .cleaned && item.freedBytes == 0 && item.candidate.sizeBytes > 0
    }
}

/// Free space on the volume before and after a clean (spec §E).
public struct FreeSpaceDelta: Hashable, Sendable {
    public var before: Int64
    public var after: Int64
    /// Positive when space was gained. Other activity on the disk can make it differ from the
    /// bytes the clean reported, or even be negative.
    public var gained: Int64 { after - before }

    public init(before: Int64, after: Int64) {
        self.before = before
        self.after = after
    }
}
