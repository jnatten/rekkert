import RekkertCore
import SwiftUI

/// One of the two big numbers. Tap scores a point, long press undoes.
struct ScoreButton: View {
    let side: TeamSide
    let value: String
    let teamName: String
    let isServing: Bool
    let servingCourt: ServeCourt?
    let isEnabled: Bool
    var compact = false
    let onTap: () -> Void
    let onUndo: () -> Void

    private func serveSlot(showing isThisEnd: Bool) -> some View {
        ServeSideSlot(
            court: isServing && isThisEnd ? servingCourt : nil,
            // Team B is the far end, so their court is drawn as you see it.
            fromAcrossTheNet: side == .b,
            height: compact ? 10 : 13,
            showsLabel: !compact
        )
        .foregroundStyle(.white.opacity(0.9))
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color.team(side)
                VStack(spacing: compact ? 0 : 6) {
                    if !compact {
                        HStack(spacing: 6) {
                            if isServing {
                                Image(systemName: "circle.fill").font(.system(size: 7))
                            }
                            Text(teamName)
                        }
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    }

                    // Above the number for them, below it for us — the same way round as
                    // the court in front of you, where their end is the far one.
                    serveSlot(showing: side == .b)

                    Text(value)
                        .font(.system(size: compact ? 64 : 120, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    serveSlot(showing: side == .a)
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
