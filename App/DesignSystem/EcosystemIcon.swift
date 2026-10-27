import CleanerKit
import SwiftUI

struct EcosystemIcon: View {
    let ecosystemID: String
    var size: CGFloat = 22

    var body: some View {
        let ecosystem = Ecosystem.named(ecosystemID)
        Image(systemName: ecosystem.symbolName)
            .font(.system(size: size * 0.55))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityLabel(ecosystem.name)
            .help(ecosystem.name)
    }
}

#Preview {
    HStack { ForEach(Ecosystem.builtIn.prefix(8)) { EcosystemIcon(ecosystemID: $0.id) } }.padding()
}
