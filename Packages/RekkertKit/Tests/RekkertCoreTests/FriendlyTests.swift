import Foundation
import Testing
@testable import RekkertCore

private func makeFriendly(
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
private func draw(_ session: FriendlySession, rounds count: Int) throws -> FriendlySession {
    try (0 ..< count).reduce(session) { current, _ in
        try FriendlyScheduler.appendingRound(to: current)
    }
}

private func partnerCounts(_ session: FriendlySession) -> [PairKey: Int] {
    var history = PairingHistory()
    for round in session.rounds { history.record([round.teams], sitOuts: round.sitOuts) }
    return history.partnered
}

private func opponentCounts(_ session: FriendlySession) -> [PairKey: Int] {
    var history = PairingHistory()
    for round in session.rounds { history.record([round.teams], sitOuts: round.sitOuts) }
    return history.opposed
}

private func benchCounts(_ session: FriendlySession) -> [String: Int] {
    var counts: [String: Int] = [:]
    for player in session.players { counts[player.name] = 0 }
    for round in session.rounds {
        for id in round.sitOuts { counts[session.name(id), default: 0] += 1 }
    }
    return counts
}

/// Every round as a line of names, the only form a draw can be pinned in: `Player(name:)`
/// mints a fresh id every run.
private func drawn(_ session: FriendlySession) -> [String] {
    session.rounds.map { round in
        let sides = TeamSide.allCases.map { session.names($0, in: round) }.joined(separator: " v ")
        let bench = session.sitOutNames(in: round)
        return bench.isEmpty ? sides : "\(sides) (\(bench.joined(separator: ", ")) out)"
    }
}

/// Who is paired with whom, regardless of sides and of who is listed first.
private func partition(_ round: FriendlyRound) -> Set<Set<PlayerID>> {
    [Set(round.teams.a), Set(round.teams.b)]
}

@Suite("Friendly draw")
struct FriendlyTests {
    /// A fingerprint of what five draw today. The cycle rule is for four alone, so everybody
    /// else has to keep drawing exactly what they always have — a draw that is still fair but
    /// different would silently re-partner a Thursday.
    @Test func fivePlayersDrawTheRoundsTheyAlwaysHave() throws {
        let session = try draw(makeFriendly(players: 5), rounds: 9)
        #expect(drawn(session) == [
            "P3 & P0 v P4 & P2 (P1 out)",
            "P0 & P4 v P3 & P1 (P2 out)",
            "P4 & P1 v P2 & P0 (P3 out)",
            "P3 & P2 v P1 & P0 (P4 out)",
            "P2 & P1 v P4 & P3 (P0 out)",
            "P2 & P0 v P4 & P3 (P1 out)",
            "P0 & P1 v P4 & P2 (P3 out)",
            "P0 & P3 v P2 & P1 (P4 out)",
            "P3 & P1 v P4 & P0 (P2 out)",
        ])
    }

    /// The first three rounds of four are the ordinary draw; only what follows them changes.
    @Test func fourPlayersOpenWithTheRoundsTheyAlwaysHave() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 3)
        #expect(drawn(session) == ["P0 & P2 v P3 & P1", "P1 & P0 v P3 & P2", "P2 & P1 v P3 & P0"])
    }

    @Test func fourPlayersReplayTheFirstThreeRoundsInOrder() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 9)
        #expect(Set(session.rounds.prefix(3).map(partition)).count == 3, "the opening three are all different")
        for round in session.rounds {
            #expect(
                round.teams == session.rounds[round.index % 3].teams,
                "round \(round.index + 1) is round \(round.index % 3 + 1) again, sides and all"
            )
            #expect(round.sitOuts.isEmpty)
        }
    }

    @Test func fourPlayersNeverKeepThePartnersFromTheRoundBefore() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 9)
        for (previous, next) in zip(session.rounds, session.rounds.dropFirst()) {
            #expect(partition(previous) != partition(next))
        }
    }

    @Test func aFriendlyDrawnByTheOldRuleSettlesIntoTheCycle() throws {
        var session = makeFriendly(players: 4)
        let p = session.players.map(\.id)
        let x = BySide(a: [p[0], p[1]], b: [p[2], p[3]])
        let y = BySide(a: [p[0], p[2]], b: [p[1], p[3]])
        let z = BySide(a: [p[0], p[3]], b: [p[1], p[2]])
        // The old draw could follow X, Y, Z with any of the three — here Y again, the other
        // way round — and a session in progress carries that history over.
        session.rounds = [x, y, z, BySide(a: y.b, b: y.a)].enumerated().map {
            FriendlyRound(index: $0.offset, teams: $0.element)
        }
        let healed = try draw(session, rounds: 5)
        #expect(
            healed.rounds.dropFirst(4).map(\.teams) == [x, z, x, y, z],
            "the least played goes next, then the three as they were first drawn"
        )
        #expect(healed.rounds[7].teams == y, "as first drawn, not as the repeat had it")
    }

    @Test func theFourPlayerCycleIsTheSameOnBothDevicesAndInThePreview() throws {
        let base = makeFriendly(players: 4)
        let one = try draw(base, rounds: 9)
        #expect(try draw(base, rounds: 9).rounds == one.rounds)
        for count in 0 ..< 9 {
            #expect(
                try draw(base, rounds: count).nextDraw() == one.rounds[count],
                "what the button offers is what the event draws"
            )
        }
    }

    @Test func fourPlayersPlayTwoAgainstTwoWithNobodyOut() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 1)
        let round = try #require(session.currentRound)
        #expect(round.teams.a.count == 2)
        #expect(round.teams.b.count == 2)
        #expect(round.sitOuts.isEmpty)
        #expect(Set(round.teams.a + round.teams.b).count == 4)
    }

    @Test func twoPlayersKeepTheSameSidesEveryRound() throws {
        let session = try draw(makeFriendly(players: 2), rounds: 5)
        let expected = BySide(a: [session.players[0].id], b: [session.players[1].id])
        #expect(session.rounds.allSatisfy { $0.teams == expected }, "the colours stay put")
        #expect(session.rounds.allSatisfy { $0.sitOuts.isEmpty })
    }

    @Test func threePlayersPlaySinglesAndTakeTurnsSittingOut() throws {
        let session = try draw(makeFriendly(players: 3), rounds: 3)
        #expect(session.teamSize == 1)
        #expect(session.rounds.allSatisfy { $0.teams.a.count == 1 && $0.teams.b.count == 1 })
        #expect(session.rounds.allSatisfy { $0.sitOuts.count == 1 })
        #expect(benchCounts(session).values.allSatisfy { $0 == 1 }, "each sits exactly once")
    }

    @Test func threePlayersMeetEveryoneInThreeRounds() throws {
        let session = try draw(makeFriendly(players: 3), rounds: 3)
        #expect(opponentCounts(session).count == 3, "all three pairings happen")
        #expect(opponentCounts(session).values.allSatisfy { $0 == 1 })
    }

    @Test func fivePlayersRotateTheSitOutFairly() throws {
        let session = try draw(makeFriendly(players: 5), rounds: 5)
        #expect(session.rounds.allSatisfy { $0.sitOuts.count == 1 })
        #expect(benchCounts(session).values.allSatisfy { $0 == 1 })
    }

    @Test func fivePlayersGetThroughEveryPartnershipWithoutRepeating() throws {
        // Five rounds of two partnerships each is exactly the ten pairs five people can make.
        let session = try draw(makeFriendly(players: 5), rounds: 5)
        #expect(partnerCounts(session).count == 10)
        #expect(partnerCounts(session).values.allSatisfy { $0 == 1 })
    }

    @Test func sixPlayersBenchTwoEachRound() throws {
        let session = try draw(makeFriendly(players: 6), rounds: 3)
        #expect(session.rounds.allSatisfy { $0.sitOuts.count == 2 })
        #expect(benchCounts(session).values.allSatisfy { $0 == 1 })
    }

    @Test(arguments: 2 ... 9)
    func everyoneIsEitherOnCourtOrOnTheBench(players count: Int) throws {
        let session = try draw(makeFriendly(players: count), rounds: 4)
        for round in session.rounds {
            let playing = round.teams.a + round.teams.b
            #expect(playing.count == session.seats)
            #expect(Set(playing).isDisjoint(with: Set(round.sitOuts)))
            #expect(Set(playing).union(round.sitOuts) == Set(session.players.map(\.id)))
            #expect(round.teams.a.count == session.teamSize)
            #expect(round.teams.b.count == session.teamSize)
        }
    }

    @Test func fourPlayersCycleAllThreePairings() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 3)
        let partners = partnerCounts(session)
        #expect(partners.count == 6, "all six partnerships, two per round")
        #expect(partners.values.allSatisfy { $0 == 1 }, "nobody partners anybody twice")
    }

    @Test func fourPlayersMeetEachOtherEqually() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 3)
        #expect(opponentCounts(session).values.allSatisfy { $0 == 2 })
    }

    @Test func eightPlayersAvoidRepeatPartners() throws {
        let session = try draw(makeFriendly(players: 8), rounds: 7)
        let worst = partnerCounts(session).values.max() ?? 0
        #expect(worst == 1, "seven rounds, fourteen partnerships, no repeats at all")
    }

    @Test func fewerThanTwoPlayersThrows() {
        #expect(throws: FriendlyError.notEnoughPlayers(needed: 2, have: 1)) {
            try FriendlyScheduler.appendingRound(to: makeFriendly(players: 1))
        }
        #expect(throws: FriendlyError.notEnoughPlayers(needed: 2, have: 0)) {
            try FriendlyScheduler.appendingRound(to: makeFriendly(players: 0))
        }
    }

    @Test func theDrawIsTheSameOnBothDevices() throws {
        // One session, drawn twice from nothing but its own id and the rounds so far — which
        // is exactly what the phone and the watch each do when they fold the log.
        let base = makeFriendly(players: 7)
        let one = try draw(base, rounds: 6)
        let two = try draw(base, rounds: 6)
        #expect(one.rounds == two.rounds, "no shared state, no system entropy")
    }

    @Test func aDifferentSessionDrawsDifferently() throws {
        let players = (0 ..< 6).map { Player(name: "P\($0)") }
        var one = makeFriendly(players: 0, id: "00000000-0000-0000-0000-0000000000A1")
        var two = makeFriendly(players: 0, id: "00000000-0000-0000-0000-0000000000B2")
        one.players = players
        two.players = players
        #expect(try draw(one, rounds: 4).rounds.map(\.teams) != draw(two, rounds: 4).rounds.map(\.teams))
    }

    @Test func theFirstServeMovesAroundFromRoundToRound() throws {
        let session = try draw(makeFriendly(players: 4), rounds: 5)
        #expect(session.rounds.map(\.score.firstServerIndex) == [0, 1, 2, 3, 0])
    }
}
