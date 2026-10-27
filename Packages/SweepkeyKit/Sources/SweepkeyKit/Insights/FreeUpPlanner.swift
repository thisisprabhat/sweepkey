import Foundation

public enum FreeUpPlanner {
    /// Greedy plan to free at least `target` bytes. Never selects danger or non-allowed (including
    /// missing-verdict) items. The caller must still run the normal clean confirmation.
    public static func plan(
        target: Int64, projects: [Project], caches: [CacheGroup],
        verdicts: [Candidate.ID: SafetyVerdict]
    ) -> [Candidate] {
        guard target > 0 else { return [] }
        func usable(_ c: Candidate) -> Bool {
            c.sizeBytes > 0 && c.risk != .danger && (verdicts[c.id]?.isAllowed ?? false)
        }
        func bySize(_ list: [Candidate]) -> [Candidate] {
            list.sorted { $0.sizeBytes != $1.sizeBytes ? $0.sizeBytes > $1.sizeBytes : $0.id < $1.id }
        }
        let stale = projects.filter(\.isStale).flatMap(\.candidates).filter(usable)
        let fresh = projects.filter { !$0.isStale }.flatMap(\.candidates).filter(usable)
        let cacheItems = caches.flatMap(\.candidates).filter(usable)

        let tiers: [[Candidate]] = [
            bySize(stale.filter { $0.risk == .safe }),
            bySize(cacheItems.filter { $0.risk == .safe }),
            bySize(fresh.filter { $0.risk == .safe }),
            bySize((stale + fresh + cacheItems).filter { $0.risk == .caution }),
        ]
        var picked: [Candidate] = []
        var seen = Set<Candidate.ID>()
        var total: Int64 = 0
        for tier in tiers {
            for c in tier where seen.insert(c.id).inserted {
                if total >= target { return picked }
                picked.append(c)
                total += c.sizeBytes
            }
        }
        return picked
    }
}
