import SweepkeyKit
import Foundation

extension SecretReason {
    var title: String {
        switch self {
        case .ignoredMatch: "Git-ignored"
        case .untrackedMatch: "Untracked"
        case .alwaysCollect: "Always collect"
        case .uncommittedWork: "Uncommitted"
        case .contentMatch: "Key in content"
        case .patternMatch: "Name pattern"
        }
    }
}

/// A row in the findings table: a project group or one file.
struct FindingRow: Identifiable, Hashable {
    let id: String
    let name: String
    let file: SecretFile?
    let files: [SecretFile]
    var children: [FindingRow]?

    var sizeBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }
    var reasonTitle: String { file?.reason.title ?? "" }

    static func grouped(_ findings: [SecretFile]) -> [FindingRow] {
        let groups = Dictionary(grouping: findings) { $0.git?.repositoryRoot.lastPathComponent ?? "No repository" }
        return groups.keys.sorted().map { key in
            let files = groups[key] ?? []
            return FindingRow(
                id: "group|\(key)", name: key, file: nil, files: files,
                children: files.map {
                    FindingRow(id: $0.id, name: $0.pathInRepository ?? $0.sourceURL.lastPathComponent,
                               file: $0, files: [$0], children: nil)
                })
        }
    }
}

extension SecretFile {
    /// Logo (when the file belongs to one tool) and SF Symbol for the vault list.
    var icon: (logo: String?, symbol: String) {
        let name = sourceURL.lastPathComponent.lowercased()
        let ext = sourceURL.pathExtension.lowercased()
        switch true {
        case name == "pubspec.yaml": return ("flutter", "doc.text")
        case name == ".npmrc" || name == ".yarnrc" || name == ".yarnrc.yml": return ("npm", "doc.text")
        case name == "local.properties" || name == "key.properties" || name.hasSuffix(".gradle.properties"):
            return ("android", "gearshape")
        case name.hasPrefix(".env") || name.hasSuffix(".env"): return (nil, "list.bullet.rectangle")
        case ["jks", "keystore", "p12", "pfx", "p8", "pem", "key", "der", "cer", "crt"].contains(ext):
            return (nil, "key.fill")
        case ext == "mobileprovision" || ext == "provisionprofile": return ("xcode", "checkmark.seal")
        case name.contains("google-services") || name.contains("googleservice-info"): return (nil, "flame")
        case ["json", "yaml", "yml", "toml", "plist", "xcconfig"].contains(ext): return (nil, "curlybraces")
        default: return (nil, "doc")
        }
    }
}
