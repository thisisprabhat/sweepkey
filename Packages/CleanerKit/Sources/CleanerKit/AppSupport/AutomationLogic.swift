import Foundation

/// Which candidates unattended paths (scheduler auto-clean, menu-bar quick clean, the low-space
/// notification action and intents) may clean: only `.safe` artifacts of stale projects. Global
/// caches are never selected, whatever their risk: they are shared by every project and some
/// cleanups (Docker prunes, Homebrew's old versions) are not trivially reversible.
public enum SafeCleanSelection {
    public static func candidates(projects: [Project]) -> [Candidate] {
        projects.filter(\.isStale).flatMap(\.candidates)
            .filter { $0.kind == .projectArtifact && $0.risk == .safe }
    }

    /// Largest first until at least `bytes` are covered (or everything is taken).
    public static func largestFirst(upTo bytes: Int64, from candidates: [Candidate]) -> [Candidate] {
        var total: Int64 = 0
        var picked: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.sizeBytes > $1.sizeBytes }) {
            guard total < bytes else { break }
            picked.append(candidate)
            total += candidate.sizeBytes
        }
        return picked
    }
}

/// Decides whether a low-space alert is due.
public enum LowSpacePolicy {
    public static let minimumInterval: TimeInterval = 6 * 3600

    public static func shouldAlert(
        freeBytes: Int64, thresholdGB: Int, lastAlert: Date?, now: Date, enabled: Bool
    ) -> Bool {
        guard enabled, freeBytes < Int64(thresholdGB) * 1_000_000_000 else { return false }
        if let lastAlert, now.timeIntervalSince(lastAlert) < minimumInterval { return false }
        return true
    }
}

/// Maps raw FSEvents paths to the directories worth rescanning.
public enum FSEventsPlanner {
    /// Paths inside these are churn from builds and tooling, not new or changed projects.
    public static func isNoise(_ path: String, artifactPaths: [String]) -> Bool {
        if path.contains("/.git/") || path.hasSuffix("/.git") || path.hasSuffix(".DS_Store") { return true }
        return artifactPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// The directory to rescan for a changed path: the containing known project, else the first
    /// directory below the scan root (a new project may have appeared there).
    public static func affectedRoot(for path: String, projectPaths: [String], scanRoots: [String]) -> String? {
        if let project = projectPaths.filter({ path == $0 || path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) {
            return project
        }
        guard let root = scanRoots.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) else { return nil }
        let rest = path.dropFirst(root.count + 1)
        guard let first = rest.split(separator: "/").first else { return nil }
        return root + "/" + first
    }
}
