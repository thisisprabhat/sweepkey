import CleanerKit
import SwiftUI

struct RuleEditorSheet: View {
    @Environment(AppModel.self) private var model
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom Rule").font(.title2.weight(.semibold))
            Form {
                TextField("Id", text: $id, prompt: Text("custom.build"))
                Picker("Ecosystem", selection: $ecosystemID) {
                    ForEach(Ecosystem.builtIn) { Text($0.name).tag($0.id) }
                }
                LabeledContent("Markers") { StringListEditor(prompt: "File name or glob", items: $markers) }
                TextField("Target", text: $target, prompt: Text("build"))
                Picker("Risk", selection: $risk) {
                    ForEach(RiskLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Regenerate", text: $regenerate, prompt: Text("make build"))
            }
            .formStyle(.grouped)
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
        .frame(width: 480)
    }

    private func save() {
        guard problems.isEmpty else { return }
        model.settings.customRules.append(draft)
        dismiss()
    }
}

#Preview {
    RuleEditorSheet().environment(AppModel())
}
