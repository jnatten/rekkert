import RekkertCore
import SwiftUI

struct NewSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: GameMode

    @State private var rules = TraditionalRules()
    @State private var teamA = "Us"
    @State private var teamB = "Them"
    @State private var playersA = ["", ""]
    @State private var playersB = ["", ""]

    @State private var tournamentName = ""
    @State private var config = TournamentConfig()
    @State private var players: [Player] = (0 ..< 4).map { _ in Player(name: "") }
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case tournamentName
        case player(PlayerID)
        case teamName(TeamSide)
        case teamPlayer(TeamSide, Int)
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .traditional {
                    traditionalSections
                } else {
                    tournamentSections
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start).disabled(!canStart)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    suggestionBar
                }
            }
        }
    }

    // MARK: - Traditional

    @ViewBuilder
    private var traditionalSections: some View {
        Section("Sport") {
            Picker("Sport", selection: $rules.sport) {
                ForEach(Sport.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        Section("Teams") {
            teamRows(name: $teamA, players: $playersA, side: .a)
            teamRows(name: $teamB, players: $playersB, side: .b)
        }

        Section("Scoring") {
            Picker("At 40–40", selection: $rules.deuceRule) {
                ForEach(DeuceRule.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text(deuceExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Format") {
            Stepper("Sets to win: \(rules.setsToWin)", value: $rules.setsToWin, in: 1 ... 5)
            Stepper("Games per set: \(rules.gamesPerSet)", value: $rules.gamesPerSet, in: 1 ... 9)
            Toggle("Tiebreak at \(rules.gamesPerSet)–\(rules.gamesPerSet)", isOn: tiebreakBinding)
            Toggle("Super tiebreak in deciding set", isOn: superTiebreakBinding)
                .disabled(rules.setsToWin < 2)
        }
    }

    private func teamRows(name: Binding<String>, players: Binding<[String]>, side: TeamSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color.team(side)).frame(width: 10, height: 10)
                TextField("Team name", text: name)
                    .font(.headline)
                    .focused($focused, equals: .teamName(side))
                    .submitLabel(.next)
                    .onSubmit { focused = .teamPlayer(side, 0) }
            }
            ForEach(0 ..< 2, id: \.self) { index in
                TextField("Player \(index + 1)", text: players[index])
                    .focused($focused, equals: .teamPlayer(side, index))
                    .submitLabel(side == .b && index == 1 ? .done : .next)
                    .onSubmit { advanceFromTeamPlayer(side, index) }
            }
        }
        .textInputAutocapitalization(.words)
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

    private var tiebreakBinding: Binding<Bool> {
        Binding(
            get: { rules.tiebreakAtGames != nil },
            set: { rules.tiebreakAtGames = $0 ? rules.gamesPerSet : nil }
        )
    }

    private var superTiebreakBinding: Binding<Bool> {
        Binding(
            get: { if case .superTiebreak = rules.decidingSet { true } else { false } },
            set: { rules.decidingSet = $0 ? .standardSuperTiebreak : .normal }
        )
    }

    private var deuceExplanation: String {
        switch rules.deuceRule {
        case .advantage: "Deuces repeat until a team wins two points in a row."
        case .goldenPoint: "The first 40–40 is a single deciding point. The receiving team picks the side."
        case .starPoint: "Two deuces are played out; the third 40–40 is a deciding point."
        }
    }

    // MARK: - Tournament

    @ViewBuilder
    private var tournamentSections: some View {
        Section {
            ForEach($players) { $player in
                TextField("Player name", text: $player.name)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .player(player.id))
                    .submitLabel(.next)
                    .onSubmit { advanceFromPlayer(player.id) }
            }
            .onDelete { players.remove(atOffsets: $0) }

            Button("Add player", systemImage: "plus") { addPlayer() }
        } header: {
            Text("Players (\(namedPlayers.count))")
        } footer: {
            Text(playerFooter)
        }

        if !quickAdd.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quickAdd) { known in
                            Button(known.name) { add(known.name) }
                                .buttonStyle(.bordered)
                                .contextMenu {
                                    Button("Forget \(known.name)", systemImage: "trash", role: .destructive) {
                                        model.forgetPlayer(known.name)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            } header: {
                Text("Played before")
            } footer: {
                Text("Tap to add. Press and hold to forget someone.")
            }
        }

        Section("Tournament") {
            TextField("Name", text: $tournamentName)
                .focused($focused, equals: .tournamentName)
                .submitLabel(.next)
                .onSubmit { focused = players.first.map { .player($0.id) } }
            Stepper("Courts: \(config.courtCount)", value: $config.courtCount, in: 1 ... 8)
        }

        Section("Points") {
            Picker("Play to", selection: $config.pointRules.target) {
                ForEach(PointCountRules.commonTargets, id: \.self) { Text("\($0)").tag($0) }
                if !PointCountRules.commonTargets.contains(config.pointRules.target) {
                    Text("\(config.pointRules.target)").tag(config.pointRules.target)
                }
            }
            Stepper("Target: \(config.pointRules.target)", value: $config.pointRules.target, in: 4 ... 99)
            Picker("Ends when", selection: $config.pointRules.targetKind) {
                ForEach(TargetKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text(targetExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Sit-outs") {
            Picker("Compensation", selection: compensationBinding) {
                Text("None").tag(0)
                Text("Half the target (\(config.pointRules.target / 2))").tag(1)
                Text("Full target (\(config.pointRules.target))").tag(2)
            }
            Text("Players benched for a round still score this many points.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if mode == .mexicano {
            Section("Pairing") {
                Picker("Each court", selection: $config.mexicanoPairing) {
                    ForEach(MexicanoPairing.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
        }
    }

    // MARK: - Player entry

    /// Enter moves to the next name, adding a row when there is not one yet, so a group
    /// can be typed in without reaching for the screen between names.
    private func advanceFromPlayer(_ id: PlayerID) {
        guard let index = players.firstIndex(where: { $0.id == id }) else { return }
        if index + 1 < players.count {
            focused = .player(players[index + 1].id)
        } else {
            addPlayer()
        }
    }

    private func addPlayer() {
        let player = Player(name: "")
        players.append(player)
        focused = .player(player.id)
    }

    /// Familiar names not already in this tournament.
    private var quickAdd: [KnownPlayer] {
        model.roster.suggestions(excluding: players.map(\.name), limit: 12)
    }

    private func add(_ name: String) {
        if let slot = players.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            players[slot].name = name
        } else {
            players.append(Player(name: name))
        }
    }

    /// Suggestions for whichever name field is being typed into, shown above the keyboard.
    @ViewBuilder
    private var suggestionBar: some View {
        let matches = suggestions
        if matches.isEmpty {
            Spacer()
            Button("Done") { focused = nil }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(matches) { known in
                        Button(known.name) { fill(known.name) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button("Done") { focused = nil }
        }
    }

    private var suggestions: [KnownPlayer] {
        guard let focused else { return [] }
        switch focused {
        case .tournamentName, .teamName:
            return []
        case .player(let id):
            guard let player = players.first(where: { $0.id == id }) else { return [] }
            return model.roster.suggestions(matching: player.name, excluding: players.map(\.name), limit: 8)
        case .teamPlayer(let side, let index):
            let entered = playersA + playersB
            let typed = (side == .a ? playersA : playersB)[index]
            return model.roster.suggestions(matching: typed, excluding: entered.filter { $0 != typed }, limit: 8)
        }
    }

    /// Puts a chosen name into the field being typed into, then moves on.
    private func fill(_ name: String) {
        guard let focused else { return }
        switch focused {
        case .tournamentName, .teamName:
            break
        case .player(let id):
            guard let index = players.firstIndex(where: { $0.id == id }) else { return }
            players[index].name = name
            advanceFromPlayer(id)
        case .teamPlayer(let side, let index):
            if side == .a { playersA[index] = name } else { playersB[index] = name }
            advanceFromTeamPlayer(side, index)
        }
    }

    private var compensationBinding: Binding<Int> {
        Binding(
            get: {
                switch config.sitOutCompensation {
                case .none: 0
                case .half: 1
                case .full: 2
                case .fixed: 3
                }
            },
            set: {
                config.sitOutCompensation = switch $0 {
                case 0: .none
                case 2: .full
                default: .half
                }
            }
        )
    }

    private var targetExplanation: String {
        switch config.pointRules.targetKind {
        case .totalPointsPlayed:
            "Both scores add up to \(config.pointRules.target), so every court finishes at the same time."
        case .firstToTarget:
            "The round ends as soon as one team reaches \(config.pointRules.target)."
        }
    }

    private var namedPlayers: [Player] {
        players.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var playerFooter: String {
        let count = namedPlayers.count
        guard count >= 4 else { return "At least 4 players are needed." }
        let benched = count - min(config.courtCount, count / 4) * 4
        return benched == 0
            ? "Everyone plays every round."
            : "\(benched) player\(benched == 1 ? "" : "s") sit out each round, rotating fairly."
    }

    // MARK: - Start

    private var canStart: Bool {
        mode == .traditional ? true : namedPlayers.count >= 4
    }

    private func start() {
        switch mode.tournamentFormat {
        case .none:
            model.remember(players: (playersA + playersB).filter { !$0.isEmpty })
            model.store.configure(.traditional(
                rules: rules,
                teams: BySide(
                    a: TeamInfo(name: teamA, players: playersA.filter { !$0.isEmpty }),
                    b: TeamInfo(name: teamB, players: playersB.filter { !$0.isEmpty })
                )
            ))
        case .some(let format):
            model.remember(players: namedPlayers.map(\.name))
            model.store.configure(.tournament(Tournament(
                name: tournamentName,
                format: format,
                players: namedPlayers,
                config: config
            )))
            model.store.nextRound()
        }
        dismiss()
    }
}
