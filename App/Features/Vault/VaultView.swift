import SwiftUI

struct VaultView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case collect = "Collect", restore = "Restore"
        var id: String { rawValue }
    }

    @State private var mode = Mode.collect

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.vertical, 10)
            switch mode {
            case .collect: VaultCollectView()
            case .restore: VaultRestoreView()
            }
        }
        // Pin to the top; a shorter screen (empty state) would otherwise float in the middle.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Vault")
    }
}

#Preview {
    VaultView().environment(\.appModel, AppModel()).frame(width: 860, height: 640)
}
