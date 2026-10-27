import Foundation

public protocol CacheProvider: Sendable {
    var id: String { get }
    func detect(_ context: CacheContext) async -> [CacheGroup]
}

public enum CacheProviders {
    public static let all: [CacheProvider] = [
        XcodeProvider(),
        AndroidProvider(),
        PackageManagerProvider(),
        VersionManagerProvider(),
        ContainerProvider(),
        BrowserTestingProvider(),
        IDEProvider(),
        AIModelProvider(),
        MiscProvider(),
    ]
}
