import CleanerKit
import Foundation

extension AppModel {
    /// Fire-and-forget scan, cancellable by starting another.
    func scan() {
        guard !scanState.isScanning else { return }
        scanTask = Task { await runScan() }
    }

    func scanIfNeeded() {
        if case .idle = scanState, !settings.scanRoots.isEmpty { scan() }
    }

    func runScan() async {
        scanError = nil
        projects = []
        selection = []
        scanState = .scanning(ScanProgress(directoriesVisited: 0, currentPath: "", projectsFound: 0, bytesFound: 0))
        let options = ScanOptions(
            roots: settings.scanRoots, excludedPaths: settings.excludedPaths,
            ruleOverrides: settings.ruleOverrides, customRules: settings.customRules,
            staleAfterDays: settings.staleAfterDays)
        async let groups = services.caches.scanCaches()
        var summary: ScanSummary?
        do {
            for try await event in services.scanner.scan(options) {
                switch event {
                case .progress(let progress): scanState = .scanning(progress)
                case .project(let project): projects.append(project)
                case .finished(let done): summary = done
                }
            }
        } catch {
            scanError = error.localizedDescription
        }
        cacheGroups = await groups
        scanState = .done(summary ?? ScanSummary(
            projectCount: projects.count, candidateCount: projects.reduce(0) { $0 + $1.candidates.count },
            totalBytes: projects.reduce(0) { $0 + $1.reclaimableBytes }, startedAt: Date(), finishedAt: Date()))
        await loadJournal()
    }

    // MARK: Lookups

    var allCandidates: [Candidate] { projects.flatMap(\.candidates) + cacheGroups.flatMap(\.candidates) }

    var selectedCandidates: [Candidate] { allCandidates.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.sizeBytes } }

    var reclaimableBytes: Int64 { allCandidates.reduce(0) { $0 + $1.sizeBytes } }

    var topOffenders: [Candidate] { Array(allCandidates.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(10)) }

    /// Reclaimable bytes by ecosystem (projects) and cache category, largest first, tail folded into "Other".
    var breakdown: [(name: String, bytes: Int64)] {
        var totals: [String: Int64] = [:]
        for candidate in projects.flatMap(\.candidates) {
            totals[Ecosystem.named(candidate.ecosystemID).name, default: 0] += candidate.sizeBytes
        }
        for group in cacheGroups { totals[group.category.displayName, default: 0] += group.totalBytes }
        let sorted = totals.sorted { $0.value > $1.value }
        let head = sorted.prefix(6).map { (name: $0.key, bytes: $0.value) }
        let tail = sorted.dropFirst(6).reduce(Int64(0)) { $0 + $1.value }
        return tail > 0 ? head + [(name: "Other", bytes: tail)] : head
    }

    func project(containing candidateID: Candidate.ID) -> Project? {
        projects.first { $0.candidates.contains { $0.id == candidateID } }
    }

    // MARK: Selection

    func toggle(_ candidate: Candidate) {
        if selection.contains(candidate.id) { selection.remove(candidate.id) } else { selection.insert(candidate.id) }
    }

    func setSelected(_ candidates: [Candidate], _ on: Bool) {
        if on { selection.formUnion(candidates.map(\.id)) } else { selection.subtract(candidates.map(\.id)) }
    }

    func clearSelection() { selection = [] }

    // MARK: Filters

    var hasActiveFilters: Bool {
        ecosystemFilter != nil || riskFilter != nil || minSizeMB > 0 || staleOnly
    }

    func resetFilters() {
        ecosystemFilter = nil
        riskFilter = nil
        minSizeMB = 0
        staleOnly = false
    }

    var filteredProjects: [Project] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return projects.compactMap { project in
            if staleOnly && !project.isStale { return nil }
            if !query.isEmpty,
               !project.name.localizedCaseInsensitiveContains(query),
               !project.url.path.localizedCaseInsensitiveContains(query) { return nil }
            if let eco = ecosystemFilter, !project.ecosystemIDs.contains(eco) { return nil }
            var filtered = project
            filtered.candidates = project.candidates.filter { candidate in
                (riskFilter == nil || candidate.risk == riskFilter)
                    && candidate.sizeBytes >= Int64(minSizeMB) * 1_048_576
            }
            return filtered.candidates.isEmpty ? nil : filtered
        }
    }

    var availableEcosystems: [Ecosystem] {
        let ids = Set(projects.flatMap(\.ecosystemIDs))
        return Ecosystem.builtIn.filter { ids.contains($0.id) }
    }

    // MARK: Safety

    func evaluateVerdicts(for candidates: [Candidate]) async {
        let result = await services.safety.evaluate(candidates, scanRoots: settings.scanRoots)
        verdicts.merge(result) { _, new in new }
    }
}
