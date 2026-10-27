import SwiftUI

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var symbolName: String
    var tint: Color = .accentColor

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
