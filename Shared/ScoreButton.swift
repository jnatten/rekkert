import RekkertCore
import SwiftUI

/// One of the two big numbers. Tap scores a point, long press undoes.
struct ScoreButton: View {
    let side: TeamSide
    let value: String
    let teamName: String
    let isServing: Bool
    let isEnabled: Bool
    var compact = false
    let onTap: () -> Void
    let onUndo: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color.team(side)
                VStack(spacing: compact ? 0 : 6) {
                    if !compact {
                        Label {
                            Text(teamName)
                        } icon: {
                            if isServing { Image(systemName: "circle.fill").font(.system(size: 7)) }
                        }
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    }

                    Text(value)
                        .font(.system(size: compact ? 64 : 120, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    if compact, isServing {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(compact ? 4 : 12)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .contentShape(.rect)
        .onLongPressGesture(perform: onUndo)
        .accessibilityLabel("\(teamName), \(value)")
        .accessibilityHint(isEnabled ? "Double tap to add a point" : "Scoring is closed")
        .animation(.snappy, value: value)
    }
}
