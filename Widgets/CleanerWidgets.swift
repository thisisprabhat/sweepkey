import SwiftUI
import WidgetKit

struct CleanerEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CleanerProvider: TimelineProvider {
    func placeholder(in context: Context) -> CleanerEntry { CleanerEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (CleanerEntry) -> Void) {
        completion(CleanerEntry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CleanerEntry>) -> Void) {
        let entry = CleanerEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct CleanerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CleanerEntry

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        if let snapshot = entry.snapshot {
            let used = snapshot.totalBytes > 0 ? Double(snapshot.totalBytes - snapshot.freeBytes) / Double(snapshot.totalBytes) : 0
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Cleaner", systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
                    Text(size(snapshot.freeBytes)).font(.title2.bold())
                    Text("free").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(size(snapshot.reclaimableBytes)) reclaimable").font(.caption.weight(.medium))
                }
            } else {
                HStack(spacing: 16) {
                    Gauge(value: used) { EmptyView() } currentValueLabel: {
                        Text("\(Int(used * 100))%").font(.caption)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .scaleEffect(1.4)
                    .frame(width: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Cleaner", systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
                        Text("\(size(snapshot.freeBytes)) free of \(size(snapshot.totalBytes))").font(.headline)
                        Text("\(size(snapshot.reclaimableBytes)) reclaimable").font(.subheadline)
                        Text("Updated \(snapshot.updatedAt, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "externaldrive")
                Text("Open Cleaner to load data").font(.caption).multilineTextAlignment(.center)
            }
        }
    }
}

struct CleanerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CleanerWidget", provider: CleanerProvider()) { entry in
            CleanerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Disk Space")
        .description("Free space and what Cleaner can reclaim.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CleanerWidgetBundle: WidgetBundle {
    var body: some Widget { CleanerWidget() }
}
