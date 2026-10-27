import Foundation

struct ContainerProvider: CacheProvider {
    let id = "container"

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        guard ctx.resolve("docker") != nil,
              await ctx.output("docker", ["info"], timeout: .seconds(5)) != nil,
              let df = await ctx.output("docker", ["system", "df", "--format", "{{json .}}"])
        else { return [] }

        var reclaimable: [String: Int64] = [:]
        for line in df.split(whereSeparator: \.isNewline) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["Type"] as? String, let rec = obj["Reclaimable"] as? String
            else { continue }
            reclaimable[type] = parseHumanSize(rec)
        }

        func item(_ type: String, _ rule: String, _ title: String, _ args: [String],
                  risk: RiskLevel = .safe, hint: String, note: String? = nil) -> CacheItem? {
            guard let size = reclaimable[type], size > 0 else { return nil }
            return CacheItem(
                ruleID: "container.\(rule)", url: URL(string: "docker:///\(rule)")!, title: title,
                risk: risk, hint: hint, note: note,
                action: .command(executable: "docker", arguments: args), size: size)
        }
        let items = [
            item("Build Cache", "buildCache", "Docker build cache", ["builder", "prune", "-af"],
                 hint: "Rebuilt on next docker build"),
            item("Images", "images", "Unused Docker images", ["image", "prune", "-af"],
                 hint: "Pulled or rebuilt when needed"),
            item("Containers", "containers", "Stopped containers", ["container", "prune", "-f"],
                 hint: "Recreate with docker run"),
            item("Local Volumes", "volumes", "Unused Docker volumes", ["volume", "prune", "-af"],
                 risk: .danger, hint: "Volume data cannot be regenerated", note: "May contain database data"),
        ].compactMap { $0 }

        var groups = [await ctx.group("container.docker", "Docker", .container,
                                      detail: "Reclaimable space reported by docker system df", items: items)]

        let raw = ctx.path("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        if ctx.fileExists(raw) {
            let size = ctx.sizer.allocatedSize(of: raw)
            let formatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            groups.append(CacheGroup(
                id: "container.dockerDisk", title: "Docker Desktop disk image", category: .container,
                symbolName: CacheCategory.container.symbolName,
                detail: "Docker.raw uses \(formatted) on disk. Pruning frees space inside it; shrink it from Docker Desktop settings."))
        }
        return groups
    }
}
