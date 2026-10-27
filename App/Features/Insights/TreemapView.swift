import SweepkeyKit
import SwiftUI

struct TreemapItem: Identifiable, Hashable {
    let id: String
    let label: String
    let bytes: Int64
}

/// Squarified treemap drawn with `Canvas`; layout math lives in `SweepkeyKit.Treemap`.
struct TreemapView: View {
    let items: [TreemapItem]
    /// When set, right-clicking a tile shows this menu for it (e.g. project actions).
    var menu: ((TreemapItem) -> AnyView)?
    @State private var hovered: Int?
    @State private var hoverPoint: CGPoint = .zero

    private func rects(in size: CGSize) -> [CGRect] {
        Treemap.layout(weights: items.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: size))
    }

    private func color(_ index: Int) -> Color {
        Color(hue: Double((index * 47) % 360) / 360, saturation: 0.45, brightness: 0.78)
    }

    var body: some View {
        GeometryReader { geo in
            let layout = rects(in: geo.size)
            Canvas { context, _ in
                for (i, rect) in layout.enumerated() where rect.width > 0 && rect.height > 0 {
                    let inset = rect.insetBy(dx: 1, dy: 1)
                    let path = Path(roundedRect: inset, cornerRadius: 4)
                    context.fill(path, with: .color(color(i).opacity(hovered == i ? 1 : 0.85)))
                    if inset.width > 60, inset.height > 26 {
                        // Clip so a long name never spills into the neighbouring tile.
                        var tile = context
                        tile.clip(to: path)
                        let text = Text(items[i].label).font(.caption.weight(.medium)).foregroundColor(.black.opacity(0.8))
                        tile.draw(text, at: CGPoint(x: inset.minX + 6, y: inset.minY + 6), anchor: .topLeading)
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverPoint = point
                    hovered = layout.firstIndex { $0.contains(point) && $0.width > 0 }
                case .ended:
                    hovered = nil
                }
            }
            .contextMenu {
                if let menu, let hovered, items.indices.contains(hovered) { menu(items[hovered]) }
            }
            .overlay(alignment: .topLeading) {
                if let hovered, items.indices.contains(hovered) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items[hovered].label).font(.callout.weight(.semibold))
                        Text(SizeFormat.string(items[hovered].bytes)).monospacedDigit()
                    }
                    .padding(8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    .offset(x: min(hoverPoint.x + 12, max(0, geo.size.width - 160)),
                            y: min(hoverPoint.y + 12, max(0, geo.size.height - 56)))
                    .allowsHitTesting(false)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Treemap of reclaimable space")
            .accessibilityValue(items.prefix(5).map { "\($0.label) \(SizeFormat.string($0.bytes))" }.joined(separator: ", "))
        }
        .frame(height: 260)
    }
}

#Preview {
    TreemapView(items: [
        TreemapItem(id: "a", label: "app-web", bytes: 5_000_000_000),
        TreemapItem(id: "b", label: "api", bytes: 3_000_000_000),
        TreemapItem(id: "c", label: "mobile", bytes: 1_200_000_000),
        TreemapItem(id: "d", label: "docs", bytes: 300_000_000),
    ]).padding().frame(width: 600)
}
