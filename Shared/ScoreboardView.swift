import RekkertCore
import SwiftUI

struct ScoreboardView<Badge: View>: View {
    let snapshot: ScoreboardSnapshot
    var compact = false
    var layout = ScoreboardLayout(isMirrored: false)
    let onTap: (TeamSide) -> Void
    let onUndo: () -> Void
    /// Rides along at the leading end of the compact header — the watch puts a running
    /// workout there. In the layout rather than laid over it: an overlay taller than the
    /// line it sits on dips into the colour of the button below, and no amount of shrinking
    /// it is a fix, because the badge grows when it has a number to show.
    @ViewBuilder var badge: () -> Badge

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: compact ? 2 : 4) {
                ForEach(layout.order, id: \.self) { side in
                    ScoreButton(
                        side: side,
                        value: snapshot.primary[side],
                        teamName: snapshot.teamNames[side],
                        isServing: snapshot.serving == side,
                        servingCourt: snapshot.servingCourt,
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
            HStack(spacing: 4) {
                badge()
                Text(snapshot.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(snapshot.isSuddenDeath ? Color.orange : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                // The far end is where the watch draws the dots for the page below this one,
                // at exactly this height. A line pushed across by a badge has to stop short
                // of them rather than run underneath.
                Color.clear.frame(width: 10, height: 0)
            }
        }
    }

    private func gameLine(_ games: BySide<Int>) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(snapshot.completedSets.enumerated()), id: \.offset) { _, set in
                    let shown = layout.asShown(set.games)
                    Text("\(shown.left)-\(shown.right)")
                        .foregroundStyle(.secondary)
                }
                let current = layout.asShown(games)
                Text("\(current.left)-\(current.right)")
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

/// The phones, which have nothing to put up there. Spelled as its own initialiser so five
/// call sites do not have to pass an empty closure to say so.
extension ScoreboardView where Badge == EmptyView {
    init(
        snapshot: ScoreboardSnapshot,
        compact: Bool = false,
        layout: ScoreboardLayout = ScoreboardLayout(isMirrored: false),
        onTap: @escaping (TeamSide) -> Void,
        onUndo: @escaping () -> Void
    ) {
        self.init(
            snapshot: snapshot,
            compact: compact,
            layout: layout,
            onTap: onTap,
            onUndo: onUndo,
            badge: { EmptyView() }
        )
    }
}
