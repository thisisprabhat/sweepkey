import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 64)).foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Welcome to Cleaner").font(.largeTitle.weight(.semibold))
            Text("Reclaim disk space from build artifacts and caches that can be regenerated, and keep un-committed secrets safe in a vault.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Cleaner never deletes anything without your confirmation.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

#Preview { OnboardingWelcomeStep().padding() }
