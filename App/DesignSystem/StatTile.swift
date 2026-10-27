import SwiftUI

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var symbolName: String
    var tint: Color = .accentColor
    /// Optional small line under the value.
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbolName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                // One line, shrinking if needed: a wrapping value changes the tile's height with
                // the width, which can make side-by-side layouts oscillate.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        // Fill the row's height so tiles side by side line up.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        StatTile(title: "Reclaimable", value: "42 GB", symbolName: "arrow.3.trianglepath")
        StatTile(title: "Freed", value: "8 GB", symbolName: "checkmark.circle", tint: .green)
    }.padding()
}
