import CleanerKit
import SwiftUI

extension RiskLevel {
    var title: LocalizedStringKey {
        switch self {
        case .safe: "Safe"
        case .caution: "Caution"
        case .danger: "Danger"
        }
    }

    var tint: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .danger: .red
        }
    }

    var symbolName: String {
        switch self {
        case .safe: "checkmark.circle"
        case .caution: "exclamationmark.triangle"
        case .danger: "exclamationmark.octagon"
        }
    }
}

/// Small risk capsule. Content-level, so it uses a tinted fill, not glass.
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Label(risk.title, systemImage: risk.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(risk.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(risk.tint.opacity(0.15), in: .capsule)
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(RiskLevel.allCases, id: \.self) { RiskBadge(risk: $0) }
    }
    .padding()
}
