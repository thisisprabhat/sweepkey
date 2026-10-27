import SwiftUI

/// List of folder URLs with add (via panel) and remove.
struct URLListEditor: View {
    let title: LocalizedStringKey
    let panelMessage: String
    @Binding var urls: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if urls.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
            ForEach(urls, id: \.self) { url in
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(url.abbreviatingHome).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { urls.removeAll { $0 == url } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            Button("Add Folder…", systemImage: "plus") {
                for url in Panels.chooseFolders(message: panelMessage) where !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
    }
}

extension URL {
    /// Path with the home directory shortened to ~.
    var abbreviatingHome: String { (path as NSString).abbreviatingWithTildeInPath }
}
