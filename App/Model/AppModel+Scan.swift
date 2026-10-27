import CleanerKit
import Foundation

extension AppModel {
    /// Fire-and-forget scan; stop it with `cancelScan()`.
    func scan() {
        guard !scanState.isScanning else { return }
        scanGeneration += 1
        let generation = scanGeneration
        scanTask = Task { await runScan(generation: generation) }
    }

    /// Cancels a running scan and returns to idle (keeping any projects found so far).
    func cancelScan() {
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        if scanState.isScanning { scanState = .idle }
    }

    func scanIfNeeded() {
        if case .idle = scanState, !settings.scanRoots.isEmpty { scan() }
    }

    /// Launch sequence: journal, last cached scan, then an automatic scan when there is no cache
    /// (or when the DEBUG `-CleanerAutoScan YES` argument is given).
    func bootstrap() async {
        await loadJournal()
        let restored = await loadCachedScan()
        if AppRuntime.autoScan || !restored { scanIfNeeded() }
    }

    /// Shows the last persisted scan immediately. Returns true if one was loaded.
    @discardableResult
    func loadCachedScan() async -> Bool {
        guard case .idle = scanState, let cache = services.scanCache, let snapshot = await cache.load(),
              case .idle = scanState else { return false }
        projects = snapshot.projects
        scanState = .done(ScanSummary(
            projectCount: projects.count, candidateCount: projects.reduce(0) { $0 + $1.candidates.count },
            totalBytes: projects.reduce(0) { $0 + $1.reclaimableBytes },
            startedAt: snapshot.savedAt, finishedAt: snapshot.savedAt))
        return true
    }

    /// Saves the results, minus projects from one-off folder scans outside the scan roots, so a
    /// path-limited scan never replaces the saved full scan.
    func persistScanCache() async {
        guard let cache = services.scanCache else { return }
        let saved = ScanMerge.persistable(projects, scanRoots: settings.scanRoots)
        do { try await cache.save(saved) } catch { lastError = error.localizedDescription }
    }

    func runScan(generation: Int? = nil) async {
        let token = generation ?? { scanGeneration += 1; return scanGeneration }()
        func isCurrent() -> Bool { token == scanGeneration && !Task.isCancelled }
        scanError = nil
        projects = []
        selection = []
        temporaryScanRoots = []
        scanState = .scanning(ScanProgress(directoriesVisited: 0, currentPath: "", projectsFound: 0, bytesFound: 0))
        let options = ScanOptions(
            roots: AppLogic.resolve(settings.scanRoots), excludedPaths: AppLogic.resolve(settings.excludedPaths),
            ruleOverrides: settings.ruleOverrides, customRules: settings.customRules,
            staleAfterDays: settings.staleAfterDays)
        async let groups = services.caches.scanCaches()
        var summary: ScanSummary?
        var failure: String?
        do {
            for try await event in services.scanner.scan(options) {
                guard isCurrent() else { break }
                switch event {
                case .progress(let progress): scanState = .scanning(progress)
                case .project(let project): projects.append(project)
                case .finished(let done): summary = done
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        let found = await groups
        guard isCurrent() else { return }
        scanError = failure
        if failure == nil { AutomationState.shared.resultsMayBeOutdated = false }
        cacheGroups = OptInCaches.apply(found, overrides: settings.ruleOverrides)
        scanState = .done(summary ?? ScanSummary(
            projectCount: projects.count, candidateCount: projects.reduce(0) { $0 + $1.candidates.count },
            totalBytes: projects.reduce(0) { $0 + $1.reclaimableBytes }, startedAt: Date(), finishedAt: Date()))
        await persistScanCache()
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
        let safety = services.safetyFor?(settings.pinnedProjects) ?? services.safety
        let roots = AppLogic.resolve(settings.scanRoots + temporaryScanRoots)
        let result = await safety.evaluate(candidates, scanRoots: roots)
        verdicts.merge(result) { _, new in new }
    }
}
