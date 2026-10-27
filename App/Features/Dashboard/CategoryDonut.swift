import Charts
import SwiftUI

struct CategoryDonut: View {
    let slices: [(name: String, bytes: Int64)]

    var body: some View {
        Chart(slices, id: \.name) { slice in
            SectorMark(
                angle: .value("Size", slice.bytes),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("Category", slice.name))
        }
        .chartLegend(position: .trailing, alignment: .center)
        .frame(height: 200)
        .accessibilityLabel("Reclaimable space by category")
    }
}

#Preview {
    CategoryDonut(slices: [("JavaScript", 3_000_000_000), ("Rust", 3_400_000_000), ("Xcode", 5_000_000_000)])
        .padding().frame(width: 460)
}
