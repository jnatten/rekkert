import RekkertCore
import SwiftUI

struct StandingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let tournament = TournamentView.tournament(model) {
                    List(Array(Leaderboard.standings(for: tournament).enumerated()), id: \.element.id) { index, standing in
                        StandingRow(rank: index + 1, standing: standing)
                    }
                } else {
                    ContentUnavailableView("No tournament", systemImage: "list.number")
                }
            }
            .navigationTitle("Standings")
        }
    }
}

struct StandingRow: View {
    let rank: Int
    let standing: Standing

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(standing.player.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(standing.total)")
                .font(.title3.bold().monospacedDigit())
        }
    }

    private var subtitle: String {
        var parts = ["\(standing.roundsPlayed) played"]
        if standing.sitOuts > 0 { parts.append("\(standing.sitOuts) sat out (+\(standing.compensation))") }
        parts.append(standing.differential >= 0 ? "+\(standing.differential)" : "\(standing.differential)")
        return parts.joined(separator: " · ")
    }
}
