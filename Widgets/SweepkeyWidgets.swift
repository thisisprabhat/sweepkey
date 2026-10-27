import SwiftUI
import WidgetKit

struct SweepkeyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SweepkeyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SweepkeyEntry { SweepkeyEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SweepkeyEntry) -> Void) {
        completion(SweepkeyEntry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SweepkeyEntry>) -> Void) {
        let entry = SweepkeyEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct SweepkeyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SweepkeyEntry

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        if let snapshot = entry.snapshot {
            let used = snapshot.totalBytes > 0 ? Double(snapshot.totalBytes - snapshot.freeBytes) / Double(snapshot.totalBytes) : 0
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sweepkey", systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
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
                        Label("Sweepkey", systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
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
                Text("Open Sweepkey to load data").font(.caption).multilineTextAlignment(.center)
            }
        }
    }
}

struct SweepkeyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SweepkeyWidget", provider: SweepkeyProvider()) { entry in
            SweepkeyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Disk Space")
        .description("Free space and what Sweepkey can reclaim.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SweepkeyWidgetBundle: WidgetBundle {
    var body: some Widget { SweepkeyWidget() }
}
