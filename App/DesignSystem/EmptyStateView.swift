import SwiftUI

struct EmptyStateView<Actions: View>: View {
    let title: LocalizedStringKey
    let symbolName: String
    var message: LocalizedStringKey?
    @ViewBuilder var actions: Actions

    init(_ title: LocalizedStringKey, symbolName: String, message: LocalizedStringKey? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.symbolName = symbolName
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbolName)
        } description: {
            if let message { Text(message) }
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(_ title: LocalizedStringKey, symbolName: String, message: LocalizedStringKey? = nil) {
        self.title = title
        self.symbolName = symbolName
        self.message = message
        self.actions = EmptyView()
    }
}

#Preview {
    EmptyStateView("Nothing here", symbolName: "tray", message: "Run a scan to get started.")
}
