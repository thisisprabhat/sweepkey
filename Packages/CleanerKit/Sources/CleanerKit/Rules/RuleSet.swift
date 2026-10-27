import Foundation

public struct RuleSet: Sendable {
    public var rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public enum LoadError: Error { case resourceMissing }

    /// The built-in rules shipped in `Resources/rules.json`.
    public static func bundled() throws -> [Rule] {
        // Shipped binaries: resolve beside the real executable first. `Bundle.module` traps when
        // its bundle is missing, so it is only consulted when that lookup fails (dev and tests).
        guard let url = RuleResources.rulesURL()
            ?? Bundle.module.url(forResource: "rules", withExtension: "json")
        else {
            throw LoadError.resourceMissing
        }
        return try JSONDecoder().decode([Rule].self, from: Data(contentsOf: url))
    }

    /// Enabled rules only (an override wins over `enabledByDefault`), with custom rules appended.
    /// A custom rule whose id equals a built-in replaces it.
    public func effectiveRules(overrides: [String: Bool], custom: [Rule]) -> [Rule] {
        let customIDs = Set(custom.map(\.id))
        return (rules.filter { !customIDs.contains($0.id) } + custom).filter { overrides[$0.id] ?? $0.enabledByDefault }
    }

    /// Human-readable problems with a rule; empty when it is valid.
    public func validate(_ rule: Rule) -> [String] {
        var problems: [String] = []
        if rule.id.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Rule id is empty.") }
        let target = rule.target.trimmingCharacters(in: .whitespaces)
        if target.isEmpty {
            problems.append("Target is empty.")
        } else {
            if target.hasPrefix("/") || target.hasPrefix("~") { problems.append("Target must be a relative path.") }
            if target.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                problems.append("Target must not contain '..'.")
            }
            if target.split(separator: "/").allSatisfy({ $0 == "." }) { problems.append("Target must name a folder inside the project.") }
        }
        let markers = rule.markers.map { $0.trimmingCharacters(in: .whitespaces) }
        if markers.isEmpty || markers.contains(where: \.isEmpty) {
            problems.append("At least one non-empty marker is required.")
        }
        if markers.contains(where: { $0.hasPrefix("/") || $0.split(separator: "/").contains("..") }) {
            problems.append("Markers must be relative paths without '..'.")
        }
        return problems
    }
}
