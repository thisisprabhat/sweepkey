import Foundation

public extension URL {
    /// True if this URL itself is a symbolic link (not followed).
    var isSymlink: Bool {
        (try? resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
    }

    /// True if this URL is a directory (symlinks are not followed: a symlink to a directory is false).
    var isDirectory: Bool {
        guard let v = try? resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        if v.isSymbolicLink == true { return false }
        return v.isDirectory ?? false
    }

    /// True if this URL is strictly inside `ancestor`, comparing standardized path components
    /// (resolves `..` and `.`; not a string-prefix check). Strict: a URL is not its own
    /// descendant. Does not resolve symlinks.
    func isDescendant(of ancestor: URL) -> Bool {
        let a = ancestor.standardizedFileURL.pathComponents
        let b = standardizedFileURL.pathComponents
        return b.count > a.count && Array(b.prefix(a.count)) == a
    }
}

/// Modification date of the item at `url` (symlinks not followed), or nil.
public func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

public enum Glob {
    /// fnmatch semantics for `*`, `?` and `[...]` on a single path segment.
    public static func matches(_ pattern: String, _ name: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}
