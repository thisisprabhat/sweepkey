import Charts
import SweepkeyKit
import SwiftUI

/// Reclaimable space by category: a compact donut with the total in the middle, beside a legend
/// that carries each category's logo, size and share.
struct CategoryDonut: View {
    let slices: [(name: String, bytes: Int64)]
    @State private var hovered: String?

    private static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .yellow, .red, .indigo, .mint]

    private var total: Int64 { slices.reduce(0) { $0 + $1.bytes } }
    private func color(_ index: Int) -> Color { Self.palette[index % Self.palette.count] }

    /// The ecosystem behind a slice, for its logo (cache categories have none and keep a dot).
    private func ecosystem(named name: String) -> Ecosystem? { Ecosystem.builtIn.first { $0.name == name } }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            Chart(Array(slices.enumerated()), id: \.element.name) { index, slice in
                SectorMark(angle: .value("Size", slice.bytes), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(color(index))
                    .opacity(hovered == nil || hovered == slice.name ? 1 : 0.35)
            }
            .chartLegend(.hidden)
            .frame(width: 180, height: 180)
            .overlay {
                VStack(spacing: 0) {
                    Text(SizeFormat.string(hoveredBytes ?? total)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(hovered ?? "Total").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 100)
                .contentTransition(.numericText())
            }
            VStack(spacing: 6) {
                ForEach(Array(slices.enumerated()), id: \.element.name) { index, slice in
                    legendRow(index: index, slice: slice)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .animation(.easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reclaimable space by category")
    }

    private var hoveredBytes: Int64? { slices.first { $0.name == hovered }?.bytes }

    private func legendRow(index: Int, slice: (name: String, bytes: Int64)) -> some View {
        let share = total > 0 ? Double(slice.bytes) / Double(total) : 0
        return HStack(spacing: 10) {
            if let eco = ecosystem(named: slice.name) {
                EcosystemIcon(ecosystemID: eco.id, size: 22)
            } else {
                Circle().fill(color(index)).frame(width: 10, height: 10).frame(width: 22)
            }
            Text(slice.name).lineLimit(1)
            Spacer(minLength: 8)
            // Share bar in the slice's colour ties the row to the donut.
            Capsule().fill(.quaternary).frame(width: 90, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(color(index)).frame(width: max(3, 90 * share), height: 6)
                }
            Text(share, format: .percent.precision(.fractionLength(0))).font(.caption).foregroundStyle(.secondary)
                .monospacedDigit().frame(width: 38, alignment: .trailing)
            SizeText(bytes: slice.bytes).monospacedDigit().frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(hovered == slice.name ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovered = $0 ? slice.name : (hovered == slice.name ? nil : hovered) }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CategoryDonut(slices: [("Flutter/Dart", 13_000_000_000), ("Rust", 9_400_000_000), ("Xcode", 5_000_000_000)])
        .padding().frame(width: 720)
}
