import Foundation

struct AIModelProvider: CacheProvider {
    let id = "aiModels"

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        var items: [CacheItem] = []
        for dir in ctx.childDirectories(of: ctx.path(".cache/huggingface/hub")) {
            items.append(CacheItem(
                ruleID: "ai.huggingface", url: dir, title: "Hugging Face \(dir.lastPathComponent)", risk: .danger,
                hint: "Re-downloaded from Hugging Face on use"))
        }
        items += await ollama(ctx)
        for base in [".lmstudio/models", ".cache/lm-studio/models"] {
            for publisher in ctx.childDirectories(of: ctx.path(base)) {
                for model in ctx.childDirectories(of: publisher) {
                    items.append(CacheItem(
                        ruleID: "ai.lmstudio", url: model,
                        title: "LM Studio \(publisher.lastPathComponent)/\(model.lastPathComponent)", risk: .danger,
                        hint: "Re-download from LM Studio"))
                }
            }
        }
        return [await ctx.group("aiModels.models", "AI models", .aiModels, items: items)]
    }

    private func ollama(_ ctx: CacheContext) async -> [CacheItem] {
        let dir = ctx.path(".ollama/models")
        guard ctx.fileExists(dir) else { return [] }
        if let list = await ctx.output("ollama", ["list"]) {
            let rows = list.split(whereSeparator: \.isNewline).dropFirst()
            var items: [CacheItem] = []
            for row in rows {
                let tokens = row.split(whereSeparator: \.isWhitespace).map(String.init)
                guard tokens.count >= 4 else { continue }
                items.append(CacheItem(
                    ruleID: "ai.ollama.\(tokens[0])", url: dir, title: "Ollama \(tokens[0])", risk: .danger,
                    hint: "Re-pull with `ollama pull \(tokens[0])`",
                    action: .command(executable: "ollama", arguments: ["rm", tokens[0]]),
                    size: parseHumanSize(tokens[2] + tokens[3])))
            }
            return items
        }
        return [CacheItem(ruleID: "ai.ollama", url: dir, title: "Ollama models", risk: .danger,
                          hint: "Re-pull models with `ollama pull`")]
    }
}
