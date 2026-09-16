import RekkertCore
import SwiftUI

enum HomeRoute: Hashable {
    case list
    case record(HistoryRecord)
    case voice
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.history) { record in
                NavigationLink(value: HomeRoute.record(record)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.headline)
                        HStack(spacing: 4) {
                            Image(systemName: record.state.modeSymbol)
                            Text(record.state.modeName)
                            Text("·")
                            Text(record.finishedAt, format: .dateTime.day().month().year().hour().minute())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        summary(for: record.state)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in
                for index in offsets { model.deleteHistory(model.history[index].id) }
            }
        }
        .navigationTitle("History")
        .overlay {
            if model.history.isEmpty {
                ContentUnavailableView("No matches yet", systemImage: "clock", description: Text("Finished matches show up here."))
            }
        }
    }

    @ViewBuilder
    private func summary(for state: SessionState) -> some View {
        switch state {
        case .traditional:
            // The result's own score line, which counts the set in progress too — listing
            // only completed sets leaves a match stopped part-way with nothing to show.
            Text(SessionResult.make(from: state).score)
        case .tournament(let tournament):
            let standings = Leaderboard.standings(for: tournament)
            Text(standings.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element.player.name) \($0.element.total)" }.joined(separator: " · "))
        case .winnerCourt(let session):
            Text("\(session.completedRounds.count) rounds · games \(session.totalGames.a)–\(session.totalGames.b)")
        case .pointCount(let session):
            Text("\(session.score.points.a)–\(session.score.points.b) · to \(session.rules.target)")
        }
    }
}
