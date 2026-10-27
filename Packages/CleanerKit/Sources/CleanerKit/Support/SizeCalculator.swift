import Foundation

public struct SizeCalculator: Sendable {
    public init() {}

    /// Recursive allocated size. Never follows symlinks; hard links counted once per call; missing path = 0.
    public func allocatedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey,
            .isSymbolicLinkKey, .fileResourceIdentifierKey, .linkCountKey,
        ]
        let keySet = Set(keys)
        var seen = Set<AnyHashable>()
        var total: Int64 = 0

        func size(of u: URL) -> (Int64, isDir: Bool) {
            guard let v = try? u.resourceValues(forKeys: keySet) else { return (0, false) }
            let isLink = v.isSymbolicLink ?? false
            if !isLink, (v.linkCount ?? 1) > 1, !(v.isDirectory ?? false),
               let id = v.fileResourceIdentifier as? AnyHashable {
                if !seen.insert(id).inserted { return (0, false) }
            }
            let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            return (s, !isLink && (v.isDirectory ?? false))
        }

        guard fm.fileExists(atPath: url.path) || url.isSymlink else { return 0 }
        let (rootSize, isDir) = size(of: url)
        total += rootSize
        guard isDir else { return total }

        guard let en = fm.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return total }
        for case let item as URL in en {
            let (s, _) = size(of: item)
            total += s
        }
        return total
    }

    public func allocatedSizes(of urls: [URL], maxConcurrency: Int = 8) async -> [URL: Int64] {
        let limit = max(1, maxConcurrency)
        var result: [URL: Int64] = [:]
        await withTaskGroup(of: (URL, Int64).self) { group in
            var iterator = urls.makeIterator()
            var running = 0
            func addNext(_ group: inout TaskGroup<(URL, Int64)>) {
                if let u = iterator.next() {
                    group.addTask { (u, SizeCalculator().allocatedSize(of: u)) }
                    running += 1
                }
            }
            for _ in 0..<limit { addNext(&group) }
            while let (u, s) = await group.next() {
                running -= 1
                result[u] = s
                addNext(&group)
            }
        }
        return result
    }
}
