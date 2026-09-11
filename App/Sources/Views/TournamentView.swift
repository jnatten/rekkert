import RekkertCore
import SwiftUI

struct TournamentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Courts", systemImage: "sportscourt") { CourtListView() }
            Tab("Standings", systemImage: "list.number") { StandingsView() }
            Tab("Rounds", systemImage: "clock.arrow.circlepath") { RoundsView() }
        }
    }

    static func tournament(_ model: AppModel) -> Tournament? {
        guard case .tournament(let value)? = model.store.state else { return nil }
        return value
    }
}

struct CourtListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Int?
    @State private var showingEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if let tournament = TournamentView.tournament(model), let round = tournament.currentRound {
                    List {
                        Section {
                            ForEach(round.matches) { match in
                                CourtRow(tournament: tournament, match: match)
                                    .contentShape(.rect)
                                    .onTapGesture { editing = match.courtIndex }
                            }
                        } header: {
                            Text("Round \(round.index + 1)")
                        } footer: {
                            Text("Tap a court to set its score, or open the scoreboard to count point by point.")
                        }

                        if !round.sitOuts.isEmpty {
                            Section("Sitting out") {
                                Text(round.sitOuts.compactMap { tournament.player($0)?.name }.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            Button("Next round", systemImage: "arrow.right.circle.fill") {
                                model.store.confirmRound()
                                model.store.nextRound()
                            }
                            .disabled(!allCourtsDone(round, tournament: tournament))

                            Button("Finish tournament", systemImage: "flag.checkered", role: .destructive) {
                                showingEnd = true
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No round yet", systemImage: "sportscourt")
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionBadge(isReachable: model.store.isReachable)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast() }
                        .disabled(!model.store.canUndo)
                }
            }
            .sheet(item: Binding(get: { editing.map(CourtRef.init) }, set: { editing = $0?.index })) { ref in
                CourtScoreboardView(court: ref.index)
            }
            .confirmationDialog("Finish the tournament?", isPresented: $showingEnd, titleVisibility: .visible) {
                Button("Save to history", role: .destructive) {
                    model.store.finish()
                    model.archiveAndReset()
                }
                Button("Keep playing", role: .cancel) {}
            }
        }
    }

    private var title: String {
        guard let tournament = TournamentView.tournament(model) else { return "Courts" }
        return tournament.name.isEmpty ? tournament.format.displayName : tournament.name
    }

    private func allCourtsDone(_ round: Round, tournament: Tournament) -> Bool {
        let engine = PointCountEngine(rules: tournament.config.pointRules)
        return round.matches.allSatisfy { engine.isFinished($0.state) || $0.isConfirmed }
    }
}

struct CourtRef: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct CourtRow: View {
    let tournament: Tournament
    let match: CourtMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Court \(match.courtIndex + 1)").font(.headline)
                Spacer()
                if match.isConfirmed {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.caption)
                }
            }
            ForEach(TeamSide.allCases, id: \.self) { side in
                HStack {
                    Circle().fill(Color.team(side)).frame(width: 8, height: 8)
                    Text(names(side)).lineLimit(1)
                    Spacer()
                    Text("\(match.state.points[side])")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.team(side))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func names(_ side: TeamSide) -> String {
        match.teams[side].compactMap { tournament.player($0)?.name }.joined(separator: " & ")
    }
}
