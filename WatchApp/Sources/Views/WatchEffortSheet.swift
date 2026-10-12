import RekkertCore
import SwiftUI
import WatchKit

struct WatchEffortSheet: View {
    @Environment(AppModel.self) private var model
    @State private var crown = 0.0
    @State private var score: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(score.map(WorkoutEffortStyle.color) ?? .secondary)
                    .contentTransition(.numericText())
                Text(score.map { WorkoutEffort(score: $0).title } ?? "Turn the crown")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                EffortScale(score: $score, height: 10, spacing: 2)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .focusable()
            .digitalCrownRotation(
                $crown,
                from: Double(WorkoutEffort.range.lowerBound),
                through: Double(WorkoutEffort.range.upperBound),
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crown) { _, value in
                let step = Int(value.rounded())
                if WorkoutEffort.range.contains(step), step != score { withAnimation { score = step } }
            }
            .onChange(of: score) { _, value in
                if let value, Int(crown.rounded()) != value { crown = Double(value) }
            }
            .navigationTitle("Effort")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", systemImage: "xmark") { model.workout.skipEffort() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        guard let score else { return }
                        WKInterfaceDevice.current().play(.success)
                        model.workout.rate(score)
                    }
                    .tint(score.map(WorkoutEffortStyle.color) ?? .gray)
                    .disabled(score == nil)
                }
            }
        }
    }
}
