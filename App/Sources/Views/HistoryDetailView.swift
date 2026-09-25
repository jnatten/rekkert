import RekkertCore
import SwiftUI

/// A finished session opened back up: how it ended, the full table where there is one, and
/// a way to carry on with it if it never actually ran its course.
///
/// Addressed by id and looked up on every redraw, rather than handed the record the list was
/// holding — editing the names makes a new value, and a pushed copy would keep drawing the
/// old ones.
struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    let id: UUID

    var body: some View {
        if let record = model.record(id) {
            RecordDetail(record: record)
        } else {
            ContentUnavailableView(
                "Nothing here",
                systemImage: "clock",
                description: Text("This match is no longer in History.")
            )
        }
    }
}

private struct RecordDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.teamPalette) private var palette
    let record: HistoryRecord

    @State private var confirmingResume = false
    @State private var startingAnother = false
    @State private var editingNames = false

    private var result: SessionResult { SessionResult.make(from: record.state) }

    private var tournament: Tournament? {
        guard case .tournament(let value) = record.state else { return nil }
        return value
    }
    private var tint: Color { result.winningSide.map(palette.color) ?? .accentColor }

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
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(placing.value)
                                    .font(.callout.bold().monospacedDigit())
                                if let detail = placing.detail {
                                    Text(detail)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
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
            if case .friendly(let session) = record.state {
                friendlyRounds(session)
            }

            resumeSection
        }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editingNames = true }
            }
        }
        .task {
            #if DEBUG
            if DemoLaunch.rematch, case .tournament = record.state { startingAnother = true }
            if DemoLaunch.editNames { editingNames = true }
            #endif
        }
        .sheet(isPresented: $editingNames) {
            EditNamesView(record: record)
        }
        // Presented from the list itself: a sheet attached to a row goes with the row
        // when it scrolls out of a lazy List, and then never opens.
        .sheet(isPresented: $startingAnother) {
            if let tournament {
                NewSessionView(
                    mode: tournament.format == .americano ? .americano : .mexicano,
                    from: tournament
                )
            }
        }
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
            Section(round.isCancelled ? "Round \(round.index + 1) · Cancelled" : "Round \(round.index + 1)") {
                ForEach(round.matches) { match in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Court \(match.courtIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(TeamSide.allCases, id: \.self) { side in
                            HStack {
                                Circle().fill(palette.color(side)).frame(width: 8, height: 8)
                                Text(names(match, side, in: tournament)).lineLimit(1)
                                Spacer()
                                Text("\(match.state.points[side])")
                                    .font(.body.bold().monospacedDigit())
                                    .foregroundStyle(palette.color(side))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .opacity(round.isCancelled ? 0.5 : 1)
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
    private func friendlyRounds(_ session: FriendlySession) -> some View {
        ForEach(session.rounds.filter(\.wasPlayed)) { round in
            Section("Round \(round.index + 1)") {
                ForEach(TeamSide.allCases, id: \.self) { side in
                    HStack {
                        Circle().fill(palette.color(side)).frame(width: 8, height: 8)
                        Text(session.names(side, in: round)).lineLimit(1)
                        Spacer()
                        Text("\(round.games[side])")
                            .font(.body.bold().monospacedDigit())
                            .foregroundStyle(palette.color(side))
                    }
                }
                if round.isStopped {
                    Text("Stopped part-way").font(.caption).foregroundStyle(.secondary)
                }
                if !round.sitOuts.isEmpty {
                    Text("Sitting out: \(session.sitOutNames(in: round).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var resumeSection: some View {
        Section {
            if tournament != nil {
                Button("New tournament, same players", systemImage: "person.2.badge.plus") {
                    startingAnother = true
                }
            }
            if record.state.canResume {
                Button("Resume this session", systemImage: "play.circle") {
                    confirmingResume = true
                }
            }
        } footer: {
            Text(resumeFooter)
        }
    }

    private var resumeFooter: String {
        // A tournament can always take another round, so "never ran its course" would be
        // the wrong thing to say about one you deliberately finished.
        if case .tournament = record.state {
            return "Resuming adds more rounds to this tournament. Starting a new one keeps the players and leaves this where it is."
        }
        if case .friendly = record.state {
            return "Resuming adds more rounds to this friendly, with the same group and the draw carrying on from where it left off."
        }
        return record.state.canResume
            ? "This one never ran its course, so there is more of it to play."
            : "This one was played out to the end, so there is nothing left to resume."
    }

    private func resume() {
        model.store.resume(record.state)
        dismiss()
    }
}
