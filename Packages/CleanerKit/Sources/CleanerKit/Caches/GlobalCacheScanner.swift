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
        // Groups with neither candidates nor an informational detail are dropped.
        return groups
            .filter { !$0.candidates.isEmpty || $0.detail != nil }
            .sorted { ($0.totalBytes, $1.title) > ($1.totalBytes, $0.title) }
    }
}
