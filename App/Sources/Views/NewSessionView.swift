import RekkertCore
import SwiftUI

struct NewSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.teamPalette) private var palette
    let mode: GameMode

    /// Starts the form filled in from a tournament that has already been played, for
    /// running the same group again. The players are copied by name only, so this is a new
    /// tournament rather than a second handle on the old one.
    init(mode: GameMode, from played: Tournament? = nil) {
        self.mode = mode
        // A friendly plays a whole match every round and then redraws, so one set is the
        // sane default where a Match wants best of three.
        if mode == .friendly {
            _rules = State(initialValue: TraditionalRules(setsToWin: 1))
        }
        guard let played else { return }
        _players = State(initialValue: played.players.map { Player(name: $0.name) })
        _sessionName = State(initialValue: played.name)
        _config = State(initialValue: played.config)
    }

    @State private var rules = TraditionalRules()
    @State private var teamA = "Us"
    @State private var teamB = "Them"
    @State private var playersA = ["", ""]
    @State private var playersB = ["", ""]

    @State private var sessionName = ""
    @State private var winnerCourtRules = WinnerCourtRules()
    @State private var pointRules = PointCountRules()
    @State private var presetName = ""
    @State private var config = TournamentConfig()
    @State private var players: [Player] = (0 ..< 4).map { _ in Player(name: "") }
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case presetName
        case sessionName
        case player(PlayerID)
        case teamName(TeamSide)
        case teamPlayer(TeamSide, Int)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .traditional: traditionalSections
                case .pointCount: pointCountSections
                case .winnerCourt: winnerCourtSections
                case .friendly: friendlySections
                case .americano, .mexicano: tournamentSections
                }
                presetSection
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
        sportSection

        teamsSection

        scoringSection
        formatSection
    }

    // MARK: - Match rules, shared with Friendly

    @ViewBuilder
    private var sportSection: some View {
        Section("Sport") {
            Picker("Sport", selection: $rules.sport) {
                ForEach(Sport.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var scoringSection: some View {
        Section("Scoring") {
            Picker("At 40–40", selection: $rules.deuceRule) {
                ForEach(DeuceRule.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text(deuceExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var formatSection: some View {
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
                Circle().fill(palette.color(side)).frame(width: 10, height: 10)
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

    private var teamsSection: some View {
        Section {
            teamRows(name: $teamA, players: $playersA, side: .a)
            teamRows(name: $teamB, players: $playersB, side: .b)
        } header: {
            Text("Teams")
        } footer: {
            Text("Player 1 serves first for their side.")
        }
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

    private var deuceExplanation: String { deuceExplanation(rules.deuceRule) }

    private func deuceExplanation(_ rule: DeuceRule) -> String {
        switch rule {
        case .advantage: "Deuces repeat until a team wins two points in a row."
        case .goldenPoint: "The first 40–40 is a single deciding point. The receiving team picks the side."
        case .starPoint: "Two deuces are played out; the third 40–40 is a deciding point."
        }
    }

    // MARK: - Points

    @ViewBuilder
    private var pointCountSections: some View {
        teamsSection

        Section {
            Picker("Play to", selection: $pointRules.target) {
                ForEach(PointCountRules.commonTargets, id: \.self) { Text("\($0)").tag($0) }
                if !PointCountRules.commonTargets.contains(pointRules.target) {
                    Text("\(pointRules.target)").tag(pointRules.target)
                }
            }
            Stepper("Target: \(pointRules.target)", value: $pointRules.target, in: 2 ... 99)
            Picker("Ends when", selection: $pointRules.targetKind) {
                ForEach(TargetKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Stepper("Serves each: \(pointRules.servesPerTeam)", value: $pointRules.servesPerTeam, in: 1 ... 5)
        } header: {
            Text("Points")
        } footer: {
            Text("\(pointExplanation) \(servesExplanation(pointRules))")
        }
    }

    private var pointExplanation: String {
        switch pointRules.targetKind {
        case .totalPointsPlayed:
            "Both scores add up to \(pointRules.target), so the round always lasts exactly that many points."
        case .firstToTarget:
            "The round ends as soon as one team reaches \(pointRules.target)."
        }
    }

    private func servesExplanation(_ rules: PointCountRules) -> String {
        rules.servesPerTeam == 1
            ? "Service changes hands every point."
            : "Each player serves \(rules.servesPerTeam) points in a row before it passes to the other side."
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetSection: some View {
        Section {
            TextField("Preset name", text: $presetName)
                .textInputAutocapitalization(.words)
                .focused($focused, equals: .presetName)
                .submitLabel(.done)
                .onSubmit { focused = nil }
        } header: {
            Text("Save as preset")
        } footer: {
            Text(presetName.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "Name this setup to save it. Saved presets can be started from your Apple Watch without reaching for the phone."
                 : "“\(presetName)” will be saved and can be started from either device.")
        }
    }

    private var configuration: PresetConfiguration {
        switch mode {
        case .traditional:
            .traditional(rules: rules, teams: teams)
        case .pointCount:
            .pointCount(rules: pointRules, teams: teams)
        case .winnerCourt:
            .winnerCourt(rules: winnerCourtRules, teams: teams)
        case .friendly:
            .friendly(name: sessionName, players: namedPlayers, rules: rules)
        case .americano, .mexicano:
            .tournament(
                format: mode == .mexicano ? .mexicano : .americano,
                name: sessionName,
                players: namedPlayers,
                config: config
            )
        }
    }

    private func savePresetIfNamed() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.store.savePreset(Preset(name: name, configuration: configuration))
    }

    // MARK: - Winner court

    @ViewBuilder
    private var winnerCourtSections: some View {
        Section("Sport") {
            Picker("Sport", selection: $winnerCourtRules.sport) {
                ForEach(Sport.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        teamsSection

        Section {
            Picker("At 40–40", selection: $winnerCourtRules.deuceRule) {
                ForEach(DeuceRule.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text(deuceExplanation(winnerCourtRules.deuceRule))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Scoring")
        } footer: {
            Text("Games run on and on; there is no set to win. Blow the whistle to end a round and the games so far are banked, then a new round starts at nil-nil.")
        }
    }

    // MARK: - Friendly

    @ViewBuilder
    private var friendlySections: some View {
        Section("Friendly") {
            TextField("Name", text: $sessionName)
                .focused($focused, equals: .sessionName)
                .submitLabel(.next)
                .onSubmit { focused = players.first.map { .player($0.id) } }
        }

        playersSection(footer: friendlyFooter)

        sportSection
        scoringSection
        formatSection
    }

    private var friendlyFooter: String {
        let count = namedPlayers.count
        guard count >= 2 else {
            return "At least 2 players are needed. Two or three play singles; four or more play doubles."
        }
        let kind = count >= 4 ? "Doubles" : "Singles"
        let sitting = count - (count >= 4 ? 4 : 2)
        return sitting == 0
            ? "\(kind), and everyone plays every round."
            : "\(kind), so \(sitting) sit\(sitting == 1 ? "s" : "") out each round — whoever has sat out least plays next."
    }

    // MARK: - Player entry, shared with Tournament

    @ViewBuilder
    private func playersSection(footer: String) -> some View {
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
            Text(footer)
        }

        if !quickAdd.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quickAdd) { known in
                            // A menu with a primary action rather than a button with a
                            // context menu: tap still adds, press and hold still offers to
                            // forget, but the menu belongs to this chip rather than to the
                            // row. The whole scroller is one row, and a row resolves a
                            // long press to the first context menu anywhere inside it — so
                            // every chip offered to forget whoever came first.
                            Menu {
                                Button("Forget \(known.name)", systemImage: "trash", role: .destructive) {
                                    model.forgetPlayer(known.name)
                                }
                            } label: {
                                Text(known.name)
                            } primaryAction: {
                                add(known.name)
                            }
                            .buttonStyle(.bordered)
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
    }

    // MARK: - Tournament

    @ViewBuilder
    private var tournamentSections: some View {
        playersSection(footer: playerFooter)

        Section("Tournament") {
            TextField("Name", text: $sessionName)
                .focused($focused, equals: .sessionName)
                .submitLabel(.next)
                .onSubmit { focused = players.first.map { .player($0.id) } }
            Stepper("Courts: \(config.courtCount)", value: $config.courtCount, in: 1 ... 8)
        }

        Section {
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
            Stepper(
                "Serves each: \(config.pointRules.servesPerTeam)",
                value: $config.pointRules.servesPerTeam, in: 1 ... 5
            )
        } header: {
            Text("Points")
        } footer: {
            Text("\(targetExplanation) \(servesExplanation(config.pointRules))")
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
        case .sessionName, .teamName, .presetName:
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
        case .sessionName, .teamName, .presetName:
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

    private var teams: BySide<TeamInfo> {
        BySide(
            a: TeamInfo(name: teamA, players: lineUp(playersA)),
            b: TeamInfo(name: teamB, players: lineUp(playersB))
        )
    }

    /// Kept where they were typed: the rotation picks the server out of this list by position,
    /// so Player 1 serves first for their side whether or not Player 2 is named. Only blanks
    /// after the last name go — the rule a rename follows too.
    private func lineUp(_ entered: [String]) -> [String] {
        var names = entered.map { $0.trimmingCharacters(in: .whitespaces) }
        while names.last?.isEmpty == true { names.removeLast() }
        return names
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
        switch mode {
        case .traditional, .pointCount, .winnerCourt: true
        case .friendly: namedPlayers.count >= 2
        case .americano, .mexicano: namedPlayers.count >= 4
        }
    }

    private func start() {
        savePresetIfNamed()

        switch mode {
        case .traditional:
            model.remember(players: namedTeamPlayers)
            model.store.configure(.traditional(rules: rules, teams: teams))

        case .pointCount:
            model.remember(players: namedTeamPlayers)
            model.store.configure(.pointCount(rules: pointRules, teams: teams))

        case .winnerCourt:
            model.remember(players: namedTeamPlayers)
            model.store.configure(.winnerCourt(rules: winnerCourtRules, teams: teams))

        case .friendly:
            model.remember(players: namedPlayers.map(\.name))
            model.store.configure(.friendly(FriendlySession(
                name: sessionName,
                rules: rules,
                players: namedPlayers
            )))
            // Nothing to score until there is a round, exactly as a tournament works.
            model.store.nextRound()

        case .americano, .mexicano:
            model.remember(players: namedPlayers.map(\.name))
            model.store.configure(.tournament(Tournament(
                name: sessionName,
                format: mode == .mexicano ? .mexicano : .americano,
                players: namedPlayers,
                config: config
            )))
            model.store.nextRound()
        }
        dismiss()
    }

    private var namedTeamPlayers: [String] {
        (playersA + playersB).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
