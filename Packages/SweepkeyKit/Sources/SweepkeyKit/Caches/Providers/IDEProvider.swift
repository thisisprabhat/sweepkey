import Foundation

struct IDEProvider: CacheProvider {
    let id = "ide"

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        var jetbrains: [CacheItem] = []
        for (kind, base) in [("caches", "Library/Caches/JetBrains"), ("logs", "Library/Logs/JetBrains")] {
            let dirs = ctx.childDirectories(of: ctx.path(base))
            let byProduct = Dictionary(grouping: dirs, by: { productName($0.lastPathComponent) })
            for (_, versions) in byProduct {
                let newest = newestVersion(versions)
                for dir in versions {
                    jetbrains.append(CacheItem(
                        ruleID: "ide.jetbrains.\(kind)", url: dir, title: "JetBrains \(dir.lastPathComponent) \(kind)",
                        risk: dir == newest ? .caution : .safe,
                        hint: "Re-created by the IDE", note: dir == newest ? "Newest version, likely in use" : nil))
                }
            }
        }

        var extensions: [CacheItem] = []
        for root in [".vscode", ".cursor", ".windsurf"] {
            let dirs = ctx.childDirectories(of: ctx.path("\(root)/extensions"))
            let byID = Dictionary(grouping: dirs, by: { extensionID($0.lastPathComponent) })
            for (extID, versions) in byID where versions.count > 1 {
                let newest = newestVersion(versions)
                for dir in versions where dir != newest {
                    extensions.append(CacheItem(
                        ruleID: "ide.extensions.\(root.dropFirst())", url: dir,
                        title: "\(extID) (old version \(dir.lastPathComponent))",
                        hint: "Superseded by a newer installed version"))
                }
            }
        }

        var appCaches: [CacheItem] = []
        for app in ["Code", "Cursor"] {
            for sub in ["Cache", "CachedData", "CachedExtensionVSIXs"] {
                appCaches.append(CacheItem(
                    ruleID: "ide.\(app.lowercased()).\(sub)", url: ctx.path("Library/Application Support/\(app)/\(sub)"),
                    title: "\(app) \(sub)", hint: "Re-created by \(app)"))
            }
        }
        return [
            await ctx.group("ide.jetbrains", "JetBrains caches & logs", .ide, items: jetbrains),
            await ctx.group("ide.extensions", "Old editor extension versions", .ide, items: extensions),
            await ctx.group("ide.appCaches", "VS Code & Cursor caches", .ide, items: appCaches),
        ]
    }

    /// "IntelliJIdea2024.1" -> "IntelliJIdea"
    private func productName(_ name: String) -> String {
        var s = Substring(name)
        while let last = s.last, last.isNumber || last == "." { s = s.dropLast() }
        return String(s)
    }

    /// "ms-python.python-2024.1.0-darwin-arm64" -> "ms-python.python"
    private func extensionID(_ name: String) -> String {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        // Split at the last version-like segment (digit-led, contains "."), never the first segment (publisher).
        guard let idx = parts.indices.last(where: { $0 > 0 && parts[$0].first?.isNumber == true && parts[$0].contains(".") })
        else { return name }
        return parts[..<idx].joined(separator: "-")
    }
}
