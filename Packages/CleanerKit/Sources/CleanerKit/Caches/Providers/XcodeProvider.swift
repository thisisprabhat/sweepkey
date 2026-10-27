import Foundation

struct XcodeProvider: CacheProvider {
    let id = "xcode"
    private let hint = "Rebuilt or re-downloaded by Xcode when needed"

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        let dev = "Library/Developer"
        var groups: [CacheGroup] = []

        let derived = ctx.childDirectories(of: ctx.path("\(dev)/Xcode/DerivedData")).map {
            CacheItem(ruleID: "xcode.derivedData", url: $0, title: $0.lastPathComponent,
                      hint: "Rebuilt by Xcode on next build")
        }
        groups.append(await ctx.group("xcode.derivedData", "Xcode DerivedData", .xcode, items: derived))

        var archives: [CacheItem] = []
        let archivesRoot = ctx.path("\(dev)/Xcode/Archives")
        for child in ctx.children(of: archivesRoot) {
            let nested = child.pathExtension == "xcarchive" ? [child] : ctx.children(of: child).filter { $0.pathExtension == "xcarchive" }
            for archive in nested {
                archives.append(CacheItem(
                    ruleID: "xcode.archives", url: archive, title: archive.deletingPathExtension().lastPathComponent,
                    risk: .danger, hint: "Cannot be regenerated without the original source",
                    note: "Contains dSYMs needed to symbolicate crash reports"))
            }
        }
        groups.append(await ctx.group("xcode.archives", "Xcode Archives", .xcode, items: archives))

        var support: [CacheItem] = []
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            for version in ctx.children(of: ctx.path("\(dev)/Xcode/\(platform) DeviceSupport")) {
                support.append(CacheItem(
                    ruleID: "xcode.deviceSupport.\(platform)", url: version,
                    title: "\(platform) DeviceSupport \(version.lastPathComponent)",
                    hint: "Re-created when the device is next connected"))
            }
        }
        groups.append(await ctx.group("xcode.deviceSupport", "Xcode Device Support", .xcode, items: support))

        var sims: [CacheItem] = [
            CacheItem(ruleID: "xcode.simulatorCaches", url: ctx.path("\(dev)/CoreSimulator/Caches"),
                      title: "CoreSimulator caches", hint: hint),
            CacheItem(ruleID: "xcode.previews", url: ctx.path("\(dev)/Xcode/UserData/Previews"),
                      title: "SwiftUI Previews", hint: "Regenerated when previews run"),
        ]
        sims += await unavailableSimulators(ctx)
        sims += await runtimes(ctx)
        groups.append(await ctx.group("xcode.simulators", "Simulators", .xcode, items: sims))
        return groups
    }

    private func unavailableSimulators(_ ctx: CacheContext) async -> [CacheItem] {
        guard let out = await ctx.output("xcrun", ["simctl", "list", "devices", "unavailable", "-j"]),
              let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let devices = json["devices"] as? [String: Any],
              devices.values.contains(where: { ($0 as? [Any])?.isEmpty == false })
        else { return [] }
        return [CacheItem(
            ruleID: "xcode.unavailableSimulators", url: ctx.path("Library/Developer/CoreSimulator/Devices"),
            title: "Unavailable simulators", hint: "Recreate simulators in Xcode if needed",
            note: "Size unknown until cleaned",
            action: .command(executable: "xcrun", arguments: ["simctl", "delete", "unavailable"]), size: 0)]
    }

    private func runtimes(_ ctx: CacheContext) async -> [CacheItem] {
        guard let out = await ctx.output("xcrun", ["simctl", "runtime", "list", "-j"]),
              let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        else { return [] }
        var items: [CacheItem] = []
        for (key, value) in json.sorted(by: { $0.key < $1.key }) {
            guard let info = value as? [String: Any] else { continue }
            let identifier = (info["identifier"] as? String) ?? key
            let platform = (info["platformIdentifier"] as? String)?.split(separator: ".").last.map(String.init)
                ?? (info["runtimeIdentifier"] as? String) ?? "Simulator"
            let version = (info["version"] as? String) ?? ""
            let size = (info["sizeBytes"] as? NSNumber)?.int64Value ?? 0
            items.append(CacheItem(
                ruleID: "xcode.runtime.\(identifier)",
                url: ctx.path("Library/Developer/CoreSimulator/Volumes"),
                title: "Simulator runtime \(platform) \(version)".trimmingCharacters(in: .whitespaces),
                risk: .caution, hint: "Re-download from Xcode Settings > Platforms",
                action: .command(executable: "xcrun", arguments: ["simctl", "runtime", "delete", identifier]),
                size: size))
        }
        return items
    }
}
