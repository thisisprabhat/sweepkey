import Foundation

public struct Insight: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbolName: String
    public var estimatedBytes: Int64

    public init(id: String, title: String, detail: String, symbolName: String, estimatedBytes: Int64) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.estimatedBytes = estimatedBytes
    }
}

public struct TrendPoint: Hashable, Sendable {
    public var day: Date
    public var freedBytes: Int64

    public init(day: Date, freedBytes: Int64) {
        self.day = day
        self.freedBytes = freedBytes
    }
}

public enum InsightsEngine {
    public static let nodeModulesThreshold = 5
    public static let venvThreshold = 3
    public static let derivedDataBytes: Int64 = 10 * 1_073_741_824
    public static let dockerBytes: Int64 = 5 * 1_073_741_824
    public static let staleBytes: Int64 = 10 * 1_073_741_824

    private static let venvRules: Set<String> = ["python.venv", "python.dot_venv", "python.env"]

    public static func suggestions(projects: [Project], caches: [CacheGroup]) -> [Insight] {
        var out: [Insight] = []
        let artifacts = projects.flatMap(\.candidates)
        let cacheItems = caches.flatMap(\.candidates)

        let nodes = artifacts.filter { $0.ruleID == "javascript.node_modules" }
        if nodes.count >= nodeModulesThreshold {
            let bytes = nodes.reduce(0) { $0 + $1.sizeBytes }
            out.append(Insight(
                id: "node-modules-dedupe",
                title: "Switch to pnpm/Bun to deduplicate (\(nodes.count) copies, \(gb(bytes)))",
                detail: "Package managers with a global content store share files between projects.",
                symbolName: "square.stack.3d.up", estimatedBytes: bytes))
        }

        let venvs = artifacts.filter { venvRules.contains($0.ruleID) }
        if venvs.count >= venvThreshold {
            let bytes = venvs.reduce(0) { $0 + $1.sizeBytes }
            out.append(Insight(
                id: "python-venvs-uv",
                title: "Use uv with a global cache (\(venvs.count) virtualenvs, \(gb(bytes)))",
                detail: "uv hard-links packages from one cache instead of copying them into each environment.",
                symbolName: "shippingbox", estimatedBytes: bytes))
        }

        let sims = cacheItems.filter {
            $0.ruleID == "xcode.unavailableSimulators" || $0.ruleID.hasPrefix("xcode.runtime.")
        }
        if !sims.isEmpty {
            let bytes = sims.reduce(0) { $0 + $1.sizeBytes }
            out.append(Insight(
                id: "xcode-simulators",
                title: "Remove unavailable simulators and old runtimes (\(sims.count) found)",
                detail: "Simulators and runtimes for old Xcode versions can be deleted and re-downloaded.",
                symbolName: "iphone.gen3", estimatedBytes: bytes))
        }

        let derived = cacheItems.filter { $0.ruleID == "xcode.derivedData" }.reduce(0) { $0 + $1.sizeBytes }
        if derived > derivedDataBytes {
            out.append(Insight(
                id: "derived-data",
                title: "Xcode DerivedData is \(gb(derived))",
                detail: "It is rebuilt automatically on the next build.",
                symbolName: "hammer", estimatedBytes: derived))
        }

        let docker = cacheItems
            .filter { $0.ruleID.hasPrefix("container.") && $0.ruleID != "container.dockerDisk.info" }
            .reduce(0) { $0 + $1.sizeBytes }
        if docker > dockerBytes {
            out.append(Insight(
                id: "docker-reclaimable",
                title: "Docker has \(gb(docker)) reclaimable",
                detail: "Build cache, unused images and stopped containers can be pruned.",
                symbolName: "cube.box", estimatedBytes: docker))
        }

        let stale = projects.filter(\.isStale)
        let staleTotal = stale.reduce(0) { $0 + $1.reclaimableBytes }
        if staleTotal > staleBytes {
            out.append(Insight(
                id: "stale-projects",
                title: "\(stale.count) stale projects hold \(gb(staleTotal))",
                detail: "These projects have not been touched recently; their artifacts regenerate on demand.",
                symbolName: "clock.badge.exclamationmark", estimatedBytes: staleTotal))
        }
        return out
    }

    /// Freed bytes per calendar day from non-dry-run reports, oldest first.
    public static func trend(reports: [CleanReport], calendar: Calendar = .current) -> [TrendPoint] {
        var perDay: [Date: Int64] = [:]
        for report in reports where !report.dryRun {
            perDay[calendar.startOfDay(for: report.finishedAt), default: 0] += report.freedBytes
        }
        return perDay.map { TrendPoint(day: $0.key, freedBytes: $0.value) }.sorted { $0.day < $1.day }
    }

    private static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
