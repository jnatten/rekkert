import RekkertCore
import SwiftUI

struct EffortSheet: View {
    let question: EffortQuestion
    let onRate: (Int) -> Void
    let onSkip: () -> Void
    @State private var score: Int?

    init(question: EffortQuestion, onRate: @escaping (Int) -> Void, onSkip: @escaping () -> Void) {
        self.question = question
        self.onRate = onRate
        self.onSkip = onSkip
        _score = State(initialValue: question.effort)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let startedAt = question.startedAt {
                    Text("Padel · \(startedAt.formatted(.dateTime.weekday(.wide).hour().minute()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 2) {
                    Text(score.map(String.init) ?? "–")
                        .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(score.map(WorkoutEffortStyle.color) ?? .secondary)
                        .contentTransition(.numericText())
                    Text(score.map { WorkoutEffort(score: $0).title } ?? "Tap to rate")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .animation(.snappy, value: score)

                EffortScale(score: $score, height: 28, spacing: 4)
                    .sensoryFeedback(.selection, trigger: score)
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .navigationTitle("How hard was that?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let score { onRate(score) }
                    }
                    .disabled(score == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
