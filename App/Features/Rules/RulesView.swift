import SweepkeyKit
import SwiftUI

struct RulesView: View {
    @Environment(\.appModel) private var model
    @State private var editorPresented = false
    @AppStorage("rules.helpHidden") private var helpHidden = false

    var body: some View {
        let rules = model.allRules
        let ecosystems = Ecosystem.builtIn.filter { eco in rules.contains { $0.ecosystemID == eco.id } }
        List {
            if !helpHidden {
                Section { RulesHelpCard(onAdd: { editorPresented = true }, onHide: { withAnimation { helpHidden = true } }) }
            }
            ForEach(ecosystems) { eco in
                Section {
                    ForEach(rules.filter { $0.ecosystemID == eco.id }) { rule in
                        RuleRow(rule: rule)
                    }
                } header: {
                    HStack(spacing: 8) {
                        EcosystemIcon(ecosystemID: eco.id, size: 20)
                        Text(eco.name)
                    }
                }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItem {
                Button("How Rules Work", systemImage: "questionmark.circle") { withAnimation { helpHidden.toggle() } }
                    .help("Show or hide the explanation of rules")
            }
            ToolbarItem {
                Button("Add Rule", systemImage: "plus") { editorPresented = true }
                    .help("Create your own cleaning rule")
            }
        }
        .sheet(isPresented: $editorPresented) { RuleEditorSheet() }
        .task { if AppRuntime.demoPresent == "ruleEditor" { editorPresented = true } }
    }
}

/// What a rule is, in one glance: marker -> target -> regenerate, with the bundled Rust rule as the example.
private struct RulesHelpCard: View {
    let onAdd: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("How rules work", systemImage: "lightbulb").font(.headline)
                Spacer()
                Button("Hide", systemImage: "xmark") { onHide() }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            Text("A rule tells Sweepkey which folder inside a project can be deleted because a tool can rebuild it. Each rule has three parts:")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                step("1", "Marker", "A file that identifies the project type.", example: "Cargo.toml")
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 22)
                step("2", "Target", "The folder to offer for cleaning, relative to the project.", example: "target")
                Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 22)
                step("3", "Regenerate", "The command that brings it back.", example: "cargo build")
            }
            Text("Use the switches below to turn rules on or off. Folders that git tracks are never deleted, whatever a rule says.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Add Your Own Rule…", systemImage: "plus", action: onAdd).buttonStyle(.glass)
        }
        .padding(4)
    }

    private func step(_ number: String, _ title: String, _ detail: String, example: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number). \(title)").font(.callout.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(example).font(.caption.monospaced())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RuleRow: View {
    @Environment(\.appModel) private var model
    let rule: Rule

    private var isCustom: Bool { model.settings.customRules.contains { $0.id == rule.id } }

    /// "In folders with Cargo.toml · rebuild with cargo build"
    private var summary: String {
        var parts = ["In folders with \(rule.markers.joined(separator: " or "))"]
        if let regenerate = rule.regenerate { parts.append("rebuild with \(regenerate)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { model.isRuleEnabled(rule) }, set: { model.setRule(rule, enabled: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.target).font(.body.monospaced())
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            Spacer()
            if isCustom { Text("Custom").font(.caption2.weight(.semibold)).foregroundStyle(.tint) }
            RiskBadge(risk: rule.risk)
            if isCustom {
                Button("Delete", systemImage: "trash") {
                    model.settings.customRules.removeAll { $0.id == rule.id }
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        }
        .help(rule.note.map { "\(rule.id): \($0)" } ?? rule.id)
    }
}

#Preview {
    RulesView().environment(\.appModel, AppModel()).frame(width: 640, height: 520)
}
