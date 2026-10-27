import Foundation
import WidgetKit

/// Writes `widget-snapshot.json` into the App Group container for the widget extension.
enum WidgetSnapshotWriter {
    /// Silently does nothing when the App Group container is unavailable (ad-hoc builds
    /// without the entitlement).
    @MainActor
    static func update(model: AppModel) {
        guard WidgetSnapshot.fileURL() != nil, let disk = DiskInfo.current() else { return }
        let snapshot = WidgetSnapshot(
            freeBytes: disk.freeBytes, totalBytes: disk.totalBytes,
            reclaimableBytes: model.reclaimableBytes, updatedAt: Date())
        if snapshot.write() { WidgetCenter.shared.reloadAllTimelines() }
    }
}
