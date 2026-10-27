import SwiftUI

struct DiskUsageCard: View {
    let disk: DiskInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Disk", systemImage: "internaldrive")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let disk {
                Text("\(SizeFormat.string(disk.freeBytes)) free")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                ProgressView(value: disk.usedFraction)
                    .tint(disk.usedFraction > 0.9 ? .red : .accentColor)
                Text("of \(SizeFormat.string(disk.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Unavailable").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DiskUsageCard(disk: DiskInfo(freeBytes: 120_000_000_000, totalBytes: 500_000_000_000)).padding().frame(width: 260)
}
