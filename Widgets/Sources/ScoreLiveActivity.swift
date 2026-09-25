import ActivityKit
import RekkertCore
import SwiftUI
import WidgetKit

struct ScoreLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScoreActivityAttributes.self) { context in
            LockScreenOrWrist(score: context.state)
        } dynamicIsland: { context in
            let score = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        LiveHeader(score: score)
                        LiveBody(score: score)
                    }
                }
            } compactLeading: {
                CompactSide(score: score, position: 0)
            } compactTrailing: {
                CompactSide(score: score, position: 1)
            } minimal: {
                Minimal(score: score)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct LockScreenOrWrist: View {
    let score: LiveScore
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            LiveScoreSmall(score: score)
        } else {
            LiveScoreLockScreen(score: score)
        }
    }
}

/// The two halves of the pill: the points either side of the camera, or for a tournament
/// the round on one side and its clock on the other.
private struct CompactSide: View {
    let score: LiveScore
    let position: Int

    var body: some View {
        if score.isTournament {
            if position == 0 {
                Text(score.round.map { "R\($0)" } ?? "–").fontWeight(.semibold)
            } else if let start = score.clockStart {
                LiveClock(start: start).frame(width: 44)
            } else {
                Text("\(score.boards.filter(\.isDone).count)/\(score.boards.count)").monospacedDigit()
            }
        } else if let board = score.boards.first {
            let side = score.order[position]
            Text(board.points[side])
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(score.palette.color(side))
        }
    }
}

private struct Minimal: View {
    let score: LiveScore

    var body: some View {
        Group {
            if score.isTournament {
                Text(score.round.map { "R\($0)" } ?? "–")
            } else if let board = score.boards.first {
                Text(board.games.map(score.pair) ?? score.pair(board.points))
            }
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .minimumScaleFactor(0.5)
    }
}

#if DEBUG
private extension LiveScore {
    static let match = LiveScore(
        kind: .traditional,
        title: "Us vs Them",
        symbol: "figure.tennis",
        detail: "Set 2",
        clockStart: Date().addingTimeInterval(-47 * 60),
        boards: [Board(
            names: BySide(a: "Us", b: "Them"),
            points: BySide(a: "40", b: "30"),
            games: BySide(a: 3, b: 2),
            sets: [SetResult(games: BySide(a: 6, b: 4), tiebreak: nil, winner: .a)],
            serving: .a
        )]
    )

    static let americano = LiveScore(
        kind: .tournament,
        title: "Thursday americano",
        symbol: "arrow.triangle.2.circlepath",
        detail: "Round 3",
        round: 3,
        clockStart: Date().addingTimeInterval(-9 * 60),
        boards: [
            Board(label: "Court 1", names: BySide(a: "Ada & Kim", b: "Sam & Tor"), points: BySide(a: "12", b: "9")),
            Board(label: "Court 2", names: BySide(a: "Ola & Siri", b: "Jonas & Bjørn"), points: BySide(a: "16", b: "5"), isDone: true),
        ],
        leaders: [Leader(name: "Ada", total: 45), Leader(name: "Kim", total: 41), Leader(name: "Sam", total: 38)]
    )
}

#Preview("Lock Screen", as: .content, using: ScoreActivityAttributes(sessionID: UUID())) {
    ScoreLiveActivity()
} contentStates: {
    LiveScore.match
    LiveScore.americano
}

#Preview("Compact", as: .dynamicIsland(.compact), using: ScoreActivityAttributes(sessionID: UUID())) {
    ScoreLiveActivity()
} contentStates: {
    LiveScore.match
    LiveScore.americano
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: ScoreActivityAttributes(sessionID: UUID())) {
    ScoreLiveActivity()
} contentStates: {
    LiveScore.match
    LiveScore.americano
}
#endif
