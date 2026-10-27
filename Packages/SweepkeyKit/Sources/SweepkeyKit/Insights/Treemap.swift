import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing, van Wijk). Pure: weights in, rects out.
public enum Treemap {
    /// Returns one rect per weight, in input order. Non-positive or non-finite weights get `.zero`.
    /// Rect areas are proportional to weights and together tile `bounds`.
    public static func layout(weights: [Double], in bounds: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: weights.count)
        let order = weights.indices
            .filter { weights[$0].isFinite && weights[$0] > 0 }
            .sorted { weights[$0] > weights[$1] }
        let total = order.reduce(0.0) { $0 + weights[$1] }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        var remaining = bounds
        var row: [Int] = []
        var index = 0

        func worst(_ row: [Int], side: Double) -> Double {
            let areas = row.map { weights[$0] * scale }
            let sum = areas.reduce(0, +)
            guard let maxA = areas.max(), let minA = areas.min(), sum > 0, minA > 0 else { return .infinity }
            let s2 = side * side
            return max(s2 * maxA / (sum * sum), (sum * sum) / (s2 * minA))
        }

        while index < order.count {
            let side = Double(min(remaining.width, remaining.height))
            let next = order[index]
            let candidate = row + [next]
            if row.isEmpty || worst(candidate, side: side) <= worst(row, side: side) {
                row = candidate
                index += 1
            } else {
                remaining = place(row, weights: weights, scale: scale, in: remaining, into: &result)
                row = []
            }
        }
        if !row.isEmpty {
            _ = place(row, weights: weights, scale: scale, in: remaining, into: &result, isLast: true)
        }
        return result
    }

    /// Lays one row along the shorter side of `rect`; returns the leftover rect.
    private static func place(
        _ row: [Int], weights: [Double], scale: Double, in rect: CGRect,
        into result: inout [CGRect], isLast: Bool = false
    ) -> CGRect {
        let sum = row.reduce(0.0) { $0 + weights[$1] * scale }
        let horizontal = rect.width >= rect.height  // row is a column on the left when wide
        let thickness = isLast
            ? Double(horizontal ? rect.width : rect.height)
            : min(sum / Double(horizontal ? rect.height : rect.width), Double(horizontal ? rect.width : rect.height))
        var offset = 0.0
        for (n, i) in row.enumerated() {
            let area = weights[i] * scale
            let isEnd = n == row.count - 1
            let length = horizontal ? Double(rect.height) : Double(rect.width)
            let span = isEnd ? length - offset : (thickness > 0 ? area / thickness : 0)
            if horizontal {
                result[i] = CGRect(x: rect.minX, y: rect.minY + offset, width: thickness, height: span)
            } else {
                result[i] = CGRect(x: rect.minX + offset, y: rect.minY, width: span, height: thickness)
            }
            offset += span
        }
        return horizontal
            ? CGRect(x: rect.minX + thickness, y: rect.minY, width: max(0, Double(rect.width) - thickness), height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY + thickness, width: rect.width, height: max(0, Double(rect.height) - thickness))
    }
}
