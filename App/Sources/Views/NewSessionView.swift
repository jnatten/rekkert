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
            }
            TextField("Player 1", text: players[0])
            TextField("Player 2", text: players[1])
        }
        .textInputAutocapitalization(.words)
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
        Section("Tournament") {
            TextField("Name", text: $tournamentName)
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

        Section {
            ForEach($players) { $player in
                TextField("Player name", text: $player.name)
                    .textInputAutocapitalization(.words)
            }
            .onDelete { players.remove(atOffsets: $0) }

            Button("Add player") { players.append(Player(name: "")) }
        } header: {
            Text("Players (\(namedPlayers.count))")
        } footer: {
            Text(playerFooter)
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
            model.store.configure(.traditional(
                rules: rules,
                teams: BySide(
                    a: TeamInfo(name: teamA, players: playersA.filter { !$0.isEmpty }),
                    b: TeamInfo(name: teamB, players: playersB.filter { !$0.isEmpty })
                )
            ))
        case .some(let format):
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
