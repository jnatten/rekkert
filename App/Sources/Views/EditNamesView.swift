import RekkertCore
import SwiftUI

/// Putting the names in a finished match right. A session is named once, when it is set up,
/// and until now that was that — a typo, or a "Them" nobody got round to filling in, stayed
/// on the record for good.
///
/// Renaming only. Nobody can be added or removed here: the rounds were drawn around these
/// people, and the standings, sit-outs and result lines all read back through them.
struct EditNamesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.teamPalette) private var palette
    let record: HistoryRecord

    init(record: HistoryRecord) {
        self.record = record
        switch record.state.names {
        case .group(let event, let players):
            _eventName = State(initialValue: event)
            _players = State(initialValue: players)
        case .sides(let teams):
            // Padded to two: a side set up without its line-up filled in still gets two slots
            // to type into, and the slots stay where they are because the serve badge picks
            // the server out of this list by position.
            _teams = State(initialValue: teams.map {
                TeamInfo(name: $0.name, players: $0.players + Array(repeating: "", count: max(0, 2 - $0.players.count)))
            })
        }
    }

    @State private var eventName = ""
    @State private var players: [Player] = []
    @State private var teams = BySide(both: TeamInfo(name: "", players: ["", ""]))
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case eventName
        case player(PlayerID)
        case teamName(TeamSide)
        case teamPlayer(TeamSide, Int)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch record.state.names {
                case .group: groupSections
                case .sides: sideSections
                }
            }
            .navigationTitle("Edit names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    // MARK: - Tournament and friendly

    @ViewBuilder
    private var groupSections: some View {
        Section {
            TextField(eventPlaceholder, text: $eventName)
                .textInputAutocapitalization(.words)
                .focused($focused, equals: .eventName)
                .submitLabel(.next)
                .onSubmit { focused = players.first.map { .player($0.id) } }
        } header: {
            Text("Name")
        } footer: {
            Text("Leave it empty and it goes back to being called “\(eventPlaceholder)”.")
        }

        Section {
            ForEach($players) { $player in
                TextField("Player name", text: $player.name)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .player(player.id))
                    .submitLabel(.next)
                    .onSubmit { advanceFromPlayer(player.id) }
            }
        } header: {
            Text("Players")
        } footer: {
            Text("Correcting a name changes it everywhere in this match — the rounds, the table and the result. It changes nothing anywhere else.")
        }
    }

    /// What the session is called when it has no name of its own, which is what clearing the
    /// field leaves behind.
    private var eventPlaceholder: String {
        switch record.state {
        case .tournament(let tournament): tournament.format.displayName
        default: "Friendly"
        }
    }

    private func advanceFromPlayer(_ id: PlayerID) {
        guard let index = players.firstIndex(where: { $0.id == id }) else { return }
        focused = index + 1 < players.count ? .player(players[index + 1].id) : nil
    }

    // MARK: - Match, Points and Winner court

    @ViewBuilder
    private var sideSections: some View {
        Section {
            teamRows(.a)
            teamRows(.b)
        } header: {
            Text("Teams")
        } footer: {
            Text("The two team names are what this match is listed under.")
        }
    }

    private func teamRows(_ side: TeamSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(palette.color(side)).frame(width: 10, height: 10)
                TextField("Team name", text: teamName(side))
                    .font(.headline)
                    .focused($focused, equals: .teamName(side))
                    .submitLabel(.next)
                    .onSubmit { focused = .teamPlayer(side, 0) }
            }
            ForEach(0 ..< 2, id: \.self) { index in
                TextField("Player \(index + 1)", text: teamPlayer(side, index))
                    .focused($focused, equals: .teamPlayer(side, index))
                    .submitLabel(side == .b && index == 1 ? .done : .next)
                    .onSubmit { advanceFromTeamPlayer(side, index) }
            }
        }
        .textInputAutocapitalization(.words)
    }

    private func teamName(_ side: TeamSide) -> Binding<String> {
        Binding(get: { teams[side].name }, set: { teams[side].name = $0 })
    }

    private func teamPlayer(_ side: TeamSide, _ index: Int) -> Binding<String> {
        Binding(get: { teams[side].players[index] }, set: { teams[side].players[index] = $0 })
    }

    private func advanceFromTeamPlayer(_ side: TeamSide, _ index: Int) {
        if index == 0 {
            focused = .teamPlayer(side, 1)
        } else if side == .a {
            focused = .teamName(.b)
        } else {
            focused = nil
        }
    }

    // MARK: - Saving

    private func save() {
        let names: SessionNames = switch record.state.names {
        case .group: .group(event: eventName, players: players)
        case .sides: .sides(teams)
        }
        model.update(record.renamed(names))
        dismiss()
    }
}
