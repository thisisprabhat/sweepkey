import SweepkeyKit
import SwiftUI

struct RuleEditorSheet: View {
    @Environment(\.appModel) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var ecosystemID = "generic"
    @State private var markers: [String] = []
    @State private var target = ""
    @State private var risk = RiskLevel.caution
    @State private var regenerate = ""

    private var draft: Rule {
        let hint = regenerate.trimmingCharacters(in: .whitespaces)
        return Rule(
            id: id.trimmingCharacters(in: .whitespaces), ecosystemID: ecosystemID, markers: markers,
            target: target.trimmingCharacters(in: .whitespaces), risk: risk, enabledByDefault: true,
            regenerate: hint.isEmpty ? nil : hint)
    }

    /// The same validation the engine applies to every rule (`RuleSet.validate`), plus the
    /// editor's id conventions.
    private var problems: [String] {
        let rule = draft
        var result = RuleSet(rules: model.allRules).validate(rule)
        if !rule.id.isEmpty {
            if !rule.id.contains(".") { result.append("The id should look like ecosystem.name.") }
            else if model.allRules.contains(where: { $0.id == rule.id }) { result.append("A rule with this id already exists.") }
        }
        return result
    }

    /// Reads the draft back as a sentence so the user can check it before saving.
    private var preview: String? {
        let rule = draft
        guard !rule.markers.isEmpty, !rule.target.isEmpty else { return nil }
        var sentence = "In any folder that contains \(rule.markers.joined(separator: " or ")), Sweepkey will offer \(rule.target) for cleaning"
        if let regenerate = rule.regenerate { sentence += ". You can rebuild it with \(regenerate)" }
        return sentence + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Cleaning Rule").font(.title2.weight(.semibold))
                    Text("Teach Sweepkey about a folder that a tool can rebuild.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fill In an Example", systemImage: "text.badge.plus") { fillExample() }
                    .buttonStyle(.glass)
                    .help("Fills the form with a Flutter build-folder rule you can edit")
            }
            Form {
                Section {
                    LabeledContent("Markers") { StringListEditor(prompt: "File name or glob", items: $markers) }
                    Text("Files that identify the project. The rule only applies in a folder that contains at least one, e.g. pubspec.yaml or *.csproj.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Target", text: $target, prompt: Text("build"))
                    Text("The folder to clean, relative to the project, e.g. build or ios/Pods. The last part may be a glob.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Regenerate", text: $regenerate, prompt: Text("flutter build"))
                    Text("Optional: the command that rebuilds the folder. It is shown next to the item so you know how to get it back.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("What to clean") }
                Section {
                    Picker("Ecosystem", selection: $ecosystemID) {
                        ForEach(Ecosystem.builtIn) { Text($0.name).tag($0.id) }
                    }
                    Picker("Risk", selection: $risk) {
                        ForEach(RiskLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Safe: always rebuildable. Caution: usually rebuildable, check first. Danger: may hold work you cannot get back.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Id", text: $id, prompt: Text("flutter.build"))
                    Text("A unique name in the form ecosystem.name.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Details") }
            }
            .formStyle(.grouped)
            if let preview {
                Label(preview, systemImage: "text.quote")
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.tint.opacity(0.1), in: .rect(cornerRadius: 8))
            }
            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Rule") { save() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!problems.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func fillExample() {
        id = "flutter.example_build"
        ecosystemID = "flutter"
        markers = ["pubspec.yaml"]
        target = "build"
        risk = .safe
        regenerate = "flutter build"
    }

    private func save() {
        guard problems.isEmpty else { return }
        model.settings.customRules.append(draft)
        dismiss()
    }
}

#Preview {
    RuleEditorSheet().environment(\.appModel, AppModel())
}
