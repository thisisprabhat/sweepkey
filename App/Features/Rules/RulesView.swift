import CleanerKit
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editorPresented = false

    var body: some View {
        let rules = model.allRules
        let ecosystems = Ecosystem.builtIn.filter { eco in rules.contains { $0.ecosystemID == eco.id } }
        List {
            ForEach(ecosystems) { eco in
                Section {
                    ForEach(rules.filter { $0.ecosystemID == eco.id }) { rule in
                        RuleRow(rule: rule)
                    }
                } header: {
                    Label(eco.name, systemImage: eco.symbolName)
                }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem {
                Button("Add Rule", systemImage: "plus") { editorPresented = true }
            }
        }
        .sheet(isPresented: $editorPresented) { RuleEditorSheet() }
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: Rule

    private var isCustom: Bool { model.settings.customRules.contains { $0.id == rule.id } }

    var body: some View {
        HStack {
            Toggle(rule.id, isOn: Binding(
                get: { model.isRuleEnabled(rule) }, set: { model.setRule(rule, enabled: $0) }))
            Spacer()
            Text(rule.target).font(.caption.monospaced()).foregroundStyle(.secondary)
            RiskBadge(risk: rule.risk)
            if isCustom {
                Button("Delete", systemImage: "trash") {
                    model.settings.customRules.removeAll { $0.id == rule.id }
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        }
        .help(rule.note ?? rule.regenerate.map { "Regenerate: \($0)" } ?? "")
    }
}

#Preview {
    RulesView().environment(AppModel()).frame(width: 640, height: 520)
}
