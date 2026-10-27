import Foundation

public struct GlobalCacheScanner: CacheScanning {
    private let providers: [CacheProvider]
    private let context: CacheContext

    public init(providers: [CacheProvider] = CacheProviders.all, context: CacheContext = .live()) {
        self.providers = providers
        self.context = context
    }

    public func scanCaches() async -> [CacheGroup] {
        let context = self.context
        var groups: [CacheGroup] = []
        await withTaskGroup(of: [CacheGroup].self) { taskGroup in
            for provider in providers {
                taskGroup.addTask { await provider.detect(context) }
            }
            for await result in taskGroup { groups.append(contentsOf: result) }
        }
        // Every group without candidates is dropped, except explicit info-only groups (id ends in ".info").
        return groups
            .filter { !$0.candidates.isEmpty || $0.id.hasSuffix(CacheGroup.infoOnlySuffix) }
            .sorted { ($0.totalBytes, $1.title) > ($1.totalBytes, $0.title) }
    }
}

extension CacheGroup {
    /// Group ids ending in this suffix mark info-only groups (no candidates, `detail` text only)
    /// that the scanner keeps even though they are empty.
    static let infoOnlySuffix = ".info"
}
