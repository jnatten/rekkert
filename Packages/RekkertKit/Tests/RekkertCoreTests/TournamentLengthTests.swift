import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-00000000000A")!)

private func makeTournament(
    _ format: TournamentFormat = .americano,
    players: Int = 4,
    courts: Int = 1,
    length: TournamentLength?,
    seed: Int = 0xFF
) -> Tournament {
    Tournament(
        id: TournamentID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", seed))!),
        name: "Test",
        format: format,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts, length: length)
    )
}

private func drawn(_ tournament: Tournament) throws -> Tournament {
    try TournamentEngine.appendingRound(to: tournament)
}

private func scored(_ tournament: Tournament) -> Tournament {
    var current = tournament
    let round = current.rounds.count - 1
    for index in current.rounds[round].matches.indices {
        current.rounds[round].matches[index].state.points = BySide(a: 9, b: 7)
    }
    return current
}

private func played(_ tournament: Tournament, rounds: Int) throws -> Tournament {
    var current = tournament
    for _ in 0 ..< rounds {
        current = try scored(drawn(current))
    }
    return current
}

/// Draws and plays rounds until the rotation is complete, or gives up at `cap`.
private func roundsToCompleteRotation(_ tournament: Tournament, cap: Int = 30) throws -> Int? {
    var current = tournament
    while current.rounds.count < cap {
        current = try scored(drawn(current))
        if current.plan?.isReached == true { return current.rounds.count }
    }
    return nil
}

@Suite("Tournament length")
struct TournamentLengthTests {
    @Test func anOpenTournamentHasNoPlan() throws {
        let t = try played(makeTournament(length: nil), rounds: 10)
        #expect(t.plan == nil)
    }

    @Test func aSetNumberOfRoundsIsReachedOnceTheLastIsPlayed() throws {
        var t = makeTournament(length: .rounds(3))
        #expect(t.plan?.progress == "3 rounds planned")

        t = try played(t, rounds: 2)
        #expect(t.plan?.progress == "3 rounds planned · 1 to go")

        t = try drawn(t)
        #expect(t.plan?.finalRound == 2)
        #expect(t.plan?.isReached == false, "drawn, but nobody has played it")
        #expect(t.plan?.finishPromptRound == nil)
        #expect(t.plan?.progress == "3 rounds planned · this is the last one")

        t = scored(t)
        #expect(t.plan?.isReached == true)
        #expect(t.plan?.finishPromptRound == 2)
        #expect(t.plan?.progress == "All 3 planned rounds played")
    }

    @Test func aCancelledRoundDoesNotCount() throws {
        var t = try played(makeTournament(length: .rounds(2)), rounds: 1)
        t = try drawn(t)
        t.rounds[1].isCancelled = true
        #expect(t.plan?.finalRound == nil)
        #expect(t.plan?.progress == "2 rounds planned · 1 to go")

        t = try scored(drawn(t))
        #expect(t.plan?.finalRound == 2)
        #expect(t.plan?.finishPromptRound == 2)
    }

    @Test func playingOnKeepsThePlanReachedWithoutAskingAgain() throws {
        var t = try played(makeTournament(length: .rounds(2)), rounds: 2)
        #expect(t.plan?.finishPromptRound == 1)

        t = try drawn(t)
        #expect(t.plan?.isReached == true)
        #expect(t.plan?.finalRound == 1)
        #expect(t.plan?.finishPromptRound == nil)

        t = scored(t)
        #expect(t.plan?.finishPromptRound == nil, "only the planned last round asks")
    }

    @Test func reopeningTheLastRoundAsksForTheSameRoundAgain() throws {
        var t = try played(makeTournament(length: .rounds(1)), rounds: 1)
        #expect(t.plan?.finishPromptRound == 0)

        t.rounds[0].matches[0].state.points = BySide(a: 3, b: 2)
        #expect(t.plan?.finishPromptRound == nil)
        #expect(t.plan?.isReached == false)

        t = scored(t)
        #expect(t.plan?.finishPromptRound == 0)
    }

    @Test func aFinishedTournamentIsNotAskedToFinish() throws {
        var t = try played(makeTournament(length: .rounds(1)), rounds: 1)
        t.isFinished = true
        #expect(t.plan?.isReached == true)
        #expect(t.plan?.finishPromptRound == nil)
    }

    @Test func aResumedTournamentRemembersItsPlanWasReached() throws {
        var t = try played(makeTournament(length: .rounds(1)), rounds: 1)
        t.isFinished = true
        guard case .tournament(let resumed)? = SessionState.tournament(t).resumed() else {
            Issue.record("expected a tournament")
            return
        }
        #expect(resumed.plan?.isReached == true)
    }

    @Test func fourPlayersRotateInThreeRounds() throws {
        var t = makeTournament(length: .fullRotation)
        #expect(t.plan?.partnershipsLeft == 6)
        var left: [Int?] = []
        for _ in 0 ..< 3 {
            t = try drawn(t)
            left.append(t.plan?.partnershipsLeft)
            t = scored(t)
        }
        #expect(left == [4, 2, 0])
        #expect(t.plan?.finalRound == 2)
        #expect(t.plan?.isReached == true)
        #expect(t.plan?.progress == "Full rotation done: everyone has partnered everyone")
    }

    @Test func theRoundThatCompletesTheRotationSaysSo() throws {
        let t = try drawn(played(makeTournament(length: .fullRotation), rounds: 2))
        #expect(t.plan?.progress == "Full rotation · everyone has partnered everyone after this round")
    }

    @Test func fivePlayersCompleteTheRotation() throws {
        let rounds = try #require(try roundsToCompleteRotation(makeTournament(players: 5, length: .fullRotation)))
        #expect(rounds >= 5)
        #expect(rounds <= 7)
    }

    @Test func eightPlayersOnTwoCourtsRotateInSevenWithThisSeed() throws {
        let rounds = try roundsToCompleteRotation(makeTournament(players: 8, courts: 2, length: .fullRotation))
        #expect(rounds == 7)
    }

    /// The draw looks one round ahead at a time, so a rotation can need a round past the
    /// fewest it could be done in. One seed in two hundred did.
    @Test(arguments: 1 ... 40)
    func eightPlayersOnTwoCourtsRotateInAtMostOneRoundMore(seed: Int) throws {
        let rounds = try #require(try roundsToCompleteRotation(
            makeTournament(players: 8, courts: 2, length: .fullRotation, seed: seed)
        ))
        #expect(rounds >= 7)
        #expect(rounds <= 8)
    }

    @Test func lengthsThatDoNotApplyAreOpen() {
        #expect(makeTournament(.mexicano, length: .fullRotation).length == nil)
        #expect(makeTournament(.mexicano, length: .rounds(5)).length == .rounds(5))
        #expect(makeTournament(.winnerCourt, length: .rounds(2)).length == nil)
        #expect(makeTournament(length: .rounds(0)).length == nil)
    }

    @Test(arguments: [(8, 2, 7), (5, 1, 5), (6, 1, 8), (12, 3, 11)])
    func fewestRounds(players: Int, courts: Int, expected: Int) {
        #expect(TournamentPlan.fewestRounds(players: players, courts: courts) == expected)
    }

    @Test func fewerThanFourPlayersCannotRotate() {
        #expect(TournamentPlan.fewestRounds(players: 3, courts: 1) == nil)
    }

    // MARK: - Encoding

    @Test func anOpenTournamentEncodesNoLength() throws {
        let data = try JSONCoding.encoder.encode(makeTournament(length: nil).config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["length"] == nil)
    }

    @Test func aTournamentBegunBeforeLengthsReadsAsOpen() throws {
        let tournament = makeTournament(length: nil)
        let back = try JSONCoding.decoder.decode(Tournament.self, from: JSONCoding.encoder.encode(tournament))
        #expect(back == tournament)
        #expect(back.config.length == nil)
    }

    @Test(arguments: [TournamentLength.fullRotation, .rounds(7)])
    func aLengthSurvivesAnEncode(length: TournamentLength) throws {
        let config = makeTournament(length: length).config
        let back = try JSONCoding.decoder.decode(TournamentConfig.self, from: JSONCoding.encoder.encode(config))
        #expect(back == config)
    }

    @Test func aLengthFromALaterBuildReadsAsOpen() throws {
        let config = makeTournament(length: .rounds(7)).config
        let data = try JSONCoding.encoder.encode(config)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["length"] = ["timed": ["minutes": 90]]

        let back = try JSONCoding.decoder.decode(
            TournamentConfig.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(back.length == nil)
        #expect(back.courtCount == config.courtCount)
        #expect(back.pointRules == config.pointRules)
    }

    // MARK: - Replay

    @Test func reachingThePlanNeverFinishesTheTournament() throws {
        var log = MatchLog(sessionID: UUID(uuidString: "33333333-0000-0000-0000-000000000000")!)
        log.append(.configure(.tournament(makeTournament(length: .rounds(1)))), from: device)
        log.drawRound(from: device)
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 9, b: 7)), from: device)

        guard case .tournament(let t)? = SessionReducer.state(of: log) else {
            Issue.record("expected a tournament")
            return
        }
        #expect(t.plan?.finishPromptRound == 0)
        #expect(t.isFinished == false)
        #expect(SessionReducer.state(of: log)?.isFinished == false)

        log.drawRound(from: device)
        guard case .tournament(let further)? = SessionReducer.state(of: log) else {
            Issue.record("expected a tournament")
            return
        }
        #expect(further.rounds.count == 2, "there is always another round")
    }
}
