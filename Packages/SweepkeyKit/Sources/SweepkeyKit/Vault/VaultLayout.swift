import CryptoKit
import Foundation

/// The vault's mirror layout: `<root folder name>/<path relative to the scan root>`.
///
/// Two scan roots can share a folder name (`~/Projects` and `/Volumes/Work/Projects`). The first
/// root, in the given (settings) order, keeps its plain name, so existing vaults are unchanged.
/// A later root whose name collides gets `<name>-<first 8 hex of sha256(resolved root path)>`.
/// Names are compared case-insensitively, as on a default APFS volume.
public enum VaultLayout {
    /// Vault folder names for `roots`, aligned with the input. Roots are resolved first, and the
    /// same resolved root always gets the same name.
    public static func rootNames(_ roots: [URL]) -> [String] {
        var byPath: [String: String] = [:]
        var taken = Set<String>()
        return roots.map { raw in
            let root = resolved(raw)
            if let known = byPath[root.path] { return known }
            let plain = root.lastPathComponent
            let name = taken.contains(plain.lowercased()) ? "\(plain)-\(shortHash(root.path))" : plain
            taken.insert(name.lowercased())
            byPath[root.path] = name
            return name
        }
    }

    /// The first root (in order) that contains `source`, with its vault folder name.
    public static func root(containing source: URL, scanRoots: [URL]) -> (root: URL, name: String)? {
        let file = resolved(source)
        let names = rootNames(scanRoots)
        for (raw, name) in zip(scanRoots, names) {
            let root = resolved(raw)
            if file.isDescendant(of: root) { return (root, name) }
        }
        return nil
    }

    /// `<root name>/<relative path>` for `source` under `root`.
    public static func vaultPath(for source: URL, root: URL, rootName: String) -> String {
        let base = resolved(root).pathComponents
        let comps = resolved(source).pathComponents
        guard comps.count > base.count, Array(comps.prefix(base.count)) == base else {
            return rootName + "/" + source.lastPathComponent
        }
        return ([rootName] + comps.dropFirst(base.count)).joined(separator: "/")
    }

    /// Re-roots files collected from a narrower root (a project folder) onto the scan-root layout
    /// that a full collection uses, so every export path writes the same vault paths. Files under
    /// none of `scanRoots` keep their vault path.
    public static func rebase(_ files: [SecretFile], scanRoots: [URL]) -> [SecretFile] {
        guard !scanRoots.isEmpty else { return files }
        let names = rootNames(scanRoots)
        let roots = scanRoots.map(resolved)
        return files.map { file in
            let source = resolved(file.sourceURL)
            guard let index = roots.firstIndex(where: { source.isDescendant(of: $0) }) else { return file }
            var copy = file
            copy.scanRoot = roots[index]
            copy.vaultPath = vaultPath(for: source, root: roots[index], rootName: names[index])
            return copy
        }
    }

    static func shortHash(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func resolved(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
}
