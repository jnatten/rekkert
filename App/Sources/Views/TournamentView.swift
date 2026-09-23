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
    @State private var editing: CourtRef?
    @State private var showingEnd = false
    /// Which round is on screen. `nil` follows the newest one, so drawing a round moves
    /// the view along with it; browsing back pins it until you return to the end.
    @State private var browsing: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let tournament = TournamentView.tournament(model) {
                    List {
                        if let round = tournament.round(at: viewed(tournament)) {
                            roundSections(tournament, round)
                        } else {
                            Section {
                                Text("No round has been drawn yet.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        managementSection(tournament)
                    }
                } else {
                    ContentUnavailableView("No tournament", systemImage: "sportscourt")
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    ConnectionBadge()
                    SharingBadge()
                    WorkoutBadge()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.store.undoLast() }
                        .disabled(!model.store.canUndo)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Tournament options", systemImage: "ellipsis.circle") {
                        SharingMenuItems()
                        if let tournament = TournamentView.tournament(model) {
                            // Only the watch acts on it: your court buzzes, and your team
                            // follows you through the draw.
                            Picker("I'm playing as", systemImage: "person.crop.circle", selection: me) {
                                Text("Nobody").tag(PlayerID?.none)
                                ForEach(tournament.players) { player in
                                    Text(player.name).tag(Optional(player.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .sheet(item: $editing) { ref in
                CourtScoreboardView(round: ref.round, court: ref.court)
            }
            .task {
                #if DEBUG
                if let round = DemoLaunch.browseRound { browsing = round }
                if let ref = DemoLaunch.openCourt { editing = ref }
                #endif
            }
            .confirmationDialog(endPrompt, isPresented: $showingEnd, titleVisibility: .visible) {
                if hasResults {
                    Button("Save to history", role: .destructive) {
                        model.store.finish()
                        model.finishSession()
                    }
                } else {
                    Button("Discard", role: .destructive) { model.discard() }
                }
                Button("Keep playing", role: .cancel) {}
            }
        }
    }

    // MARK: - Rounds

    private func viewed(_ tournament: Tournament) -> Int {
        min(browsing ?? tournament.latestRoundIndex, tournament.latestRoundIndex)
    }

    @ViewBuilder
    private func roundSections(_ tournament: Tournament, _ round: Round) -> some View {
        Section {
            ForEach(round.matches) { match in
                CourtRow(tournament: tournament, match: match)
                    .contentShape(.rect)
                    .onTapGesture { editing = CourtRef(round: round.index, court: match.courtIndex) }
            }
        } header: {
            roundSwitcher(tournament, round)
        } footer: {
            if round.matches.contains(where: \.isConfirmed) {
                Text("This round is finished. Reopen it to change a score.")
            } else {
                Text("Tap a court to set its score, or open the scoreboard to count point by point.")
            }
        }

        if !round.sitOuts.isEmpty {
            Section("Sitting out") {
                Text(round.sitOuts.compactMap { tournament.player($0)?.name }.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func roundSwitcher(_ tournament: Tournament, _ round: Round) -> some View {
        HStack {
            Button("Previous round", systemImage: "chevron.left") {
                browsing = round.index - 1
            }
            .disabled(round.index == 0)

            Spacer()
            Text("Round \(round.index + 1) of \(tournament.rounds.count)")
            Spacer()

            Button("Next round", systemImage: "chevron.right") {
                let next = round.index + 1
                browsing = next == tournament.latestRoundIndex ? nil : next
            }
            .disabled(round.index >= tournament.latestRoundIndex)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.body)
        .textCase(nil)
    }

    // MARK: - Actions

    /// Always rendered, whatever the tournament looks like — otherwise undoing the draw
    /// leaves the screen with no way out.
    @ViewBuilder
    private func managementSection(_ tournament: Tournament) -> some View {
        let index = viewed(tournament)
        let round = tournament.round(at: index)

        Section {
            if let round {
                if round.matches.contains(where: \.isConfirmed) {
                    Button("Reopen this round", systemImage: "lock.open") {
                        model.store.setRoundConfirmed(round.index, false)
                    }
                } else if round.index < tournament.latestRoundIndex {
                    Button("Back to the current round", systemImage: "forward.end") {
                        browsing = nil
                    }
                } else {
                    Button("Finish round and draw the next", systemImage: "arrow.right.circle.fill") {
                        model.store.setRoundConfirmed(round.index, true)
                        model.store.nextRound()
                        browsing = nil
                    }
                    .disabled(!allCourtsDone(round, tournament: tournament))
                }
            } else {
                Button("Draw the first round", systemImage: "dice") { model.store.nextRound() }
                    .disabled(tournament.playableCourts < 1)
            }

            if model.store.canEndSession {
                Button(
                    hasResults ? "Finish tournament" : "Discard tournament",
                    systemImage: hasResults ? "flag.checkered" : "trash",
                    role: .destructive
                ) {
                    showingEnd = true
                }
            } else {
                // Somebody else's tournament: step off it rather than end it for them.
                Button("Leave", systemImage: "rectangle.portrait.and.arrow.right") {
                    model.sharing.stop()
                }
            }
        } footer: {
            if tournament.playableCourts < 1 {
                Text("A court needs four players — this tournament has \(tournament.players.count).")
            } else if let round, round.index < tournament.latestRoundIndex {
                Text("You are looking at an earlier round. Later rounds were drawn from the standings as they were, so changing a score here will not re-pair them.")
            }
        }
    }

    private var me: Binding<PlayerID?> {
        Binding(get: { model.store.me }, set: { model.store.setMe($0) })
    }

    private var title: String {
        guard let tournament = TournamentView.tournament(model) else { return "Courts" }
        return tournament.name.isEmpty ? tournament.format.displayName : tournament.name
    }

    /// Nothing has been played, so there is nothing worth keeping in history.
    private var hasResults: Bool {
        guard let tournament = TournamentView.tournament(model) else { return false }
        return tournament.rounds.contains { round in
            round.matches.contains { $0.state.points.total > 0 } || !round.sitOuts.isEmpty
        }
    }

    private var endPrompt: String {
        hasResults ? "Finish the tournament?" : "Discard this tournament?"
    }

    private func allCourtsDone(_ round: Round, tournament: Tournament) -> Bool {
        let engine = PointCountEngine(rules: tournament.config.pointRules)
        return round.matches.allSatisfy { engine.isFinished($0.state) || $0.isConfirmed }
    }
}

struct CourtRef: Identifiable, Hashable {
    let round: Int
    let court: Int
    var id: Self { self }
}

private struct CourtRow: View {
    @Environment(\.teamPalette) private var palette
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
                    Circle().fill(palette.color(side)).frame(width: 8, height: 8)
                    names(side)
                        .lineLimit(1)
                        .accessibilityLabel(spokenNames(side))
                    Spacer()
                    Text("\(match.state.points[side])")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(palette.color(side))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Who serves next on this court, or nobody once it is over.
    private var server: PlayerID? {
        let engine = PointCountEngine(rules: tournament.config.pointRules)
        guard !match.isConfirmed, !engine.isFinished(match.state) else { return nil }
        let slot = engine.serve(match.state).slot
        let line = match.teams[slot.team]
        return line.indices.contains(slot.playerIndex) ? line[slot.playerIndex] : nil
    }

    /// The pair, with the server in bold.
    private func names(_ side: TeamSide) -> Text {
        let names = match.teams[side].compactMap(tournament.player).map { player in
            player.id == server ? Text(player.name).bold() : Text(player.name)
        }
        return names.dropFirst().reduce(names.first ?? Text("")) { line, name in
            Text("\(line) & \(name)")
        }
    }

    private func spokenNames(_ side: TeamSide) -> String {
        let players = match.teams[side].compactMap { tournament.player($0) }
        let line = players.map(\.name).joined(separator: " and ")
        guard let serving = players.first(where: { $0.id == server }) else { return line }
        return "\(line), \(serving.name) serving"
    }
}
