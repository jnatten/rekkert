import RekkertCore
import SwiftUI

struct RoundsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let tournament = TournamentView.tournament(model) {
                    List(tournament.rounds.reversed()) { round in
                        Section(round.isCancelled ? "Round \(round.index + 1) · Cancelled" : "Round \(round.index + 1)") {
                            ForEach(round.matches) { match in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(TeamSide.allCases, id: \.self) { side in
                                            Text(names(match, side, tournament)).font(.subheadline)
                                        }
                                    }
                                    Spacer()
                                    Text("\(match.state.points.a)–\(match.state.points.b)")
                                        .font(.headline.monospacedDigit())
                                }
                                .foregroundStyle(round.isCancelled ? .secondary : .primary)
                            }
                            if !round.sitOuts.isEmpty {
                                Text("Out: " + round.sitOuts.compactMap { tournament.player($0)?.name }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No rounds", systemImage: "clock")
                }
            }
            .navigationTitle("Rounds")
        }
    }

    private func names(_ match: CourtMatch, _ side: TeamSide, _ tournament: Tournament) -> String {
        match.teams[side].compactMap { tournament.player($0)?.name }.joined(separator: " & ")
    }
}
