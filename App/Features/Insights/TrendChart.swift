import Charts
import CleanerKit
import SwiftUI

struct TrendChart: View {
    let points: [TrendPoint]

    var body: some View {
        Chart(points, id: \.day) { point in
            BarMark(x: .value("Day", point.day, unit: .day), y: .value("Freed", point.freedBytes))
                .foregroundStyle(.green.gradient)
                .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bytes = value.as(Int64.self) { Text(SizeFormat.string(bytes)) }
                }
            }
        }
        .frame(height: 160)
        .accessibilityLabel("Space freed per day")
    }
}

#Preview {
    TrendChart(points: [
        TrendPoint(day: .now.addingTimeInterval(-86_400 * 2), freedBytes: 2_000_000_000),
        TrendPoint(day: .now.addingTimeInterval(-86_400), freedBytes: 500_000_000),
        TrendPoint(day: .now, freedBytes: 4_000_000_000),
    ]).padding().frame(width: 500)
}
