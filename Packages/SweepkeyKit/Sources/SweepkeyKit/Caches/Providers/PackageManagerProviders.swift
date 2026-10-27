import Foundation

struct PackageManagerProvider: CacheProvider {
    let id = "packageManager"

    private struct Spec {
        var rule: String
        var name: String
        var paths: [String]
        var command: (String, [String])?
        var risk: RiskLevel = .safe
        /// Overrides the default "Re-downloaded automatically by <name>" hint.
        var hint: String?
        var note: String?
    }

    private var specs: [Spec] {
        [
            Spec(rule: "npm", name: "npm", paths: [".npm/_cacache"], command: ("npm", ["cache", "clean", "--force"])),
            Spec(rule: "yarn", name: "Yarn", paths: ["Library/Caches/Yarn"], command: ("yarn", ["cache", "clean"])),
            Spec(rule: "pnpm", name: "pnpm store", paths: ["Library/pnpm/store"], command: ("pnpm", ["store", "prune"])),
            Spec(rule: "bun", name: "Bun", paths: [".bun/install/cache"], command: nil),
            Spec(rule: "pip", name: "pip", paths: ["Library/Caches/pip"], command: ("pip3", ["cache", "purge"])),
            Spec(rule: "uv", name: "uv", paths: [".cache/uv"], command: ("uv", ["cache", "clean"])),
            Spec(rule: "poetry", name: "Poetry", paths: ["Library/Caches/pypoetry"], command: nil),
            Spec(rule: "conda", name: "conda packages",
                 paths: ["miniconda3/pkgs", "anaconda3/pkgs", "miniforge3/pkgs"], command: ("conda", ["clean", "-a", "-y"])),
            Spec(rule: "cargoCache", name: "Cargo registry cache", paths: [".cargo/registry/cache"], command: nil),
            Spec(rule: "cargoSrc", name: "Cargo registry sources", paths: [".cargo/registry/src"], command: nil),
            Spec(rule: "cargoGit", name: "Cargo git checkouts", paths: [".cargo/git/checkouts"], command: nil),
            Spec(rule: "go", name: "Go module cache", paths: ["go/pkg/mod"], command: ("go", ["clean", "-modcache"])),
            Spec(rule: "maven", name: "Maven repository", paths: [".m2/repository"], command: nil, risk: .caution),
            Spec(rule: "cocoapods", name: "CocoaPods", paths: ["Library/Caches/CocoaPods"], command: ("pod", ["cache", "clean", "--all"])),
            Spec(rule: "carthage", name: "Carthage", paths: ["Library/Caches/org.carthage.CarthageKit"], command: nil),
            Spec(rule: "composer", name: "Composer", paths: ["Library/Caches/composer"], command: nil),
            Spec(rule: "gem", name: "RubyGems", paths: [".gem"], command: nil, risk: .caution,
                 hint: "Reinstall with `gem install` or `bundle install`",
                 note: "Holds gems installed with `gem install --user-install`, not only a download cache"),
            Spec(rule: "nuget", name: "NuGet packages", paths: [".nuget/packages"], command: nil),
            Spec(rule: "deno", name: "Deno", paths: ["Library/Caches/deno"], command: nil),
        ]
    }

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        var items: [CacheItem] = []
        for spec in specs where spec.rule != "conda" {
            for rel in spec.paths {
                let action = spec.command.map { ctx.action($0.0, $0.1) } ?? .delete
                items.append(CacheItem(
                    ruleID: "pm.\(spec.rule)", url: ctx.path(rel), title: spec.name, risk: spec.risk,
                    hint: spec.hint ?? "Re-downloaded automatically by \(spec.name)", note: spec.note,
                    action: action))
            }
        }
        // conda: a single command candidate covering every existing pkgs dir.
        let condaDirs = ["miniconda3/pkgs", "anaconda3/pkgs", "miniforge3/pkgs"].map { ctx.path($0) }.filter(ctx.fileExists)
        if let first = condaDirs.first {
            let total = condaDirs.reduce(Int64(0)) { $0 + ctx.sizer.allocatedSize(of: $1) }
            items.append(CacheItem(
                ruleID: "pm.conda", url: first, title: "conda packages",
                hint: "Re-downloaded automatically by conda", action: ctx.action("conda", ["clean", "-a", "-y"]),
                size: total))
        }
        // pub: flutter if available, else dart.
        let pubAction: CleanAction
        if ctx.resolve("flutter") != nil {
            pubAction = .command(executable: "flutter", arguments: ["pub", "cache", "clean", "-f"])
        } else {
            pubAction = ctx.action("dart", ["pub", "cache", "clean", "-f"])
        }
        items.append(CacheItem(
            ruleID: "pm.pub", url: ctx.path(".pub-cache"), title: "Dart/Flutter pub cache", risk: .caution,
            hint: "Re-downloaded by pub (globally activated tools are removed)", action: pubAction))
        items += await homebrew(ctx)
        return [await ctx.group("packageManager.caches", "Package manager caches", .packageManager, items: items)]
    }

    private func homebrew(_ ctx: CacheContext) async -> [CacheItem] {
        var cacheURL = ctx.path("Library/Caches/Homebrew")
        var action = CleanAction.delete
        var title = "Homebrew downloads"
        var note: String?
        if ctx.resolve("brew") != nil {
            let path = (await ctx.output("brew", ["--cache"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty { cacheURL = URL(fileURLWithPath: path) }
            action = .command(executable: "brew", arguments: ["cleanup", "--prune=all"])
            // `brew cleanup` also uninstalls outdated versions of installed formulae and casks.
            title = "Homebrew downloads and old formula versions"
            note = "Also removes old installed versions of formulae and casks"
        }
        return [CacheItem(ruleID: "pm.homebrew", url: cacheURL, title: title,
                          hint: "Re-downloaded automatically by Homebrew", note: note, action: action)]
    }
}
