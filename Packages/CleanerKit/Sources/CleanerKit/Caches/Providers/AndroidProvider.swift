import Foundation

struct AndroidProvider: CacheProvider {
    let id = "android"

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        var gradle: [CacheItem] = [
            CacheItem(ruleID: "android.gradleCaches", url: ctx.path(".gradle/caches"),
                      title: "Gradle caches", hint: "Re-downloaded automatically by Gradle"),
        ]
        let dists = ctx.childDirectories(of: ctx.path(".gradle/wrapper/dists"))
        let newestDist = newestVersion(dists)
        for dist in dists {
            gradle.append(CacheItem(
                ruleID: "android.gradleWrapper", url: dist, title: "Gradle \(dist.lastPathComponent)",
                risk: dist == newestDist ? .caution : .safe,
                hint: "Re-downloaded by the Gradle wrapper"))
        }
        gradle.append(CacheItem(ruleID: "android.cache", url: ctx.path(".android/cache"),
                                title: "Android cache", hint: "Re-created by Android tools"))

        let sdk = sdkRoot(ctx)
        var sdkItems: [CacheItem] = []
        sdkItems += sdkKind(ctx, sdk, "build-tools", depth: 1, ruleID: "android.sdk.buildTools", label: "Build-tools")
        sdkItems += sdkKind(ctx, sdk, "ndk", depth: 1, ruleID: "android.sdk.ndk", label: "NDK")
        sdkItems += sdkKind(ctx, sdk, "system-images", depth: 3, ruleID: "android.sdk.systemImages", label: "System image")
        sdkItems += sdkKind(ctx, sdk, "platforms", depth: 1, ruleID: "android.sdk.platforms", label: "Platform")

        let avds = ctx.children(of: ctx.path(".android/avd")).filter { $0.pathExtension == "avd" }.map {
            CacheItem(ruleID: "android.avd", url: $0, title: "AVD \($0.deletingPathExtension().lastPathComponent)",
                      risk: .danger, hint: "Recreate the emulator in Android Studio",
                      note: "Emulator data and snapshots are lost")
        }
        return [
            await ctx.group("android.gradle", "Gradle & Android caches", .android, items: gradle),
            await ctx.group("android.sdk", "Android SDK components", .android, items: sdkItems),
            await ctx.group("android.avd", "Android emulators", .android, items: avds),
        ]
    }

    private func sdkRoot(_ ctx: CacheContext) -> URL {
        if let env = ctx.environment("ANDROID_HOME") ?? ctx.environment("ANDROID_SDK_ROOT"), !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return ctx.path("Library/Android/sdk")
    }

    /// Per-version directories `depth` levels under `<sdk>/<kind>`; the newest is danger, the rest caution.
    private func sdkKind(
        _ ctx: CacheContext, _ sdk: URL, _ kind: String, depth: Int, ruleID: String, label: String
    ) -> [CacheItem] {
        let base = sdk.appendingPathComponent(kind)
        var level = [base]
        for _ in 0..<depth { level = level.flatMap { ctx.childDirectories(of: $0) } }
        let newest = newestVersion(level) { url in
            String(url.path.dropFirst(base.path.count))
        }
        return level.map { url in
            let relative = String(url.path.dropFirst(base.path.count + 1))
            return CacheItem(
                ruleID: ruleID, url: url, title: "\(label) \(relative)",
                risk: url == newest ? .danger : .caution,
                hint: "Re-install with the Android SDK Manager",
                note: url == newest ? "Newest installed version" : nil)
        }
    }
}
