import SwiftUI

/// Animated ring with a pulsing symbol. Indeterminate when `fraction` is nil.
struct ScanProgressRing: View {
    var fraction: Double?
    var symbolName = "sparkle.magnifyingglass"
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction ?? 0.28)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90 + (fraction == nil && spin ? 360 : 0)))
                .animation(fraction == nil && !reduceMotion
                           ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .smooth, value: spin)
                .animation(.smooth, value: fraction)
            Image(systemName: symbolName)
                .font(.system(size: 30))
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .foregroundStyle(.secondary)
        }
        .frame(width: 96, height: 96)
        .onAppear { spin = true }
        .accessibilityElement()
        .accessibilityLabel("Working")
        .accessibilityValue(fraction.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("In progress"))
    }
}

#Preview {
    HStack(spacing: 24) { ScanProgressRing(); ScanProgressRing(fraction: 0.6) }.padding()
}
