import SweepkeyKit
import Foundation

/// Bundled-rule source for the Rules screen. A later task wires the real catalog.
protocol RuleCatalog: Sendable {
    func rules() -> [Rule]
}

/// Everything the UI needs from the engine. Depends only on Core protocols.
struct AppServices: Sendable {
    var scanner: any ProjectScanning
    var caches: any CacheScanning
    var safety: any SafetyEvaluating
    var cleaner: any CleanExecuting
    var journal: any CleanJournaling
    var secrets: any SecretFinding
    var vaultExporter: any VaultExporting
    var vaultRestorer: any VaultRestoring
    var settingsStore: SettingsStore
    var ruleCatalog: any RuleCatalog
    /// Persists the last scan (live services only).
    var scanCache: ScanCache? = nil
    /// Builds a safety evaluator that honours the given pinned projects (live services only).
    var safetyFor: (@Sendable ([URL]) -> any SafetyEvaluating)? = nil
}
