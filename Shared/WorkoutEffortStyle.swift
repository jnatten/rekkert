import RekkertCore
import SwiftUI

/// A finished workout waiting to be rated.
struct EffortQuestion: Identifiable, Hashable {
    let id: UUID
    var startedAt: Date?
    var effort: Int?
}

enum WorkoutEffortStyle {
    static func color(_ score: Int) -> Color {
        switch WorkoutEffort(score: score) {
        case .easy: .green
        case .moderate: .yellow
        case .hard: .orange
        case .allOut: .red
        }
    }

    static func label(_ score: Int) -> String {
        "\(score) · \(WorkoutEffort(score: score).title)"
    }
}

/// The ten steps in a row, lit up to the one picked. Tapping one picks it.
struct EffortScale: View {
    @Binding var score: Int?
    var height: CGFloat = 12
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(WorkoutEffort.range, id: \.self) { step in
                Capsule()
                    .fill(WorkoutEffortStyle.color(step))
                    .opacity(step <= (score ?? 0) ? 1 : 0.2)
                    .frame(height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { score = step }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Effort")
        .accessibilityValue(score.map(WorkoutEffortStyle.label) ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: score = min((score ?? 0) + 1, WorkoutEffort.range.upperBound)
            case .decrement: score = max((score ?? 2) - 1, WorkoutEffort.range.lowerBound)
            @unknown default: break
            }
        }
    }
}
