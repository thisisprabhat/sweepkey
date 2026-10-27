import Foundation

struct BrowserTestingProvider: CacheProvider {
    let id = "browserTesting"

    private let entries: [(rule: String, title: String, path: String)] = [
        ("playwright", "Playwright browsers", "Library/Caches/ms-playwright"),
        ("puppeteer", "Puppeteer browsers", ".cache/puppeteer"),
        ("cypress", "Cypress binaries", "Library/Caches/Cypress"),
        ("electron", "Electron downloads", "Library/Caches/electron"),
        ("nodeGypLibrary", "node-gyp headers", "Library/Caches/node-gyp"),
        ("nodeGyp", "node-gyp headers", ".node-gyp"),
    ]

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        let items = entries.map {
            CacheItem(ruleID: "browserTesting.\($0.rule)", url: ctx.path($0.path), title: $0.title,
                      hint: "Re-downloaded on next install or run")
        }
        return [await ctx.group("browserTesting.caches", "Browser & testing downloads", .browserTesting, items: items)]
    }
}
