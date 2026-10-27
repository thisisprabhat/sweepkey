import Foundation

public struct ArchiveStep: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable { case done, skipped, failed }
    public var name: String
    public var status: Status
    public var detail: String

    public init(name: String, status: Status, detail: String = "") {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct ArchiveReport: Sendable {
    public var steps: [ArchiveStep] = []
    public var risks: [ArchiveRisk] = []
    public var freedBytes: Int64 = 0
    public var zipURL: URL?
    public var trashedProject = false
    /// Where the project went in the Trash (when the trash call reports it), for Put Back.
    public var projectTrashURL: URL?
    /// The permanent artifact clean, so the caller can journal it.
    public var cleanReport: CleanReport?
    /// True only if every step finished without failure.
    public var succeeded: Bool { !steps.isEmpty && !steps.contains { $0.status == .failed } }
    /// True when the run stopped because risks were not acknowledged.
    public var requiresAcknowledgement = false

    public init() {}
}

/// Vault-collect, clean, optionally zip-and-trash a project. Stops at the first failing step; the
/// original is only moved to the Trash after the zip has been extracted successfully.
public struct ArchiveRecipe: Sendable {
    private let secrets: any SecretFinding
    private let exporter: any VaultExporting
    private let cleaner: any CleanExecuting
    private let safety: any SafetyEvaluating
    private let shell: any ShellRunning
    private let trash: @Sendable (URL) throws -> URL?

    /// `trash` moves the project to the Trash and returns where it landed (nil if unknown).
    public init(
        secrets: any SecretFinding, exporter: any VaultExporting, cleaner: any CleanExecuting,
        safety: any SafetyEvaluating, shell: any ShellRunning = ProcessShellRunner(),
        trash: @escaping @Sendable (URL) throws -> URL? = ArchiveRecipe.moveToTrash
    ) {
        self.secrets = secrets
        self.exporter = exporter
        self.cleaner = cleaner
        self.safety = safety
        self.shell = shell
        self.trash = trash
    }

    /// - Parameters:
    ///   - collect: the user's vault collect options (`SweepkeySettings.vaultCollectOptions()`); the
    ///     roots are replaced by the project. Defaults apply when nil.
    ///   - layoutRoots: the scan roots, in settings order, so the vault uses the same
    ///     `<root>/<relative path>` layout as every other export. A project outside them is laid
    ///     out under its parent folder.
    ///   - keepVersions: `VaultSettings.keepVersions`.
    public func run(
        project: Project, vaultDestination: URL, archiveDirectory: URL?, zip: Bool,
        acknowledgeRisks: Bool = false, collect: VaultCollectOptions? = nil, layoutRoots: [URL] = [],
        keepVersions: Int = 5
    ) async -> ArchiveReport {
        var report = ArchiveReport()

        // 0. Pre-archive check.
        report.risks = PreArchiveCheck.risks(projects: [project])
        if !report.risks.isEmpty && !acknowledgeRisks {
            report.requiresAcknowledgement = true
            report.steps.append(ArchiveStep(
                name: "Pre-archive check", status: .failed,
                detail: report.risks.map(\.message).joined(separator: "; ") + ". Acknowledge the risks to continue."))
            return report
        }
        report.steps.append(ArchiveStep(
            name: "Pre-archive check", status: .done,
            detail: report.risks.isEmpty ? "No risks found" : "Risks acknowledged"))
        if zip && archiveDirectory == nil {
            report.steps.append(ArchiveStep(name: "Archive", status: .failed, detail: "No archive directory given"))
            return report
        }

        // Destinations inside the project would be trashed together with it. Fail before anything runs.
        if Self.isInsideOrEqual(vaultDestination, of: project.url) {
            report.steps.append(ArchiveStep(
                name: "Destination check", status: .failed,
                detail: "The vault destination is inside the project and would be lost with it. Choose another folder."))
            return report
        }
        if zip, let archiveDirectory {
            if Self.isInsideOrEqual(archiveDirectory, of: project.url) {
                report.steps.append(ArchiveStep(
                    name: "Destination check", status: .failed,
                    detail: "The archive folder is inside the project and would be lost with it. Choose another folder."))
                return report
            }
            let zipPath = Self.resolved(archiveDirectory.appendingPathComponent(project.url.lastPathComponent + ".zip"))
            if zipPath.pathComponents == Self.resolved(project.url).pathComponents {
                report.steps.append(ArchiveStep(
                    name: "Destination check", status: .failed, detail: "The zip path coincides with the project."))
                return report
            }
        }

        // 1. Vault collect + folder export.
        do {
            var options = collect ?? VaultCollectOptions(roots: [])
            options.roots = [project.url]
            let found = VaultLayout.rebase(
                try await secrets.findSecrets(options),
                scanRoots: layoutRoots + [project.url.deletingLastPathComponent()])
            if found.isEmpty {
                report.steps.append(ArchiveStep(name: "Vault", status: .skipped, detail: "No secrets found"))
            } else {
                let result = try await exporter.export(VaultExportRequest(
                    files: found, destination: vaultDestination, format: .folder, keepVersions: keepVersions))
                report.steps.append(ArchiveStep(
                    name: "Vault", status: .done,
                    detail: "Saved \(found.count) file(s) to \(result.outputURL.path)"))
            }
        } catch {
            report.steps.append(ArchiveStep(name: "Vault", status: .failed, detail: error.localizedDescription))
            return report
        }

        // 2. Clean artifacts (permanent), only those the safety evaluator allows.
        let scanRoot = project.url.deletingLastPathComponent()
        let verdicts = await safety.evaluate(project.candidates, scanRoots: [scanRoot])
        let allowed = project.candidates.filter { verdicts[$0.id]?.isAllowed ?? false }
        let blocked = project.candidates.count - allowed.count
        if allowed.isEmpty {
            report.steps.append(ArchiveStep(
                name: "Clean", status: .skipped,
                detail: blocked > 0 ? "\(blocked) artifact(s) blocked by safety checks" : "Nothing to clean"))
        } else {
            let cleaned = await cleaner.clean(allowed, mode: .permanent, dryRun: false) { _ in }
            let failures = cleaned.items.filter { $0.status == .failed }
            report.freedBytes = cleaned.freedBytes
            report.cleanReport = cleaned
            if failures.isEmpty {
                var detail = "Freed \(cleaned.freedBytes) bytes"
                if blocked > 0 { detail += "; \(blocked) artifact(s) blocked by safety checks" }
                report.steps.append(ArchiveStep(name: "Clean", status: .done, detail: detail))
            } else {
                report.steps.append(ArchiveStep(
                    name: "Clean", status: .failed,
                    detail: failures.map { "\($0.candidate.title): \($0.message ?? "failed")" }.joined(separator: "; ")))
                return report
            }
        }

        guard zip, let archiveDirectory else { return report }

        // 3. Zip, verify, then trash.
        let zipURL = archiveDirectory.appendingPathComponent(project.url.lastPathComponent + ".zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            report.steps.append(ArchiveStep(
                name: "Zip", status: .failed, detail: "\(zipURL.path) already exists; not overwriting"))
            return report
        }
        do {
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let made = try await shell.run(
                "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", project.url.path, zipURL.path],
                currentDirectory: nil, input: nil, timeout: .seconds(3600))
            guard made.succeeded else {
                report.steps.append(ArchiveStep(name: "Zip", status: .failed, detail: "ditto: " + made.stderr))
                return report
            }
            report.zipURL = zipURL
            report.steps.append(ArchiveStep(name: "Zip", status: .done, detail: zipURL.path))
        } catch {
            report.steps.append(ArchiveStep(name: "Zip", status: .failed, detail: error.localizedDescription))
            return report
        }

        guard await verify(zip: zipURL, projectName: project.url.lastPathComponent, report: &report) else { return report }

        do {
            report.projectTrashURL = try trash(project.url)
            report.trashedProject = true
            report.steps.append(ArchiveStep(name: "Move to Trash", status: .done, detail: project.url.path))
        } catch {
            report.steps.append(ArchiveStep(name: "Move to Trash", status: .failed, detail: error.localizedDescription))
        }
        return report
    }

    @Sendable public static func moveToTrash(_ url: URL) throws -> URL? {
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return out as URL?
    }

    /// Standardizes and resolves symlinks of the deepest existing ancestor, so not-yet-created
    /// directories are compared correctly (e.g. /var vs /private/var).
    static func resolved(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var out = existing.resolvingSymlinksInPath()
        for t in tail { out.appendPathComponent(t) }
        return out.standardizedFileURL
    }

    static func isInsideOrEqual(_ url: URL, of base: URL) -> Bool {
        let a = resolved(url).pathComponents
        let b = resolved(base).pathComponents
        return a.count >= b.count && Array(a.prefix(b.count)) == b
    }

    /// The zip must exist and extract cleanly into a temporary directory.
    private func verify(zip: URL, projectName: String, report: inout ArchiveReport) async -> Bool {
        guard FileManager.default.fileExists(atPath: zip.path) else {
            report.steps.append(ArchiveStep(name: "Verify zip", status: .failed, detail: "Zip file is missing"))
            return false
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepkey-verify-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let r = try await shell.run(
                "/usr/bin/ditto", arguments: ["-x", "-k", zip.path, temp.path],
                currentDirectory: nil, input: nil, timeout: .seconds(3600))
            guard r.succeeded else {
                report.steps.append(ArchiveStep(name: "Verify zip", status: .failed, detail: "ditto -x: " + r.stderr))
                return false
            }
            var isDir: ObjCBool = false
            let extracted = temp.appendingPathComponent(projectName).path
            guard FileManager.default.fileExists(atPath: extracted, isDirectory: &isDir), isDir.boolValue else {
                report.steps.append(ArchiveStep(
                    name: "Verify zip", status: .failed, detail: "Extracted archive does not contain \(projectName)"))
                return false
            }
            report.steps.append(ArchiveStep(name: "Verify zip", status: .done, detail: "Archive extracts cleanly"))
            return true
        } catch {
            report.steps.append(ArchiveStep(name: "Verify zip", status: .failed, detail: error.localizedDescription))
            return false
        }
    }
}

/// Journal entries for an archive run: the permanent artifact clean, and the move of the whole
/// project to the Trash (a Trash-mode entry, so History can put it back).
public enum ArchiveJournal {
    public static let ruleID = "recipe.archive"

    public static func reports(for report: ArchiveReport, project: Project, now: Date = Date()) -> [CleanReport] {
        var out: [CleanReport] = []
        if let clean = report.cleanReport { out.append(clean) }
        if report.trashedProject {
            let candidate = Candidate(
                id: "\(ruleID)|\(project.url.path)", url: project.url, kind: .projectArtifact,
                title: "\(project.name) (archived project)", ecosystemID: project.ecosystemIDs.first ?? "generic",
                ruleID: ruleID, risk: .caution, sizeBytes: 0, projectRoot: project.url)
            let zip = report.zipURL.map { " after archiving to \($0.path)" } ?? ""
            out.append(CleanReport(
                startedAt: now, finishedAt: now, mode: .trash, dryRun: false,
                items: [CleanItemResult(
                    candidate: candidate, status: .cleaned, freedBytes: 0,
                    message: "Project moved to the Trash\(zip)", trashURL: report.projectTrashURL)]))
        }
        return out
    }
}
