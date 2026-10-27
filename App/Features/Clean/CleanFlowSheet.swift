import SwiftUI

/// Hosts confirm -> progress -> result inside one sheet.
struct CleanFlowSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.cleanPhase {
            case .idle, .confirming: CleanConfirmationSheet()
            case .running(let progress): CleanProgressView(progress: progress)
            case .finished(let report): CleanResultView(report: report)
            }
        }
        .frame(width: 560)
        .frame(minHeight: 360)
        .interactiveDismissDisabled(isRunning)
    }

    private var isRunning: Bool {
        if case .running = model.cleanPhase { return true }
        return false
    }
}
