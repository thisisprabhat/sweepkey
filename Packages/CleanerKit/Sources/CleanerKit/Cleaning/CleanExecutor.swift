import Foundation

public struct CleanExecutor: CleanExecuting {
    private let shell: ShellRunning
    private let sizer: SizeCalculator
    private let journal: CleanJournaling?
    private let home: URL

    public init(
        shell: ShellRunning = ProcessShellRunner(), sizer: SizeCalculator = .init(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        journal: CleanJournaling? = nil
    ) {
        self.shell = shell
        self.sizer = sizer
        self.home = home
        self.journal = journal
    }

    public func clean(
        _ candidates: [Candidate], mode: DeleteMode, dryRun: Bool,
        progress: @escaping @Sendable (CleanProgress) -> Void
    ) async -> CleanReport {
        let started = Date()
        var items: [CleanItemResult] = []
        var freed: Int64 = 0

        for (index, c) in candidates.enumerated() {
            let item: CleanItemResult
            if Task.isCancelled {
                item = CleanItemResult(candidate: c, status: .skipped, message: "Cancelled")
            } else if dryRun {
                item = CleanItemResult(candidate: c, status: .dryRun, freedBytes: c.sizeBytes)
            } else {
                item = await run(c, mode: mode)
            }
            items.append(item)
            if item.status == .cleaned { freed += item.freedBytes }
            progress(CleanProgress(
                completed: index + 1, total: candidates.count, currentTitle: c.title, freedBytes: freed))
        }

        var report = CleanReport(
            startedAt: started, finishedAt: Date(), mode: mode, dryRun: dryRun, items: items)
        if !dryRun, let journal {
            do {
                try await journal.append(report)
            } catch {
                // Surface the failure without changing the contract: note it on the last item.
                if let last = report.items.indices.last {
                    let note = "Journal write failed: \(error.localizedDescription)"
                    let old = report.items[last].message
                    report.items[last].message = old.map { "\($0); \(note)" } ?? note
                }
            }
        }
        return report
    }

    private func run(_ c: Candidate, mode: DeleteMode) async -> CleanItemResult {
        switch c.action {
        case .delete: return delete(c, mode: mode)
        case let .command(executable, arguments): return await command(c, executable, arguments)
        }
    }

    private func delete(_ c: Candidate, mode: DeleteMode) -> CleanItemResult {
        let fm = FileManager.default
        if c.url.isSymlink { return CleanItemResult(candidate: c, status: .skipped, message: "Is a symlink") }
        guard fm.fileExists(atPath: c.url.path) else {
            return CleanItemResult(candidate: c, status: .skipped, message: "No longer exists")
        }
        // Defence in depth: never act through a symlinked ancestor, or on `/` or home.
        let standard = c.url.standardizedFileURL
        let resolved = standard.resolvingSymlinksInPath()
        if standard.path != resolved.path {
            return CleanItemResult(candidate: c, status: .skipped, message: "Path passes through a symlink")
        }
        if standard.path == "/" || standard.path.lowercased() == home.standardizedFileURL.resolvingSymlinksInPath().path.lowercased() {
            return CleanItemResult(candidate: c, status: .skipped, message: "Refusing to delete root or home")
        }
        let size = sizer.allocatedSize(of: c.url)
        do {
            switch mode {
            case .permanent:
                try fm.removeItem(at: c.url)
                return CleanItemResult(candidate: c, status: .cleaned, freedBytes: size)
            case .trash:
                var trashed: NSURL?
                try fm.trashItem(at: c.url, resultingItemURL: &trashed)
                return CleanItemResult(
                    candidate: c, status: .cleaned, freedBytes: size, trashURL: trashed as URL?)
            }
        } catch {
            return CleanItemResult(candidate: c, status: .failed, message: error.localizedDescription)
        }
    }

    private func command(_ c: Candidate, _ executable: String, _ arguments: [String]) async -> CleanItemResult {
        let before = sizer.allocatedSize(of: c.url)
        do {
            let r = try await shell.run(
                executable, arguments: arguments, currentDirectory: nil, input: nil, timeout: .seconds(600))
            guard r.succeeded else {
                let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return CleanItemResult(
                    candidate: c, status: .failed,
                    message: msg.isEmpty ? "Exit code \(r.exitCode)" : msg)
            }
            let after = sizer.allocatedSize(of: c.url)
            return CleanItemResult(candidate: c, status: .cleaned, freedBytes: max(0, before - after))
        } catch {
            return CleanItemResult(candidate: c, status: .failed, message: "\(error)")
        }
    }

    public func putBack(_ items: [CleanItemResult]) async -> [CleanItemResult] {
        let fm = FileManager.default
        var out: [CleanItemResult] = []
        for item in items where item.status == .cleaned {
            guard let trash = item.trashURL else { continue }
            var r = item
            let dest = item.candidate.url
            if !trash.pathComponents.contains(".Trash") {
                r.status = .failed
                r.message = "Not in Trash"
            } else if fm.fileExists(atPath: dest.path) || dest.isSymlink {
                r.status = .failed
                r.message = "Destination exists"
            } else {
                do {
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: trash, to: dest)
                    r.status = .skipped
                    r.message = "Restored"
                    r.freedBytes = 0
                    r.trashURL = nil
                } catch {
                    r.status = .failed
                    r.message = error.localizedDescription
                }
            }
            out.append(r)
        }
        return out
    }
}
