import ArgumentParser
import CleanerKit
import Foundation

/// Shared safety-check, plan, confirm and execute flow for `clean` and `caches clean`.
func runCleanFlow(
    candidates: [Candidate], scanRoots: [URL], settings: CleanerSettings,
    dryRun: Bool, trash: Bool, yes: Bool
) async throws {
    guard !candidates.isEmpty else {
        print("Nothing to clean.")
        throw ExitCode(2)
    }
    let guardrail = SafetyGuard(pinnedProjects: settings.pinnedProjects.map(resolvedURL))
    let verdicts = await guardrail.evaluate(candidates, scanRoots: scanRoots)

    var allowed: [Candidate] = []
    var blocked: [(Candidate, String)] = []
    var warnings: [Candidate.ID: String] = [:]
    for candidate in candidates {
        switch verdicts[candidate.id] {
        case .allowed?: allowed.append(candidate)
        case .warning(let text)?:
            allowed.append(candidate)
            warnings[candidate.id] = text
        case .blocked(let reason)?: blocked.append((candidate, reason))
        case nil: blocked.append((candidate, "No safety verdict"))
        }
    }

    if !blocked.isEmpty {
        print("Blocked (will not be touched):")
        print(CLIFormatting.table(
            headers: ["Item", "Path", "Reason"],
            rows: blocked.map { [$0.0.title, $0.0.url.path, $0.1] }))
        print("")
    }
    guard !allowed.isEmpty else {
        print("Nothing to clean: every item was blocked by the safety checks.")
        throw ExitCode(2)
    }

    let mode: DeleteMode = trash ? .trash : settings.defaultDeleteMode
    print("Plan (\(dryRun ? "dry run, " : "")\(mode.rawValue)):")
    print(CLIFormatting.table(
        headers: ["Item", "Risk", "Size", "Path", "Warning"],
        rows: allowed.map { c in
            [c.title, c.risk.rawValue, CLIFormatting.formatBytes(c.sizeBytes), c.url.path, warnings[c.id] ?? ""]
        },
        rightAligned: [2]))
    let total = allowed.reduce(Int64(0)) { $0 + $1.sizeBytes }
    print("\n\(allowed.count) item(s), \(CLIFormatting.formatBytes(total)).")

    let danger = allowed.filter { $0.risk == .danger }
    if !danger.isEmpty {
        print("\nDANGER items (hard to regenerate):")
        for c in danger { print("  - \(c.title)  \(c.url.path)") }
    }

    if !yes && !dryRun {
        guard standardInputIsTTY else {
            printError("Refusing to clean without confirmation on a non-interactive terminal. Pass --yes.")
            throw ExitCode.failure
        }
        let prompt = danger.isEmpty ? "Proceed? [y/N]" : "Proceed, including the danger items above? [y/N]"
        guard confirm(prompt) else {
            print("Aborted.")
            throw ExitCode.failure
        }
    }

    let executor = CleanExecutor(journal: JSONJournal())
    let report = await executor.clean(allowed, mode: mode, dryRun: dryRun, progress: { _ in })

    print("")
    print(CLIFormatting.table(
        headers: ["Item", "Status", "Freed", "Message"],
        rows: report.items.map {
            [$0.candidate.title, $0.status.rawValue, CLIFormatting.formatBytes($0.freedBytes), $0.message ?? ""]
        },
        rightAligned: [2]))
    if dryRun {
        let would = report.items.filter { $0.status == .dryRun }.reduce(Int64(0)) { $0 + $1.freedBytes }
        print("\nDry run: nothing was deleted. Would free \(CLIFormatting.formatBytes(would)).")
    } else {
        print("\nFreed \(CLIFormatting.formatBytes(report.freedBytes)).")
    }
    if report.items.contains(where: { $0.status == .failed }) { throw ExitCode.failure }
}
