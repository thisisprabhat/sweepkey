import Foundation

/// A not-yet-sized candidate description built by providers.
struct CacheItem: Sendable {
    var ruleID: String
    var url: URL
    var title: String
    var risk: RiskLevel = .safe
    var hint: String?
    var note: String?
    var action: CleanAction = .delete
    /// When set, used instead of measuring `url` (the item is then kept even if `url` is missing).
    var size: Int64?
}

extension CacheContext {
    func path(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }

    /// Sorted children of a directory (files and folders), skipping `.DS_Store`.
    func children(of url: URL) -> [URL] {
        // Build children from names so paths stay under `url` as given (no /var -> /private/var rewrite).
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0 != ".DS_Store" }.sorted()
            .map { url.appendingPathComponent($0) }
    }

    func childDirectories(of url: URL) -> [URL] {
        children(of: url).filter { $0.isDirectory }
    }

    /// stdout of a successful command (short timeout), or nil on any failure.
    func output(_ executable: String, _ arguments: [String], timeout: Duration = .seconds(10)) async -> String? {
        guard resolve(executable) != nil else { return nil }
        guard let result = try? await shell.run(
            executable, arguments: arguments, currentDirectory: nil, input: nil, timeout: timeout),
            result.succeeded
        else { return nil }
        return result.stdout
    }

    /// `.command` when the tool is installed, otherwise `.delete` of the path.
    func action(_ executable: String, _ arguments: [String]) -> CleanAction {
        resolve(executable) != nil ? .command(executable: executable, arguments: arguments) : .delete
    }

    /// Sizes the items and turns them into candidates. Items whose path is missing (and have no size override) are dropped.
    func candidates(from items: [CacheItem], category: CacheCategory) async -> [Candidate] {
        let live = items.filter { $0.size != nil || fileExists($0.url) }
        let toMeasure = Array(Set(live.filter { $0.size == nil }.map(\.url)))
        let sizes = await sizer.allocatedSizes(of: toMeasure)
        return live.map { item in
            Candidate(
                id: "\(item.ruleID)|\(item.url.path)", url: item.url, kind: .globalCache,
                title: item.title, ecosystemID: category.rawValue, ruleID: item.ruleID,
                risk: item.risk, sizeBytes: item.size ?? sizes[item.url] ?? 0,
                lastModified: modificationDate(item.url), regenerateHint: item.hint,
                note: item.note, action: item.action)
        }
    }

    func group(
        _ id: String, _ title: String, _ category: CacheCategory, detail: String? = nil,
        items: [CacheItem]
    ) async -> CacheGroup {
        CacheGroup(
            id: id, title: title, category: category, symbolName: category.symbolName,
            detail: detail, candidates: await candidates(from: items, category: category))
    }
}

// MARK: - Versions

func versionComponents(_ string: String) -> [Int] {
    var result: [Int] = []
    var current = ""
    for ch in string {
        if ch.isASCII, ch.isNumber {
            current.append(ch)
        } else if !current.isEmpty {
            result.append(Int(current) ?? 0)
            current = ""
        }
    }
    if !current.isEmpty { result.append(Int(current) ?? 0) }
    return result
}

/// Numeric component-wise comparison (8.10 > 8.9). Missing trailing components count as 0.
func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}

/// The newest URL by numeric version in `key(url)` (default: last path component),
/// falling back to modification date when names carry no version or tie.
func newestVersion(_ urls: [URL], key: (URL) -> String = { $0.lastPathComponent }) -> URL? {
    guard !urls.isEmpty else { return nil }
    let comps = urls.map { versionComponents(key($0)) }
    let allVersioned = comps.allSatisfy { !$0.isEmpty }
    var best = 0
    for i in 1..<urls.count {
        var cmp = 0
        if allVersioned { cmp = compareVersions(comps[i], comps[best]) }
        if cmp == 0 {
            let a = modificationDate(urls[i]) ?? .distantPast
            let b = modificationDate(urls[best]) ?? .distantPast
            cmp = a == b ? 0 : (a > b ? 1 : -1)
        }
        if cmp > 0 { best = i }
    }
    return urls[best]
}

// MARK: - Human sizes

/// Parses strings like "1.2GB", "1.2GB (40%)", "4.7 GB", "512kB". Decimal units, as Docker and Ollama print.
func parseHumanSize(_ string: String) -> Int64 {
    var s = string.trimmingCharacters(in: .whitespaces)
    if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]) }
    s = s.replacingOccurrences(of: " ", with: "")
    let number = s.prefix { $0.isNumber || $0 == "." }
    guard let value = Double(number) else { return 0 }
    let multipliers: [String: Double] = [
        "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
        "KIB": 1024, "MIB": 1_048_576, "GIB": 1_073_741_824, "TIB": 1_099_511_627_776,
    ]
    let unit = String(s.dropFirst(number.count)).uppercased()
    return Int64(value * (multipliers[unit] ?? 1))
}
