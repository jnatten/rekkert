import Foundation
@testable import RekkertCore

func makeFriendly(
    players: Int,
    id: String = "00000000-0000-0000-0000-0000000000A1",
    rules: TraditionalRules = TraditionalRules(setsToWin: 1)
) -> FriendlySession {
    FriendlySession(
        id: FriendlyID(UUID(uuidString: id)!),
        name: "Thursday",
        rules: rules,
        players: (0 ..< players).map { Player(name: "P\($0)") }
    )
}

/// Draws `count` rounds without anybody scoring in them. The draw never reads a score, so an
/// unplayed round schedules exactly as a played one would.
func draw(_ session: FriendlySession, rounds count: Int) throws -> FriendlySession {
    try (0 ..< count).reduce(session) { current, _ in
        try FriendlyScheduler.appendingRound(to: current)
    }
}

func partnerCounts(_ session: FriendlySession) -> [PairKey: Int] {
    var history = PairingHistory()
    for round in session.rounds { history.record([round.teams], sitOuts: round.sitOuts) }
    return history.partnered
}

func opponentCounts(_ session: FriendlySession) -> [PairKey: Int] {
    var history = PairingHistory()
    for round in session.rounds { history.record([round.teams], sitOuts: round.sitOuts) }
    return history.opposed
}

func benchCounts(_ session: FriendlySession) -> [String: Int] {
    var counts: [String: Int] = [:]
    for player in session.players { counts[player.name] = 0 }
    for round in session.rounds {
        for id in round.sitOuts { counts[session.name(id), default: 0] += 1 }
    }
    return counts
}

/// Every round as a line of names, the only form a draw can be pinned in: `Player(name:)`
/// mints a fresh id every run.
func drawn(_ session: FriendlySession) -> [String] {
    session.rounds.map { round in
        let sides = TeamSide.allCases.map { session.names($0, in: round) }.joined(separator: " v ")
        let bench = session.sitOutNames(in: round)
        return bench.isEmpty ? sides : "\(sides) (\(bench.joined(separator: ", ")) out)"
    }
}

/// Who is paired with whom, regardless of sides and of who is listed first.
func partition(_ round: FriendlyRound) -> Set<Set<PlayerID>> {
    [Set(round.teams.a), Set(round.teams.b)]
}
