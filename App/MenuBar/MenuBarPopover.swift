import CleanerKit
import SwiftUI

/// Content of the menu bar extra (`.window` style).
struct MenuBarPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var disk = DiskInfo.current()
    @State private var confirming = false
    /// The exact items shown in the confirmation; only these are cleaned.
    @State private var confirmedItems: [Candidate] = []
    @State private var working = false
    private let automation = AutomationState.shared

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let disk {
                VStack(alignment: .leading, spacing: 4) {
                    Gauge(value: disk.usedFraction) { Text("Disk") }
                    Text("\(size(disk.freeBytes)) free of \(size(disk.totalBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Reclaimable", value: size(model.reclaimableBytes))
            if automation.resultsMayBeOutdated {
                Label("Results may be outdated", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            quickClean
            if let report = model.reports.first, !report.dryRun {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last clean").font(.caption).foregroundStyle(.secondary)
                    Text("\(size(report.freedBytes)) freed, \(report.finishedAt.formatted(.relative(presentation: .named)))")
                        .font(.callout)
                }
            }
            if let message = automation.lastActionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Open Cleaner") {
                    AppRouter.showApp()
                    openWindow(id: "main")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { disk = DiskInfo.current() }
        .onChange(of: model.diskRefreshToken) { disk = DiskInfo.current() }
        .task { await model.ensureScanned() }
    }

    @ViewBuilder
    private var quickClean: some View {
        let items = model.safeCleanCandidates
        if confirming {
            let bytes = confirmedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
            VStack(alignment: .leading, spacing: 8) {
                Text("Clean \(confirmedItems.count) safe item(s) of stale projects, \(size(bytes))?")
                    .font(.callout.weight(.medium))
                Text(model.settings.defaultDeleteMode == .trash ? "Items go to the Trash." : "Items are deleted permanently.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") {
                        confirming = false
                        confirmedItems = []
                    }
                    Button("Clean", role: .destructive) {
                        let chosen = confirmedItems
                        confirming = false
                        confirmedItems = []
                        working = true
                        Task {
                            // Exactly the confirmed items, not a recomputed list (as the intents do).
                            let outcome = await model.cleanEligible(chosen, dryRun: false)
                            automation.lastActionMessage = outcome.summary
                            working = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Button {
                confirmedItems = items
                confirming = true
            } label: {
                Label(working ? "Cleaning…" : "Quick clean safe items", systemImage: "sparkles")
            }
            .disabled(items.isEmpty || working || model.scanState.isScanning)
        }
    }
}
