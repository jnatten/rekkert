import RekkertCore
import SwiftUI
import WidgetKit

extension LiveScore {
    var order: [TeamSide] { leftSide == .a ? [.a, .b] : [.b, .a] }
    var palette: TeamPalette { TeamPalette(isSwapped: colorsSwapped) }
    var isTournament: Bool { kind == .tournament }
    var isSuddenDeath: Bool { boards.first?.isSuddenDeath ?? false }

    /// "4–3", read the way the phone's own board reads it.
    func pair<Value>(_ value: BySide<Value>) -> String {
        "\(value[order[0]])–\(value[order[1]])"
    }
}

/// Counted by the system, so it keeps going between updates. Clamped to now for the same
/// reason as the board's: the start is another device's stamp.
struct LiveClock: View {
    let start: Date

    var body: some View {
        Text(timerInterval: min(start, Date()) ... .distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

/// The clock where nothing gives it a width. `fixedSize()` would, but a Live Activity lays a
/// fixed-size timer out so wide that nothing after it is drawn; a stand-in as wide as the
/// clock gets is measured instead.
struct SizedLiveClock: View {
    let start: Date

    var body: some View {
        Text(verbatim: "0:00:00")
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) { LiveClock(start: start) }
    }
}

struct LiveScoreLockScreen: View {
    let score: LiveScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveHeader(score: score)
            LiveBody(score: score)
        }
        .padding(16)
    }
}

struct LiveHeader: View {
    let score: LiveScore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: score.symbol)
            Text(score.title).fontWeight(.semibold).lineLimit(1)
            Spacer(minLength: 4)
            Text(score.detail)
                .foregroundStyle(score.isSuddenDeath ? Color.orange : .secondary)
                .lineLimit(1)
            if let start = score.clockStart {
                Text(verbatim: "·").foregroundStyle(.secondary)
                SizedLiveClock(start: start).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

struct LiveBody: View {
    let score: LiveScore

    var body: some View {
        if let result = score.result {
            Label(result, systemImage: "trophy.fill")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        if score.isTournament {
            if !score.isOver {
                CourtsSummary(score: score)
            }
            LeadersLine(leaders: score.leaders)
        } else if let board = score.boards.first {
            Scorebug(score: score, board: board)
        }
    }
}

/// Two rows, one per side, the left of the phone's board on top. Stacks with fixed columns
/// rather than a `Grid`, which lays out a NaN origin when the host measures the height.
struct Scorebug: View {
    let score: LiveScore
    let board: LiveScore.Board

    var body: some View {
        VStack(spacing: 4) {
            ForEach(score.order, id: \.self) { side in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(score.palette.color(side))
                        .frame(width: 4, height: 24)
                    HStack(spacing: 5) {
                        Text(board.names[side]).lineLimit(1)
                        if board.serving == side {
                            Image(systemName: "circle.fill").font(.system(size: 7))
                        }
                        if board.winner == side {
                            Image(systemName: "checkmark").font(.caption.weight(.bold))
                        }
                    }
                    .font(.headline)
                    Spacer(minLength: 8)
                    ForEach(Array(board.sets.enumerated()), id: \.offset) { _, set in
                        Text("\(set.games[side])")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }
                    if let games = board.games {
                        Text("\(games[side])")
                            .fontWeight(.semibold)
                            .frame(width: 20)
                    }
                    Text(board.points[side])
                        .font(.title2.weight(.bold))
                        .frame(width: 48, alignment: .trailing)
                }
                .monospacedDigit()
            }
        }
    }
}

struct CourtsSummary: View {
    let score: LiveScore

    var body: some View {
        if score.boards.count <= 3 {
            VStack(spacing: 4) {
                ForEach(Array(score.boards.enumerated()), id: \.offset) { _, board in
                    courtRow(board)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(stride(from: 0, to: score.boards.count, by: 4)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(start ..< min(start + 4, score.boards.count), id: \.self) { index in
                            chip(score.boards[index], number: index + 1)
                        }
                    }
                }
            }
        }
    }

    private func courtRow(_ board: LiveScore.Board) -> some View {
        HStack(spacing: 8) {
            Text(board.label ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(board.names[score.order[0]])
                .foregroundStyle(score.palette.color(score.order[0]))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(score.pair(board.points))
                .fontWeight(.bold)
                .monospacedDigit()
                .fixedSize()
            Text(board.names[score.order[1]])
                .foregroundStyle(score.palette.color(score.order[1]))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .opacity(board.isDone ? 1 : 0)
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    private func chip(_ board: LiveScore.Board, number: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(number)").foregroundStyle(.secondary)
            Text(score.pair(board.points)).fontWeight(.semibold)
            if board.isDone {
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
            }
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

struct LeadersLine: View {
    let leaders: [LiveScore.Leader]

    var body: some View {
        if !leaders.isEmpty {
            Text(leaders.enumerated().map { "\($0.offset + 1). \($0.element.name) \($0.element.total)" }
                .joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The watch's Smart Stack, which has room for a title and two numbers and no more.
struct LiveScoreSmall: View {
    let score: LiveScore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(score.isTournament ? score.title : score.detail).lineLimit(1)
                Spacer(minLength: 2)
                if let start = score.clockStart {
                    SizedLiveClock(start: start)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let result = score.result {
                Text(result).font(.headline).lineLimit(2).minimumScaleFactor(0.6)
            } else if score.isTournament {
                Text(score.boards.map { score.pair($0.points) }.joined(separator: "  "))
                    .font(.headline.monospacedDigit())
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            } else if let board = score.boards.first {
                HStack(spacing: 6) {
                    ForEach(score.order, id: \.self) { side in
                        Text(board.points[side])
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(score.palette.color(side))
                            .frame(maxWidth: .infinity)
                    }
                }
                if let games = board.games {
                    Text(score.pair(games))
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(8)
    }
}
