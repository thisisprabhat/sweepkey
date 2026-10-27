import SwiftUI

/// Floating bottom bar for the current selection. Glass is used here because it is floating
/// chrome; it morphs in and out via `glassEffectID`.
struct GlassActionBar: View {
    let count: Int
    let bytes: Int64
    var onClean: () -> Void
    var onClear: () -> Void
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if count > 0 {
                    HStack(spacing: 14) {
                        Text("\(count) selected")
                            .fontWeight(.medium)
                        SizeText(bytes: bytes)
                            .foregroundStyle(.secondary)
                        Button("Clear", action: onClear)
                            .buttonStyle(.glass)
                        Button("Clean", systemImage: "trash", action: onClean)
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("actionBar", in: namespace)
                }
            }
        }
        .animation(.smooth, value: count > 0)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack {
        Spacer()
        GlassActionBar(count: 3, bytes: 1_200_000_000, onClean: {}, onClear: {})
    }
    .frame(width: 500, height: 200)
}
