import CleanerKit
import SwiftUI

/// Never shows file contents: only the name and size.
struct MaskedPreviewView: View {
    let file: SecretFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.sourceURL.lastPathComponent).fontWeight(.medium)
                HStack(spacing: 6) {
                    SizeText(bytes: file.sizeBytes)
                    Text("· contents hidden").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            Button("Reveal in Finder", systemImage: "folder") { Panels.reveal(file.sourceURL) }
                .buttonStyle(.glass)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
    }
}

#Preview {
    MaskedPreviewView(file: MockData.secrets[0]).frame(width: 600)
}
