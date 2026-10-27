import AppKit
import SweepkeyKit
import SwiftUI

/// A brand logo from `Assets.xcassets/EcosystemLogos` (Simple Icons, CC0), or the SF Symbol when
/// there is no logo for it.
struct LogoIcon: View {
    let logo: String?
    let symbolName: String
    var size: CGFloat = 22

    private var assetName: String? {
        guard let logo else { return nil }
        let name = "EcosystemLogos/\(logo)"
        return NSImage(named: name) != nil ? name : nil
    }

    var body: some View {
        Group {
            if let assetName {
                Image(assetName).resizable().scaledToFit().padding(size * 0.12)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct EcosystemIcon: View {
    let ecosystemID: String
    var size: CGFloat = 22

    var body: some View {
        let ecosystem = Ecosystem.named(ecosystemID)
        LogoIcon(logo: ecosystemID == "generic" ? nil : ecosystemID, symbolName: ecosystem.symbolName, size: size)
            .accessibilityLabel(ecosystem.name)
            .help(ecosystem.name)
    }
}

extension CacheGroup {
    /// Logo for groups that belong to one tool; mixed groups (package managers, IDE caches) keep their symbol.
    var logo: String? {
        switch id {
        case let id where id.hasPrefix("xcode."): "xcode"
        case let id where id.hasPrefix("android."): "android"
        case "container.docker": "docker"
        case "ide.jetbrains": "jetbrains"
        default: nil
        }
    }
}

#Preview {
    HStack { ForEach(Ecosystem.builtIn.prefix(8)) { EcosystemIcon(ecosystemID: $0.id) } }.padding()
}
