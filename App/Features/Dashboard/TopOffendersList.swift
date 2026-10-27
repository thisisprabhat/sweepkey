import CleanerKit
import SwiftUI

struct TopOffendersList: View {
    let candidates: [Candidate]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)
                    EcosystemIcon(ecosystemID: candidate.ecosystemID)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.title).lineLimit(1)
                        Text(candidate.url.deletingLastPathComponent().abbreviatingHome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    RiskBadge(risk: candidate.risk)
                    SizeText(bytes: candidate.sizeBytes)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 6)
                if index < candidates.count - 1 { Divider() }
            }
        }
    }
}

#Preview {
    TopOffendersList(candidates: Array(MockData.projects.flatMap(\.candidates).prefix(5))).padding().frame(width: 560)
}
