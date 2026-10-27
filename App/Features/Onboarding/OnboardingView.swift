import SwiftUI

/// Four-step paged flow without TabView: Welcome, roots, Full Disk Access, first scan.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: OnboardingWelcomeStep()
                case 1: OnboardingRootsStep()
                case 2: OnboardingAccessStep()
                default: OnboardingScanStep()
                }
            }
            .frame(maxWidth: 520, maxHeight: .infinity)
            .padding(32)
            .id(step)
            .transition(.push(from: .trailing))

            HStack {
                Button("Back") { go(step - 1) }.opacity(step == 0 ? 0 : 1).disabled(step == 0)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { Circle().fill($0 == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7) }
                }
                .accessibilityHidden(true)
                Spacer()
                if step < lastStep {
                    Button("Continue") { go(step + 1) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 1 && model.settings.scanRoots.isEmpty)
                } else {
                    Button("Finish") { model.settings.hasCompletedOnboarding = true }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 520)
        .clipped()
    }

    private func go(_ target: Int) {
        withAnimation(.smooth) { step = min(max(target, 0), lastStep) }
    }
}

#Preview {
    OnboardingView().environment(AppModel())
}
