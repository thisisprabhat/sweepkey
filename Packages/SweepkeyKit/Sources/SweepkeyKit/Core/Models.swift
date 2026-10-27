import Foundation

public enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case safe, caution, danger

    private var order: Int {
        switch self {
        case .safe: 0
        case .caution: 1
        case .danger: 2
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.order < rhs.order }
}

public enum DeleteMode: String, Codable, Sendable, CaseIterable { case permanent, trash }

public enum CandidateKind: String, Codable, Sendable { case projectArtifact, globalCache }

public enum CleanAction: Codable, Hashable, Sendable {
    /// Remove/trash `Candidate.url`.
    case delete
    /// Tool-native cleanup (e.g. "docker", ["system","prune","-f"]).
    case command(executable: String, arguments: [String])
}

public struct Ecosystem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var symbolName: String

    public init(id: String, name: String, symbolName: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    public static let builtIn: [Ecosystem] = [
        Ecosystem(id: "javascript", name: "JavaScript/TypeScript", symbolName: "curlybraces"),
        Ecosystem(id: "python", name: "Python", symbolName: "chevron.left.forwardslash.chevron.right"),
        Ecosystem(id: "flutter", name: "Flutter/Dart", symbolName: "bird"),
        Ecosystem(id: "android", name: "Android", symbolName: "apps.iphone"),
        Ecosystem(id: "jvm", name: "Java/Kotlin", symbolName: "cup.and.saucer"),
        Ecosystem(id: "rust", name: "Rust", symbolName: "gearshape.2"),
        Ecosystem(id: "swift", name: "Swift/iOS", symbolName: "swift"),
        Ecosystem(id: "go", name: "Go", symbolName: "hare"),
        Ecosystem(id: "dotnet", name: ".NET", symbolName: "number"),
        Ecosystem(id: "cpp", name: "C/C++", symbolName: "c.square"),
        Ecosystem(id: "elixir", name: "Elixir", symbolName: "drop"),
        Ecosystem(id: "haskell", name: "Haskell", symbolName: "function"),
        Ecosystem(id: "ruby", name: "Ruby", symbolName: "diamond"),
        Ecosystem(id: "php", name: "PHP", symbolName: "p.square"),
        Ecosystem(id: "zig", name: "Zig", symbolName: "bolt"),
        Ecosystem(id: "scala", name: "Scala", symbolName: "s.square"),
        Ecosystem(id: "bazel", name: "Bazel", symbolName: "shippingbox"),
        Ecosystem(id: "terraform", name: "Terraform", symbolName: "cloud"),
        Ecosystem(id: "unity", name: "Unity", symbolName: "cube"),
        Ecosystem(id: "unreal", name: "Unreal", symbolName: "gamecontroller"),
        Ecosystem(id: "generic", name: "Other", symbolName: "folder"),
    ]

    /// Looks up a built-in ecosystem by id, falling back to "generic".
    public static func named(_ id: String) -> Ecosystem {
        builtIn.first { $0.id == id } ?? builtIn.first { $0.id == "generic" }!
    }
}

public struct Rule: Codable, Hashable, Sendable, Identifiable {
    /// e.g. "javascript.node_modules"
    public var id: String
    public var ecosystemID: String
    /// Any-of; file names or globs ("*.csproj") that must exist in the project dir.
    public var markers: [String]
    /// Relative path from project dir; last segment may be a glob; may contain "/".
    public var target: String
    public var risk: RiskLevel
    public var enabledByDefault: Bool
    /// e.g. "npm install"
    public var regenerate: String?
    public var note: String?

    public init(
        id: String, ecosystemID: String, markers: [String], target: String,
        risk: RiskLevel, enabledByDefault: Bool,
        regenerate: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.ecosystemID = ecosystemID
        self.markers = markers
        self.target = target
        self.risk = risk
        self.enabledByDefault = enabledByDefault
        self.regenerate = regenerate
        self.note = note
    }
}

public struct Candidate: Identifiable, Codable, Hashable, Sendable {
    /// "<ruleID>|<url.path>"
    public var id: String
    public var url: URL
    public var kind: CandidateKind
    /// e.g. "node_modules", "Xcode DerivedData"
    public var title: String
    /// Ecosystem id for artifacts; CacheCategory.rawValue for caches.
    public var ecosystemID: String
    public var ruleID: String
    public var risk: RiskLevel
    public var sizeBytes: Int64
    public var lastModified: Date?
    public var projectRoot: URL?
    public var regenerateHint: String?
    public var note: String?
    public var action: CleanAction
    /// For command actions whose tool frees space somewhere other than `url` (simulator runtime
    /// images live under /Library), the file measured before and after to get the bytes freed.
    /// Only ever measured, never deleted; safety checks still apply to `url`.
    public var sizeProbeURL: URL?

    public init(
        id: String, url: URL, kind: CandidateKind, title: String, ecosystemID: String,
        ruleID: String, risk: RiskLevel, sizeBytes: Int64, lastModified: Date? = nil,
        projectRoot: URL? = nil, regenerateHint: String? = nil, note: String? = nil,
        action: CleanAction = .delete, sizeProbeURL: URL? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.title = title
        self.ecosystemID = ecosystemID
        self.ruleID = ruleID
        self.risk = risk
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.projectRoot = projectRoot
        self.regenerateHint = regenerateHint
        self.note = note
        self.action = action
        self.sizeProbeURL = sizeProbeURL
    }
}

public struct GitInfo: Codable, Hashable, Sendable {
    public var repositoryRoot: URL
    public var remoteURL: String?
    public var branch: String?
    public var headCommit: String?
    public var lastCommitDate: Date?
    public var isDirty: Bool
    /// nil = no upstream
    public var unpushedCommitCount: Int?
    public var stashCount: Int

    public init(
        repositoryRoot: URL, remoteURL: String? = nil, branch: String? = nil,
        headCommit: String? = nil, lastCommitDate: Date? = nil, isDirty: Bool = false,
        unpushedCommitCount: Int? = nil, stashCount: Int = 0
    ) {
        self.repositoryRoot = repositoryRoot
        self.remoteURL = remoteURL
        self.branch = branch
        self.headCommit = headCommit
        self.lastCommitDate = lastCommitDate
        self.isDirty = isDirty
        self.unpushedCommitCount = unpushedCommitCount
        self.stashCount = stashCount
    }
}

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var name: String
    public var ecosystemIDs: [String]
    public var candidates: [Candidate]
    public var git: GitInfo?
    public var lastActivity: Date?
    public var isStale: Bool
    /// Sum of candidates' sizes.
    public var reclaimableBytes: Int64 { candidates.reduce(0) { $0 + $1.sizeBytes } }

    public init(
        url: URL, name: String, ecosystemIDs: [String] = [], candidates: [Candidate] = [],
        git: GitInfo? = nil, lastActivity: Date? = nil, isStale: Bool = false
    ) {
        self.url = url
        self.name = name
        self.ecosystemIDs = ecosystemIDs
        self.candidates = candidates
        self.git = git
        self.lastActivity = lastActivity
        self.isStale = isStale
    }

    private enum CodingKeys: String, CodingKey {
        case url, name, ecosystemIDs, candidates, git, lastActivity, isStale
    }
}

public struct ScanOptions: Codable, Hashable, Sendable {
    public var roots: [URL]
    public var excludedPaths: [URL] = []
    /// ruleID -> enabled
    public var ruleOverrides: [String: Bool] = [:]
    public var customRules: [Rule] = []
    public var staleAfterDays: Int = 30
    public var includeGitInfo: Bool = true
    public var maxConcurrency: Int = 8

    public init(
        roots: [URL], excludedPaths: [URL] = [], ruleOverrides: [String: Bool] = [:],
        customRules: [Rule] = [], staleAfterDays: Int = 30, includeGitInfo: Bool = true,
        maxConcurrency: Int = 8
    ) {
        self.roots = roots
        self.excludedPaths = excludedPaths
        self.ruleOverrides = ruleOverrides
        self.customRules = customRules
        self.staleAfterDays = staleAfterDays
        self.includeGitInfo = includeGitInfo
        self.maxConcurrency = maxConcurrency
    }
}

public struct ScanProgress: Hashable, Sendable {
    public var directoriesVisited: Int
    public var currentPath: String
    public var projectsFound: Int
    public var bytesFound: Int64

    public init(directoriesVisited: Int, currentPath: String, projectsFound: Int, bytesFound: Int64) {
        self.directoriesVisited = directoriesVisited
        self.currentPath = currentPath
        self.projectsFound = projectsFound
        self.bytesFound = bytesFound
    }
}

public struct ScanSummary: Codable, Hashable, Sendable {
    public var projectCount: Int
    public var candidateCount: Int
    public var totalBytes: Int64
    public var startedAt: Date
    public var finishedAt: Date

    public init(projectCount: Int, candidateCount: Int, totalBytes: Int64, startedAt: Date, finishedAt: Date) {
        self.projectCount = projectCount
        self.candidateCount = candidateCount
        self.totalBytes = totalBytes
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public enum ScanEvent: Sendable {
    case progress(ScanProgress), project(Project), finished(ScanSummary)
}

public enum SafetyVerdict: Codable, Hashable, Sendable {
    case allowed, warning(String), blocked(String)

    /// A warning counts as allowed.
    public var isAllowed: Bool {
        switch self {
        case .allowed, .warning: true
        case .blocked: false
        }
    }
}

public enum CleanItemStatus: String, Codable, Sendable { case cleaned, skipped, failed, dryRun }

public struct CleanItemResult: Codable, Hashable, Sendable {
    public var candidate: Candidate
    public var status: CleanItemStatus
    public var freedBytes: Int64
    public var message: String?
    public var trashURL: URL?

    public init(
        candidate: Candidate, status: CleanItemStatus, freedBytes: Int64 = 0,
        message: String? = nil, trashURL: URL? = nil
    ) {
        self.candidate = candidate
        self.status = status
        self.freedBytes = freedBytes
        self.message = message
        self.trashURL = trashURL
    }
}

public struct CleanProgress: Hashable, Sendable {
    public var completed: Int
    public var total: Int
    public var currentTitle: String
    public var freedBytes: Int64

    public init(completed: Int, total: Int, currentTitle: String, freedBytes: Int64) {
        self.completed = completed
        self.total = total
        self.currentTitle = currentTitle
        self.freedBytes = freedBytes
    }
}

public struct CleanReport: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var mode: DeleteMode
    public var dryRun: Bool
    public var items: [CleanItemResult]
    /// Sum of items' freedBytes where status == .cleaned.
    public var freedBytes: Int64 {
        items.reduce(0) { $0 + ($1.status == .cleaned ? $1.freedBytes : 0) }
    }

    public init(
        id: UUID = UUID(), startedAt: Date, finishedAt: Date, mode: DeleteMode,
        dryRun: Bool, items: [CleanItemResult]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode
        self.dryRun = dryRun
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, finishedAt, mode, dryRun, items
    }
}

public enum CacheCategory: String, Codable, Sendable, CaseIterable {
    case xcode, android, packageManager, versionManager, container, browserTesting, ide, aiModels, misc

    public var displayName: String {
        switch self {
        case .xcode: "Xcode"
        case .android: "Android"
        case .packageManager: "Package Managers"
        case .versionManager: "Version Managers"
        case .container: "Containers"
        case .browserTesting: "Browsers & Testing"
        case .ide: "IDEs & Editors"
        case .aiModels: "AI Models"
        case .misc: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .xcode: "hammer"
        case .android: "apps.iphone"
        case .packageManager: "shippingbox"
        case .versionManager: "square.stack.3d.up"
        case .container: "cube.box"
        case .browserTesting: "globe"
        case .ide: "chevron.left.forwardslash.chevron.right"
        case .aiModels: "brain"
        case .misc: "tray.full"
        }
    }
}

public struct CacheGroup: Identifiable, Hashable, Sendable {
    /// Provider id, e.g. "xcode.derivedData"
    public var id: String
    public var title: String
    public var category: CacheCategory
    public var symbolName: String
    /// One-line explanation shown in UI.
    public var detail: String?
    public var candidates: [Candidate]
    public var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.sizeBytes } }

    public init(
        id: String, title: String, category: CacheCategory, symbolName: String,
        detail: String? = nil, candidates: [Candidate] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.symbolName = symbolName
        self.detail = detail
        self.candidates = candidates
    }
}

// MARK: - Vault

public enum SecretReason: String, Codable, Sendable {
    case ignoredMatch, untrackedMatch, alwaysCollect, uncommittedWork, contentMatch, patternMatch
}

public struct SecretFile: Identifiable, Codable, Hashable, Sendable {
    public var id: String { sourceURL.path }
    public var sourceURL: URL
    public var scanRoot: URL
    /// "<scanRoot.lastPathComponent>/<path relative to scanRoot>", e.g. "Projects/app/android/upload.jks"
    public var vaultPath: String
    public var reason: SecretReason
    /// Pattern / rule that matched.
    public var matchedRule: String
    public var sizeBytes: Int64
    public var modified: Date?
    public var git: GitInfo?
    /// Relative to git.repositoryRoot.
    public var pathInRepository: String?

    public init(
        sourceURL: URL, scanRoot: URL, vaultPath: String, reason: SecretReason,
        matchedRule: String, sizeBytes: Int64, modified: Date? = nil,
        git: GitInfo? = nil, pathInRepository: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.scanRoot = scanRoot
        self.vaultPath = vaultPath
        self.reason = reason
        self.matchedRule = matchedRule
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.git = git
        self.pathInRepository = pathInRepository
    }

    private enum CodingKeys: String, CodingKey {
        case sourceURL, scanRoot, vaultPath, reason, matchedRule, sizeBytes, modified, git, pathInRepository
    }
}

public struct VaultCollectOptions: Codable, Hashable, Sendable {
    public var roots: [URL]
    public var excludedPaths: [URL] = []
    public var extraPatterns: [String] = []
    public var alwaysCollect: [String] = ["pubspec.yaml"]
    public var includeUncommittedWork: Bool = false
    public var scanContents: Bool = false
    public var maxFileSizeBytes: Int64 = 10_485_760

    public init(
        roots: [URL], excludedPaths: [URL] = [], extraPatterns: [String] = [],
        alwaysCollect: [String] = ["pubspec.yaml"], includeUncommittedWork: Bool = false,
        scanContents: Bool = false, maxFileSizeBytes: Int64 = 10_485_760
    ) {
        self.roots = roots
        self.excludedPaths = excludedPaths
        self.extraPatterns = extraPatterns
        self.alwaysCollect = alwaysCollect
        self.includeUncommittedWork = includeUncommittedWork
        self.scanContents = scanContents
        self.maxFileSizeBytes = maxFileSizeBytes
    }
}

public enum VaultExportFormat: String, Codable, Sendable, CaseIterable { case folder, zip, encryptedImage }

public struct VaultExportRequest: Sendable {
    public var files: [SecretFile]
    /// .folder: vault directory; .zip/.encryptedImage: output file URL (.zip/.dmg)
    public var destination: URL
    public var format: VaultExportFormat
    /// Required for .encryptedImage.
    public var password: String?
    public var keepVersions: Int = 5

    public init(
        files: [SecretFile], destination: URL, format: VaultExportFormat,
        password: String? = nil, keepVersions: Int = 5
    ) {
        self.files = files
        self.destination = destination
        self.format = format
        self.password = password
        self.keepVersions = keepVersions
    }
}

public struct VaultManifestEntry: Codable, Hashable, Sendable {
    public var vaultPath: String
    public var sourcePath: String
    public var sha256: String
    public var sizeBytes: Int64
    public var modified: Date?
    public var collectedAt: Date
    public var reason: SecretReason
    public var gitRemoteURL: String?
    public var gitBranch: String?
    public var gitHeadCommit: String?
    public var pathInRepository: String?

    public init(
        vaultPath: String, sourcePath: String, sha256: String, sizeBytes: Int64,
        modified: Date? = nil, collectedAt: Date, reason: SecretReason,
        gitRemoteURL: String? = nil, gitBranch: String? = nil, gitHeadCommit: String? = nil,
        pathInRepository: String? = nil
    ) {
        self.vaultPath = vaultPath
        self.sourcePath = sourcePath
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.collectedAt = collectedAt
        self.reason = reason
        self.gitRemoteURL = gitRemoteURL
        self.gitBranch = gitBranch
        self.gitHeadCommit = gitHeadCommit
        self.pathInRepository = pathInRepository
    }
}

public struct VaultManifest: Codable, Hashable, Sendable {
    public var formatVersion: Int = 1
    public var createdAt: Date
    public var hostName: String
    public var entries: [VaultManifestEntry]

    public init(formatVersion: Int = 1, createdAt: Date, hostName: String, entries: [VaultManifestEntry]) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.hostName = hostName
        self.entries = entries
    }
}

public struct VaultExportResult: Codable, Hashable, Sendable {
    public var outputURL: URL
    public var manifest: VaultManifest
    public var copiedCount: Int
    public var unchangedCount: Int

    public init(outputURL: URL, manifest: VaultManifest, copiedCount: Int, unchangedCount: Int) {
        self.outputURL = outputURL
        self.manifest = manifest
        self.copiedCount = copiedCount
        self.unchangedCount = unchangedCount
    }
}

public struct OpenedVault: Hashable, Sendable {
    public var manifest: VaultManifest
    public var root: URL
    /// Set for encrypted images.
    public var mountPoint: URL?

    public init(manifest: VaultManifest, root: URL, mountPoint: URL? = nil) {
        self.manifest = manifest
        self.root = root
        self.mountPoint = mountPoint
    }
}

public enum RestoreStrategy: Codable, Hashable, Sendable {
    case originalPaths
    case matchGitRemote(searchRoots: [URL])
}

public struct RestoreAction: Identifiable, Codable, Hashable, Sendable {
    public var id: String { entry.vaultPath }
    public var entry: VaultManifestEntry
    public var vaultFileURL: URL
    public var destinationURL: URL
    public var destinationExists: Bool
    public var identical: Bool

    public init(
        entry: VaultManifestEntry, vaultFileURL: URL, destinationURL: URL,
        destinationExists: Bool, identical: Bool
    ) {
        self.entry = entry
        self.vaultFileURL = vaultFileURL
        self.destinationURL = destinationURL
        self.destinationExists = destinationExists
        self.identical = identical
    }

    private enum CodingKeys: String, CodingKey {
        case entry, vaultFileURL, destinationURL, destinationExists, identical
    }
}

public struct RestoreResult: Codable, Hashable, Sendable {
    public var restored: [String]
    public var skipped: [String]
    public var failed: [String: String]

    public init(restored: [String] = [], skipped: [String] = [], failed: [String: String] = [:]) {
        self.restored = restored
        self.skipped = skipped
        self.failed = failed
    }
}
