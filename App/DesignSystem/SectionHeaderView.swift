import SwiftUI

struct SectionHeaderView<Trailing: View>: View {
    let title: LocalizedStringKey
    var symbolName: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            if let symbolName { Image(systemName: symbolName).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            Spacer()
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeaderView where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, symbolName: String? = nil) {
        self.title = title
        self.symbolName = symbolName
        self.trailing = EmptyView()
    }
}

#Preview {
    SectionHeaderView("Top offenders", symbolName: "chart.bar").padding()
}
