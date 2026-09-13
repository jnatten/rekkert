import RekkertCore
import SwiftUI

/// A finished session opened back up: how it ended, the full table where there is one, and
/// a way to carry on with it if it never actually ran its course.
struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: HistoryRecord

    @State private var confirmingResume = false

    private var result: SessionResult { SessionResult.make(from: record.state) }
    private var tint: Color { result.winningSide.map(Color.team) ?? .accentColor }

    var body: some View {
        List {
            Section { outcome }

            if !result.placings.isEmpty {
                Section("Leaderboard") {
                    ForEach(result.placings) { placing in
                        HStack(spacing: 12) {
                            Text("\(placing.rank)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)
                            Text(placing.name)
                                .fontWeight(placing.rank == 1 ? .semibold : .regular)
                            Spacer()
                            Text(placing.value)
                                .font(.callout.bold().monospacedDigit())
                        }
                    }
                }
            }

            if case .tournament(let tournament) = record.state {
                rounds(tournament)
            }
            if case .traditional(let session) = record.state, !session.score.completedSets.isEmpty {
                sets(session)
            }
            if case .winnerCourt(let session) = record.state, !session.completedRounds.isEmpty {
                winnerCourtRounds(session)
            }

            resumeSection
        }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Pick this up again?",
            isPresented: $confirmingResume,
            titleVisibility: .visible
        ) {
            Button("Resume") { resume() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It comes back as the session in play on both devices, with the score it had. The copy here stays in History.")
        }
    }

    private var outcome: some View {
        VStack(spacing: 8) {
            Text(result.headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !result.score.isEmpty {
                Text(result.score)
                    .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            if let detail = result.detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: record.state.modeSymbol)
                Text(record.state.modeName)
                Text("·")
                Text(record.finishedAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func rounds(_ tournament: Tournament) -> some View {
        ForEach(tournament.rounds, id: \.index) { round in
            Section("Round \(round.index + 1)") {
                ForEach(round.matches) { match in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Court \(match.courtIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(TeamSide.allCases, id: \.self) { side in
                            HStack {
                                Circle().fill(Color.team(side)).frame(width: 8, height: 8)
                                Text(names(match, side, in: tournament)).lineLimit(1)
                                Spacer()
                                Text("\(match.state.points[side])")
                                    .font(.body.bold().monospacedDigit())
                                    .foregroundStyle(Color.team(side))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !round.sitOuts.isEmpty {
                    Text("Sitting out: \(round.sitOuts.compactMap { tournament.player($0)?.name }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func names(_ match: CourtMatch, _ side: TeamSide, in tournament: Tournament) -> String {
        match.teams[side].compactMap { tournament.player($0)?.name }.joined(separator: " & ")
    }

    @ViewBuilder
    private func sets(_ session: TraditionalSession) -> some View {
        Section("Sets") {
            ForEach(Array(session.score.completedSets.enumerated()), id: \.offset) { index, set in
                HStack {
                    Text("Set \(index + 1)").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(set.games.a)–\(set.games.b)")
                        .font(.body.monospacedDigit())
                    if let tiebreak = set.tiebreak {
                        Text("(\(tiebreak.a)–\(tiebreak.b))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func winnerCourtRounds(_ session: WinnerCourtSession) -> some View {
        Section("Rounds") {
            ForEach(Array(session.completedRounds.enumerated()), id: \.offset) { index, round in
                HStack {
                    Text("Round \(index + 1)").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(round.games.a)–\(round.games.b)")
                        .font(.body.monospacedDigit())
                }
            }
        }
    }

    @ViewBuilder
    private var resumeSection: some View {
        Section {
            if record.state.canResume {
                Button("Resume this session", systemImage: "play.circle") {
                    confirmingResume = true
                }
            }
        } footer: {
            Text(record.state.canResume
                 ? "This one never ran its course, so there is more of it to play."
                 : "This one was played out to the end, so there is nothing left to resume.")
        }
    }

    private func resume() {
        model.store.resume(record.state)
        dismiss()
    }
}
