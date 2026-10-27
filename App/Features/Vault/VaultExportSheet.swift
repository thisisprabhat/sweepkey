import SweepkeyKit
import SwiftUI

struct VaultExportSheet: View {
    @Environment(\.appModel) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var format = VaultExportFormat.folder
    @State private var destination: URL?
    @State private var password = ""
    @State private var confirm = ""
    @State private var remember = false

    private var formatTitle: [VaultExportFormat: LocalizedStringKey] {
        [.folder: "Folder", .zip: "Zip archive", .encryptedImage: "Encrypted image"]
    }

    private var isCloudPath: Bool {
        guard let path = destination?.path else { return false }
        return ["Mobile Documents", "iCloud", "Dropbox", "Google Drive", "OneDrive"].contains { path.contains($0) }
    }

    private var canExport: Bool {
        guard isValidDestination(destination) else { return false }
        return format != .encryptedImage || (password.count >= 8 && password == confirm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export \(model.findingsSelection.count) files").font(.title2.weight(.semibold))
            switch model.exportState {
            case .idle: form
            case .running:
                VStack(spacing: 12) { ScanProgressRing(symbolName: "lock.shield"); Text("Exporting…") }
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .done(let result): VaultExportResultView(result: result) { dismiss() }
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                Button("Back") { model.exportState = .idle }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: format) { _, _ in
            if !isValidDestination(destination) { destination = nil }
        }
        .onAppear { format = model.settings.vault.defaultFormat; destination = model.settings.vault.destination }
    }

    @ViewBuilder private var form: some View {
        Picker("Format", selection: $format) {
            ForEach(VaultExportFormat.allCases, id: \.self) { Text(formatTitle[$0] ?? "").tag($0) }
        }
        .pickerStyle(.segmented)
        HStack {
            Text(destination?.abbreviatingHome ?? "No destination chosen")
                .foregroundStyle(destination == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Choose…") { destination = chooseDestination() }
        }
        if isCloudPath {
            Label("This folder syncs to the cloud. Secrets stored here leave your Mac — prefer an encrypted image.",
                  systemImage: "exclamationmark.icloud")
                .font(.callout).foregroundStyle(.orange)
        }
        if format == .encryptedImage {
            SecureField("Password (8+ characters)", text: $password)
            SecureField("Confirm password", text: $confirm)
            Toggle(VaultKeychain.gatingAvailable ? "Remember in Keychain (unlock with Touch ID)" : "Remember in Keychain",
                   isOn: $remember)
            if !confirm.isEmpty && confirm != password {
                Text("Passwords don't match.").font(.caption).foregroundStyle(.red)
            }
        }
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button("Export") {
                guard let destination else { return }
                Task {
                    await model.exportVault(format: format, destination: destination,
                                            password: format == .encryptedImage ? password : nil,
                                            rememberInKeychain: remember && format == .encryptedImage)
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canExport)
        }
    }

    private func isValidDestination(_ url: URL?) -> Bool {
        guard let url else { return false }
        switch format {
        case .folder: return url.hasDirectoryPath || url.pathExtension.isEmpty
        case .zip: return url.pathExtension.lowercased() == "zip"
        case .encryptedImage: return url.pathExtension.lowercased() == "dmg"
        }
    }

    private func chooseDestination() -> URL? {
        switch format {
        case .folder: Panels.chooseFolders(message: "Choose where to create the vault folder", allowsMultiple: false).first
        case .zip: Panels.saveLocation(name: "Sweepkey Vault.zip", message: "Save the vault archive")
        case .encryptedImage: Panels.saveLocation(name: "Sweepkey Vault.dmg", message: "Save the encrypted vault image")
        }
    }
}

#Preview {
    VaultExportSheet().environment(\.appModel, AppModel())
}
