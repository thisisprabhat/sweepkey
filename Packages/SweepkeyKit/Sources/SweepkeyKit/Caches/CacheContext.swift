import Foundation

public struct CacheContext: Sendable {
    public var home: URL
    public var shell: ShellRunning
    public var sizer: SizeCalculator
    public var fileExists: @Sendable (URL) -> Bool
    /// Resolves an executable name to a path; nil when not installed. Injectable for tests.
    public var resolve: @Sendable (String) -> String?
    /// Environment lookup (e.g. `ANDROID_HOME`). Injectable for tests.
    public var environment: @Sendable (String) -> String?

    public init(
        home: URL, shell: ShellRunning, sizer: SizeCalculator = SizeCalculator(),
        fileExists: @escaping @Sendable (URL) -> Bool,
        resolve: @escaping @Sendable (String) -> String?,
        environment: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.home = home
        self.shell = shell
        self.sizer = sizer
        self.fileExists = fileExists
        self.resolve = resolve
        self.environment = environment
    }

    public static func live() -> CacheContext {
        CacheContext(
            home: FileManager.default.homeDirectoryForCurrentUser,
            shell: ProcessShellRunner(),
            sizer: SizeCalculator(),
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            resolve: { resolveExecutable($0) },
            environment: { ProcessInfo.processInfo.environment[$0] })
    }
}
