import RekkertCore
import SwiftUI

struct BoardMatchView: View {
    @Environment(\.teamPalette) private var palette
    let board: TVBoard
    let court: TVBoard.Court
    let metrics: BoardMetrics

    private var unit: CGFloat { metrics.unit }
    private var order: [TeamSide] { [board.leftSide, board.leftSide.other] }

    var body: some View {
        let halves = metrics.isLandscape
            ? AnyLayout(HStackLayout(spacing: 12 * unit))
            : AnyLayout(VStackLayout(spacing: 12 * unit))

        VStack(spacing: 24 * unit) {
            HStack(spacing: 24 * unit) {
                halves {
                    ForEach(order, id: \.self) { side in
                        half(side)
                    }
                }
                if metrics.isLandscape, !board.standings.isEmpty {
                    BoardStandings(standings: board.standings, metrics: metrics)
                        .frame(width: metrics.size.width * 0.26)
                }
            }
            band
        }
    }

    private func half(_ side: TeamSide) -> some View {
        let team = court.sides[side]

        return GeometryReader { geometry in
            VStack(spacing: 18 * unit) {
                if let name = team.name {
                    HStack(spacing: 16 * unit) {
                        Text(name)
                            .font(metrics.font(64, .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if team.isWinner {
                            Image(systemName: "trophy.fill").font(metrics.font(52))
                        }
                    }
                }
                if !team.players.isEmpty {
                    players(team, winner: team.name == nil && team.isWinner)
                }

                Spacer(minLength: 0)

                Text(team.points)
                    .font(.system(size: min(geometry.size.width * 0.46, geometry.size.height * 0.5), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .contentTransition(.numericText())

                Spacer(minLength: 0)

                if team.games != nil || team.roundsWon != nil {
                    tally(team)
                }
            }
            .padding(32 * unit)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(palette.color(side), in: .rect(cornerRadius: 40 * unit, style: .continuous))
        .animation(.snappy, value: team)
    }

    private func players(_ team: TVBoard.Side, winner: Bool) -> some View {
        let chips = ForEach(Array(team.players.enumerated()), id: \.offset) { _, player in
            chip(player)
        }
        return HStack(spacing: 16 * unit) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16 * unit) { chips }
                VStack(spacing: 12 * unit) { chips }
            }
            if winner {
                Image(systemName: "trophy.fill").font(metrics.font(48))
            }
        }
    }

    private func chip(_ player: TVBoard.Player) -> some View {
        HStack(spacing: 12 * unit) {
            if player.isServing {
                Image(systemName: "tennisball.fill")
            }
            Text(player.name)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(metrics.font(46, player.isServing ? .bold : .semibold))
        .foregroundStyle(player.isServing ? Color.black : .white)
        .padding(.horizontal, 26 * unit)
        .padding(.vertical, 12 * unit)
        .background(player.isServing ? Color.white : .black.opacity(0.2), in: .capsule)
    }

    /// Games per set, the current one boxed; on a winner court, rounds won as well.
    private func tally(_ team: TVBoard.Side) -> some View {
        HStack(spacing: 18 * unit) {
            ForEach(Array(team.sets.enumerated()), id: \.offset) { _, games in
                Text("\(games)")
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let games = team.games {
                Text("\(games)")
                    .fontWeight(.heavy)
                    .padding(.horizontal, 20 * unit)
                    .padding(.vertical, 4 * unit)
                    .background(.black.opacity(0.22), in: .rect(cornerRadius: 16 * unit, style: .continuous))
            }
            if let won = team.roundsWon {
                Text(won == 1 ? "1 round won" : "\(won) rounds won")
                    .font(metrics.font(40, .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, 12 * unit)
            }
        }
        .font(metrics.font(60, .bold))
        .monospacedDigit()
    }

    @ViewBuilder
    private var band: some View {
        if let next = board.upNext {
            HStack(spacing: 16 * unit) {
                Text("Up next").foregroundStyle(.white.opacity(0.6))
                Text(next.teams.a).foregroundStyle(palette.color(.a))
                Text("vs").foregroundStyle(.white.opacity(0.6))
                Text(next.teams.b).foregroundStyle(palette.color(.b))
                if !next.sittingOut.isEmpty {
                    Text("· Sitting out: \(next.sittingOut.joined(separator: ", "))")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .font(metrics.font(40))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        } else if !board.sittingOut.isEmpty {
            Text("Sitting out: \(board.sittingOut.joined(separator: ", "))")
                .font(metrics.font(40))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}
