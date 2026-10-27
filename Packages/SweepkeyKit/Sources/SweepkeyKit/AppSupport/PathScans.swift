import Foundation

/// Rules for scans of a single folder requested from outside the window (`sweepkey://scan?path=`
/// and the Services menu).
public enum PathScanPolicy {
    public enum Decision: Equatable, Sendable {
        /// Never scanned this way.
        case reject(String)
        /// Already a scan root or inside one: scan straight away.
        case scan
        /// Not covered by the scan roots: ask in the app first.
        case confirm
    }

    private static let systemPrefixes = [
        "/System", "/usr", "/bin", "/sbin", "/Library", "/Applications", "/private", "/etc", "/var", "/dev", "/cores", "/opt",
    ]
    /// Temporary folders live under system prefixes but hold user data.
    private static let allowedPrefixes = ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]

    public static func decide(_ url: URL, scanRoots: [URL], home: URL) -> Decision {
        let path = resolved(url)
        let key = path.path.lowercased()
        if key == "/" { return .reject("Scanning the whole disk is not supported.") }
        if key == resolved(home).path.lowercased() {
            return .reject("Scanning your whole home folder this way is not supported. Add it in Settings instead.")
        }
        // /Volumes/<disk>/... is fine; /Volumes itself is not a project folder.
        if key == "/volumes" { return .reject("Not a project folder.") }
        if !allowedPrefixes.contains(where: { key.hasPrefix($0) }) {
            for prefix in systemPrefixes {
                let p = prefix.lowercased()
                if key == p || key.hasPrefix(p + "/") { return .reject("System folders are never scanned.") }
            }
        }
        let comps = path.pathComponents.map { $0.lowercased() }
        let covered = scanRoots.map(resolved).contains { root in
            let r = root.pathComponents.map { $0.lowercased() }
            return comps.count >= r.count && Array(comps.prefix(r.count)) == r
        }
        return covered ? .scan : .confirm
    }

    private static func resolved(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
}

/// Merging partial scans into the full result list without losing the rest of it.
public enum ScanMerge {
    /// Replaces the projects at or under `roots` with `found` and keeps every other project.
    /// Largest first.
    public static func merge(existing: [Project], found: [Project], replacing roots: [URL]) -> [Project] {
        let resolvedRoots = AppLogic.resolve(roots)
        var kept = existing.filter { project in
            !resolvedRoots.contains { project.url == $0 || project.url.isDescendant(of: $0) }
        }
        let keptIDs = Set(kept.map(\.id))
        kept.append(contentsOf: found.filter { !keptIDs.contains($0.id) })
        return kept.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Only projects inside the configured scan roots belong in the saved scan cache; a one-off
    /// folder scan elsewhere is shown for the session but never saved over the full scan.
    public static func persistable(_ projects: [Project], scanRoots: [URL]) -> [Project] {
        let roots = AppLogic.resolve(scanRoots)
        return projects.filter { project in
            let url = project.url.standardizedFileURL.resolvingSymlinksInPath()
            return roots.contains { url == $0 || url.isDescendant(of: $0) }
        }
    }
}
