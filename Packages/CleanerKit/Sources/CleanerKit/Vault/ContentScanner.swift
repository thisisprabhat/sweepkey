import Foundation

public struct ContentScanner: Sendable {
    private struct Rule: Sendable {
        let name: String
        let regex: NSRegularExpression
    }

    private let rules: [Rule]

    public init() {
        let defs: [(String, String)] = [
            ("AWS access key", "AKIA[0-9A-Z]{16}"),
            ("GitHub token", "gh[pousr]_[A-Za-z0-9]{36,}"),
            ("Stripe live key", "sk_live_[0-9a-zA-Z]{24,}"),
            ("OpenAI-style key", "sk-[A-Za-z0-9_-]{32,}"),
            ("Slack token", "xox[baprs]-[A-Za-z0-9-]{10,}"),
            ("Google API key", "AIza[0-9A-Za-z_-]{35}"),
            ("Private key", "-----BEGIN [A-Z ]*PRIVATE KEY-----"),
        ]
        rules = defs.compactMap { name, pattern in
            (try? NSRegularExpression(pattern: pattern)).map { Rule(name: name, regex: $0) }
        }
    }

    /// Returns the name of the first rule that matches, never the matched value.
    /// Skips binary files (NUL in the first 8 KB) and files larger than `maxBytes`.
    public func scan(_ url: URL, maxBytes: Int64) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = (attrs[.size] as? NSNumber)?.int64Value, size <= maxBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if data.prefix(8192).contains(0) { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let range = NSRange(text.startIndex..., in: text)
        for rule in rules where rule.regex.firstMatch(in: text, range: range) != nil {
            return rule.name
        }
        return nil
    }
}
