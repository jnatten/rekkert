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

@Suite("Friendly draw")
struct FriendlyTests {
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
