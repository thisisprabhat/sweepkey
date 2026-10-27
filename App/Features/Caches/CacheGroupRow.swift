import SweepkeyKit
import SwiftUI

struct CacheGroupRow: View {
    @Environment(\.appModel) private var model
    let group: CacheGroup
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(group.candidates) { candidate in
                CacheItemRow(candidate: candidate)
            }
        } label: {
            HStack(spacing: 10) {
                Toggle("Select \(group.title)", isOn: groupBinding).labelsHidden()
                LogoIcon(logo: group.logo, symbolName: group.symbolName, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title).fontWeight(.medium)
                    if let detail = group.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                SizeText(bytes: group.totalBytes).foregroundStyle(.secondary)
            }
        }
    }

    private var groupBinding: Binding<Bool> {
        Binding(
            get: { group.candidates.allSatisfy { model.selection.contains($0.id) } },
            set: { model.setSelected(group.candidates, $0) })
    }
}

struct CacheItemRow: View {
    @Environment(\.appModel) private var model
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Select \(candidate.title)", isOn: Binding(
                get: { model.selection.contains(candidate.id) },
                set: { _ in model.toggle(candidate) })).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title).lineLimit(1)
                if let note = candidate.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if case .command(let executable, let arguments) = candidate.action {
                    Label(([executable] + arguments).joined(separator: " "), systemImage: "terminal")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                        .help("Runs this command instead of deleting files")
                }
            }
            Spacer()
            RiskBadge(risk: candidate.risk)
            SizeText(bytes: candidate.sizeBytes).frame(width: 80, alignment: .trailing)
        }
        .padding(.leading, 28)
    }
}

#Preview {
    List { CacheGroupRow(group: MockData.cacheGroups[2]) }
        .environment(\.appModel, AppModel()).frame(width: 640, height: 240)
}
