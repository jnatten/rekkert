import RekkertCore
import SwiftUI

/// One of the two big numbers. Tap scores a point, long press undoes.
struct ScoreButton: View {
    @Environment(\.teamPalette) private var palette
    @Environment(\.nearTeam) private var nearTeam
    let side: TeamSide
    let value: String
    let teamName: String
    let isServing: Bool
    let servingCourt: ServeCourt?
    /// Who on this side is serving, when the line-up is known.
    var servingPlayer: String? = nil
    let isEnabled: Bool
    var compact = false
    /// Off on a watch that scores from the whole page instead, which takes the taps itself.
    var takesTaps = true
    let onTap: () -> Void
    let onUndo: () -> Void

    /// On the watch this is how you tell which pair you are — a tournament court names
    /// the two teams by their players, and there is nothing else on screen that does.
    private var teamLabel: some View {
        HStack(spacing: 6) {
            if isServing, !compact {
                Image(systemName: "circle.fill").font(.system(size: 7))
            }
            Text(teamName)
        }
        .font(compact ? .system(size: 11, weight: .semibold) : .headline)
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(compact ? 0.5 : 1)
    }

    private func serveSlot(showing isThisEnd: Bool) -> some View {
        ServeSideSlot(
            court: isServing && isThisEnd ? servingCourt : nil,
            playerName: namedServer,
            // The other team is the far end, so their court is drawn as you see it.
            fromAcrossTheNet: side != nearTeam,
            height: compact ? 10 : 13
        )
        .foregroundStyle(.white.opacity(0.9))
    }

    /// In singles the team is the player, and that name is already on the line above.
    private var namedServer: String? {
        guard isServing, let servingPlayer, servingPlayer != teamName else { return nil }
        return servingPlayer
    }

    private var face: some View {
        ZStack {
            palette.color(side)
            VStack(spacing: compact ? 0 : 6) {
                teamLabel

                // Above the number for them, below it for us — the same way round as
                // the court in front of you, where their end is the far one.
                serveSlot(showing: side != nearTeam)

                Text(value)
                    .font(.system(size: compact ? 54 : 120, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                serveSlot(showing: side == nearTeam)
            }
            .padding(compact ? 4 : 12)
        }
    }

    @ViewBuilder
    private var control: some View {
        if takesTaps {
            Button(action: onTap) { face }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.55)
                .contentShape(.rect)
                .onLongPressGesture(perform: onUndo)
                .accessibilityHint(isEnabled ? "Double tap to add a point" : "Scoring is closed")
        } else {
            face.opacity(isEnabled ? 1 : 0.55)
        }
    }

    var body: some View {
        control
            .accessibilityLabel(
                isServing
                    ? "\(teamName), \(value), \(servingPlayer.map { "\($0) serving" } ?? "serving")"
                    : "\(teamName), \(value)"
            )
            .animation(.snappy, value: value)
    }
}
