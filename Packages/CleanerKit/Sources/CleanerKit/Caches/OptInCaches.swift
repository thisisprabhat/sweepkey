import Foundation

/// Cache items that stay hidden unless the user turns them on (spec §C "Misc (opt-in)").
/// The switch is `CleanerSettings.ruleOverrides[ruleID] == true`, shared by the app and the CLI.
public enum OptInCaches {
    public static let diagnosticReports = "misc.diagnosticReports"

    /// Rule ids that are off unless explicitly enabled.
    public static let ruleIDs: Set<String> = [diagnosticReports]

    public static func isEnabled(_ ruleID: String, overrides: [String: Bool]) -> Bool {
        guard ruleIDs.contains(ruleID) else { return true }
        return overrides[ruleID] == true
    }

    /// Drops disabled opt-in candidates, and groups left empty by that (info-only groups are kept).
    public static func apply(_ groups: [CacheGroup], overrides: [String: Bool]) -> [CacheGroup] {
        groups.compactMap { group in
            var copy = group
            copy.candidates = group.candidates.filter { isEnabled($0.ruleID, overrides: overrides) }
            let infoOnly = group.candidates.isEmpty && group.id.hasSuffix(CacheGroup.infoOnlySuffix)
            return copy.candidates.isEmpty && !infoOnly ? nil : copy
        }
    }
}
