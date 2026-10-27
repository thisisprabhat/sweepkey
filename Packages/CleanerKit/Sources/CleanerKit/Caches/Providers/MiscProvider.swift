import Foundation

struct MiscProvider: CacheProvider {
    let id = "misc"

    func detect(_ ctx: CacheContext) async -> [CacheGroup] {
        var items = [CacheItem(
            ruleID: "misc.diagnosticReports", url: ctx.path("Library/Logs/DiagnosticReports"),
            title: "Crash & diagnostic reports", risk: .caution, hint: "Not regenerated: new reports appear when apps crash",
            note: "Opt-in: crash logs can help diagnose problems you have not reported yet")]
        for backup in ctx.childDirectories(of: ctx.path("Library/Application Support/MobileSync/Backup")) {
            items.append(CacheItem(
                ruleID: "misc.iosBackup", url: backup, title: "iOS device backup \(backup.lastPathComponent)",
                risk: .danger, hint: "Cannot be regenerated", note: "iOS device backup — cannot be regenerated"))
        }
        return [await ctx.group("misc.other", "Other", .misc, items: items)]
    }
}
