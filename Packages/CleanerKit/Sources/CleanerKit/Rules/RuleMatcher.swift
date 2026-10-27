import Foundation

public struct RuleMatch: Sendable {
    public let rule: Rule
    /// Existing target paths resolved from `rule.target`.
    public let targets: [URL]
    /// Marker paths that exist in the directory (used for activity dates).
    public let markers: [URL]
}

public enum RuleMatcher {
    /// Returns rules whose marker exists in `directory` and which resolve to at least one existing target.
    /// `childNames` are the directory's immediate entries.
    public static func matches(in directory: URL, childNames: [String], rules: [Rule]) -> [RuleMatch] {
        let names = Set(childNames)
        var result: [RuleMatch] = []
        for rule in rules {
            let markers = existingMarkers(rule.markers, in: directory, names: names)
            if markers.isEmpty { continue }
            let targets = resolveTargets(rule.target, in: directory, names: names)
            if targets.isEmpty { continue }
            result.append(RuleMatch(rule: rule, targets: targets, markers: markers))
        }
        return result
    }

    private static func isGlob(_ s: String) -> Bool { s.contains { "*?[".contains($0) } }

    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func existingMarkers(_ markers: [String], in dir: URL, names: Set<String>) -> [URL] {
        var found: [URL] = []
        for m in markers {
            if m.contains("/") {
                let u = dir.appendingPathComponent(m)
                if exists(u) { found.append(u) }
            } else if isGlob(m) {
                for n in names.sorted() where Glob.matches(m, n) { found.append(dir.appendingPathComponent(n)) }
            } else if names.contains(m) {
                found.append(dir.appendingPathComponent(m))
            }
        }
        return found
    }

    private static func resolveTargets(_ target: String, in dir: URL, names: Set<String>) -> [URL] {
        let parts = target.split(separator: "/").map(String.init)
        guard let last = parts.last, !parts.contains(".."), !target.hasPrefix("/") else { return [] }
        let parentParts = parts.dropLast()
        let parent = parentParts.reduce(dir) { $0.appendingPathComponent($1) }
        if isGlob(last) {
            let siblings: [String]
            if parentParts.isEmpty {
                siblings = names.sorted()
            } else {
                siblings = ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []).sorted()
            }
            return siblings.filter { Glob.matches(last, $0) }.map { parent.appendingPathComponent($0) }
        }
        if parentParts.isEmpty { return names.contains(last) ? [parent.appendingPathComponent(last)] : [] }
        let u = parent.appendingPathComponent(last)
        return exists(u) ? [u] : []
    }
}
