import SweepkeyKit
import Foundation

extension AppModel {
    var insights: [Insight] { InsightsEngine.suggestions(projects: projects, caches: cacheGroups) }

    var cleanTrend: [TrendPoint] { InsightsEngine.trend(reports: reports) }

    /// Reclaimable bytes per project (largest first); zero-size projects are omitted.
    var treemapByProject: [TreemapItem] {
        projects.filter { $0.reclaimableBytes > 0 }
            .map { TreemapItem(id: $0.id, label: $0.name, bytes: $0.reclaimableBytes) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Reclaimable bytes per ecosystem (projects) and cache category.
    var treemapByEcosystem: [TreemapItem] {
        var totals: [String: Int64] = [:]
        for c in projects.flatMap(\.candidates) { totals[Ecosystem.named(c.ecosystemID).name, default: 0] += c.sizeBytes }
        for g in cacheGroups { totals[g.category.displayName, default: 0] += g.totalBytes }
        return totals.filter { $0.value > 0 }
            .map { TreemapItem(id: $0.key, label: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }
}
