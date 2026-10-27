import Foundation

struct VersionManagerProvider: CacheProvider {
    let id = "versionManager"

    private struct Spec {
        var rule: String
        var name: String
        /// Each pattern is a relative path where `*` matches one directory level of "tool" folders
        /// (those parents are resolved first); the version directories live under the resolved parents.
        var parents: [String]
        /// When true, `parents` are folders whose children are tool folders (e.g. ~/.sdkman/candidates).
        var nested = false
        var reinstall: String
    }

    private let specs: [Spec] = [
        Spec(rule: "nvm", name: "nvm Node", parents: [".nvm/versions/node"], reinstall: "nvm install <version>"),
        Spec(rule: "fnm", name: "fnm Node",
             parents: [".local/share/fnm/node-versions", "Library/Application Support/fnm/node-versions"],
             reinstall: "fnm install <version>"),
        Spec(rule: "volta", name: "Volta Node", parents: [".volta/tools/image/node"], reinstall: "volta install node@<version>"),
        Spec(rule: "pyenv", name: "pyenv Python", parents: [".pyenv/versions"], reinstall: "pyenv install <version>"),
        Spec(rule: "rustup", name: "rustup toolchain", parents: [".rustup/toolchains"], reinstall: "rustup toolchain install <name>"),
        Spec(rule: "sdkman", name: "SDKMAN", parents: [".sdkman/candidates"], nested: true, reinstall: "sdk install <candidate> <version>"),
        Spec(rule: "fvm", name: "fvm Flutter", parents: ["fvm/versions", ".fvm/versions"], reinstall: "fvm install <version>"),
        Spec(rule: "asdf", name: "asdf", parents: [".asdf/installs"], nested: true, reinstall: "asdf install <tool> <version>"),
        Spec(rule: "mise", name: "mise", parents: [".local/share/mise/installs"], nested: true, reinstall: "mise install <tool>@<version>"),
    ]

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        var groups: [CacheGroup] = []
        for spec in specs {
            var items: [CacheItem] = []
            for parent in spec.parents {
                let root = ctx.path(parent)
                let toolDirs = spec.nested ? ctx.childDirectories(of: root) : [root]
                for tool in toolDirs {
                    let versions = ctx.children(of: tool).filter { $0.lastPathComponent != "current" && $0.isDirectory }
                    let newest = newestVersion(versions)
                    for version in versions {
                        let label = spec.nested ? "\(tool.lastPathComponent) \(version.lastPathComponent)" : version.lastPathComponent
                        items.append(CacheItem(
                            ruleID: "versionManager.\(spec.rule)", url: version, title: "\(spec.name) \(label)",
                            risk: version == newest ? .danger : .caution,
                            hint: "Reinstall with `\(spec.reinstall)`",
                            note: version == newest ? "Newest installed version, likely in use" : nil))
                    }
                }
            }
            groups.append(await ctx.group("versionManager.\(spec.rule)", spec.name + " versions", .versionManager, items: items))
        }
        return groups
    }
}
