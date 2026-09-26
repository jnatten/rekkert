import RekkertCore
import SwiftUI

struct BoardCourtsView: View {
    let board: TVBoard
    let courts: [TVBoard.Court]
    let metrics: BoardMetrics

    private var unit: CGFloat { metrics.unit }
    private var spacing: CGFloat { 20 * unit }

    var body: some View {
        let isLandscape = metrics.isLandscape
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 24 * unit))
            : AnyLayout(VStackLayout(spacing: 24 * unit))

        VStack(spacing: 24 * unit) {
            layout {
                GeometryReader { geometry in
                    grid(in: geometry.size)
                }
                if !board.standings.isEmpty, !isLandscape || metrics.size.width >= 900 {
                    BoardStandings(standings: board.standings, metrics: metrics)
                        .frame(
                            width: isLandscape ? metrics.size.width * 0.26 : nil,
                            height: isLandscape ? nil : metrics.size.height * 0.3
                        )
                }
            }
            if !board.sittingOut.isEmpty {
                Text("Sitting out: \(board.sittingOut.joined(separator: ", "))")
                    .font(metrics.font(40))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func grid(in size: CGSize) -> some View {
        let columns = Self.columns(for: courts.count, in: size, spacing: spacing)
        let rows = max(1, (courts.count + columns - 1) / columns)
        let card = CGSize(
            width: max(0, (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)),
            height: max(0, (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
        )

        return VStack(spacing: spacing) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(courts[row * columns ..< min((row + 1) * columns, courts.count)]) { court in
                        BoardCourtCard(court: court, leftSide: board.leftSide, size: card, unit: unit)
                            .frame(width: card.width, height: card.height)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The column count that leaves each card the most room at the shape a card reads best.
    static func columns(for count: Int, in size: CGSize, spacing: CGFloat) -> Int {
        guard count > 1 else { return 1 }
        let aspect: CGFloat = 1.5
        func fit(_ columns: Int) -> CGFloat {
            let rows = (count + columns - 1) / columns
            let width = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            return min(width / aspect, height)
        }
        return (1 ... count).max { fit($0) < fit($1) } ?? 1
    }
}

private struct BoardCourtCard: View {
    @Environment(\.teamPalette) private var palette
    let court: TVBoard.Court
    let leftSide: TeamSide
    let size: CGSize
    let unit: CGFloat

    private var headerHeight: CGFloat { min(size.height * 0.16, 64 * unit) }
    private var rowHeight: CGFloat { max(0, (size.height - headerHeight - gap * 3) / 2) }
    private var gap: CGFloat { max(6, size.height * 0.025) }
    private var nameSize: CGFloat { min(rowHeight * 0.26, size.width * 0.075) }
    private var pointsSize: CGFloat { min(rowHeight * 0.66, size.width * 0.2) }

    var body: some View {
        VStack(spacing: gap) {
            HStack(alignment: .firstTextBaseline) {
                Text(court.label ?? "")
                    .font(.system(size: headerHeight * 0.6, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                if let status = court.status {
                    Text(status)
                        .foregroundStyle(.white.opacity(0.6))
                } else if court.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(.system(size: headerHeight * 0.48, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .frame(height: headerHeight)

            ForEach([leftSide, leftSide.other], id: \.self) { side in
                row(side)
            }
        }
        .padding(gap)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 28 * unit, style: .continuous))
    }

    private func row(_ side: TeamSide) -> some View {
        let team = court.sides[side]

        return HStack(spacing: 12 * unit) {
            VStack(alignment: .leading, spacing: nameSize * 0.15) {
                ForEach(Array(team.players.enumerated()), id: \.offset) { _, player in
                    HStack(spacing: nameSize * 0.3) {
                        Text(player.name)
                            .fontWeight(player.isServing ? .heavy : .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if player.isServing {
                            Image(systemName: "tennisball.fill")
                                .font(.system(size: nameSize * 0.7))
                        }
                    }
                }
            }
            .font(.system(size: nameSize, design: .rounded))

            Spacer(minLength: 8 * unit)

            if team.isWinner {
                Image(systemName: "checkmark")
                    .font(.system(size: pointsSize * 0.4, weight: .heavy))
            }
            Text(team.points)
                .font(.system(size: pointsSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20 * unit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.color(side), in: .rect(cornerRadius: 20 * unit, style: .continuous))
        .animation(.snappy, value: team)
    }
}
