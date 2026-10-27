import AppKit
import SwiftUI

struct OnboardingAccessStep: View {
    @State private var granted: Bool?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.open.display").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Full Disk Access").font(.title.weight(.semibold))
            Text("To scan caches and protected folders, Sweepkey needs Full Disk Access. Open System Settings, enable Sweepkey under Privacy & Security, then come back and check again.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Button("Open System Settings", systemImage: "gearshape") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
                Button("Check Again", systemImage: "arrow.clockwise") { granted = Self.hasAccess() }
                    .buttonStyle(.glass)
            }
            if let granted {
                Label(granted ? "Access granted" : "Not granted yet — you can still continue",
                      systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? Color.green : Color.orange)
            }
        }
        .task { granted = Self.hasAccess() }
    }

    /// Full Disk Access is granted when ~/Library/Safari is readable.
    static func hasAccess() -> Bool {
        let safari = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: safari.path)) != nil
    }
}

#Preview { OnboardingAccessStep().padding().frame(width: 520, height: 400) }
