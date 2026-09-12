import RekkertCore
import SwiftUI

struct ScoreboardView: View {
    let snapshot: ScoreboardSnapshot
    var compact = false
    let onTap: (TeamSide) -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: compact ? 2 : 4) {
                ForEach(TeamSide.allCases, id: \.self) { side in
                    ScoreButton(
                        side: side,
                        value: snapshot.primary[side],
                        teamName: snapshot.teamNames[side],
                        isServing: snapshot.serving == side,
                        isEnabled: !snapshot.isLocked,
                        compact: compact,
                        onTap: { onTap(side) },
                        onUndo: onUndo
                    )
                }
            }
            if let games = snapshot.games {
                gameLine(games)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if !compact {
            VStack(spacing: 2) {
                if let label = snapshot.courtLabel {
                    Text(label).font(.subheadline.weight(.semibold))
                }
                Text(snapshot.detail)
                    .font(.caption)
                    .foregroundStyle(snapshot.isSuddenDeath ? Color.orange : .secondary)
            }
            .padding(.vertical, 6)
        } else {
            Text(snapshot.detail)
                .font(.system(size: 11))
                .foregroundStyle(snapshot.isSuddenDeath ? Color.orange : .secondary)
                .lineLimit(1)
        }
    }

    private func gameLine(_ games: BySide<Int>) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(snapshot.completedSets.enumerated()), id: \.offset) { _, set in
                    Text("\(set.games.a)-\(set.games.b)")
                        .foregroundStyle(.secondary)
                }
                Text("\(games.a)-\(games.b)")
                    .fontWeight(.semibold)
            }
            .font(compact ? .system(size: 12).monospacedDigit() : .callout.monospacedDigit())
            .padding(.horizontal, compact ? 4 : 16)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
        .padding(.top, compact ? 2 : 8)
        .padding(.bottom, compact ? 2 : 28)
    }
}
