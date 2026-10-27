import CleanerKit
import SwiftUI

struct FreeUpRecipeView: View {
    @Environment(AppModel.self) private var model
    @State private var targetGB = 10.0
    @State private var plan: [Candidate] = []
    @State private var isPlanning = false
    @State private var hasPlanned = false

    private var planned: Int64 { plan.reduce(0) { $0 + $1.sizeBytes } }
    private var target: Int64 { Int64(targetGB * 1_073_741_824) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView("Free up \(Int(targetGB)) GB", symbolName: "wand.and.stars")
            Text("Picks the safest items first: stale projects, then caches, then other projects. You review the list before anything is deleted.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Slider(value: $targetGB, in: 1...200, step: 1)
                TextField("GB", value: $targetGB, format: .number.precision(.fractionLength(0)))
                    .frame(width: 60).multilineTextAlignment(.trailing)
                Text("GB")
            }
            HStack {
                Button("Plan", systemImage: "list.bullet.clipboard") {
                    Task {
                        isPlanning = true
                        plan = await model.planFreeUp(targetBytes: target)
                        hasPlanned = true
                        isPlanning = false
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isPlanning || model.scanState.isScanning || targetGB < 1)
                if isPlanning { ProgressView().controlSize(.small) }
            }
            if hasPlanned {
                if plan.isEmpty {
                    Text("Nothing safe to clean.").foregroundStyle(.secondary)
                } else {
                    if planned < target {
                        Label("Only \(SizeFormat.string(planned)) can be freed safely.", systemImage: "info.circle")
                            .foregroundStyle(.orange)
                    }
                    TopOffendersList(candidates: plan)
                    HStack {
                        Text("\(plan.count) items · \(SizeFormat.string(planned))").monospacedDigit()
                        Spacer()
                        Button("Review and clean…", systemImage: "trash") { model.reviewForCleaning(plan) }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
        }
    }
}

#Preview {
    FreeUpRecipeView().environment(AppModel()).padding().frame(width: 700)
}
