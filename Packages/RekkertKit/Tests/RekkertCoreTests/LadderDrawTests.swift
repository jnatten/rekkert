import Foundation
import Testing
@testable import RekkertCore

func makeLadder(
    players: Int,
    courts: Int,
    partners: LadderPartners = .fixed,
    start: LadderStart = .asListed,
    minutes: Int? = 12
) -> Tournament {
    Tournament(
        id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000EE")!),
        name: "Ladder",
        format: .winnerCourt,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(
            courtCount: courts,
            ladder: LadderRules(roundMinutes: minutes, partners: partners, start: start)
        )
    )
}

/// Whistles the last round with court `c` won 3–1 by `winners[c]`.
func settle(_ tournament: Tournament, _ winners: [TeamSide]) -> Tournament {
    var settled = tournament
    let round = settled.rounds.count - 1
    let engine = try! #require(settled.gameEngine)
    for index in settled.rounds[round].matches.indices {
        let side = winners[index]
        let games = engine.winGames(3, for: side, from: TraditionalState())
        settled.rounds[round].matches[index].games = engine.winGames(1, for: side.other, from: games)
    }
    settled.rounds[round].isEnded = true
    return settled
}

private func draw(_ tournament: Tournament, sitOuts: [PlayerID]? = nil) throws -> Tournament {
    try TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts)
}

/// The last round, court by court, as the names on each side.
private func courts(_ tournament: Tournament) -> [[[String]]] {
    (tournament.currentRound?.matches ?? []).map { match in
        TeamSide.allCases.map { side in match.teams[side].compactMap { tournament.player($0)?.name } }
    }
}

private func bench(_ tournament: Tournament) -> [String] {
    (tournament.currentRound?.sitOuts ?? []).compactMap { tournament.player($0)?.name }
}

private func id(_ tournament: Tournament, _ name: String) -> PlayerID {
    tournament.players.first { $0.name == name }!.id
}

@Suite("Winner court ladder: the draw")
struct LadderDrawTests {
    @Test func pairsAreTheListTakenTwoAtATime() throws {
        let t = try draw(makeLadder(players: 8, courts: 2))
        #expect(courts(t) == [[["P0", "P1"], ["P2", "P3"]], [["P4", "P5"], ["P6", "P7"]]])
        #expect(t.currentRound?.matches.allSatisfy { $0.games == TraditionalState() } == true, "every court scored in games")
    }

    @Test func randomStartIsTheSameOnEveryDeviceAndKeepsThePairs() throws {
        let one = try draw(makeLadder(players: 12, courts: 3, start: .random))
        let two = try draw(makeLadder(players: 12, courts: 3, start: .random))
        #expect(courts(one) == courts(two))
        let pairs = Set(courts(one).flatMap(\.self).map(Set.init))
        #expect(pairs == [["P0", "P1"], ["P2", "P3"], ["P4", "P5"], ["P6", "P7"], ["P8", "P9"], ["P10", "P11"]])
    }

    @Test func winnersMoveUpAndLosersMoveDown() throws {
        var t = try draw(makeLadder(players: 12, courts: 3))
        t = try draw(settle(t, [.b, .a, .b]))
        #expect(courts(t) == [
            [["P2", "P3"], ["P4", "P5"]],
            [["P0", "P1"], ["P10", "P11"]],
            [["P6", "P7"], ["P8", "P9"]],
        ], "court 1's winners stay, court 2's come up, court 1's losers go down, court 3's losers stay")
    }

    @Test func oneCourtKeepsTheSameTwoPairs() throws {
        var t = try draw(makeLadder(players: 4, courts: 1))
        t = try draw(settle(t, [.b]))
        #expect(courts(t) == [[["P2", "P3"], ["P0", "P1"]]])
    }

    @Test func theFirstRoundCanHaveABench() throws {
        let t = try draw(makeLadder(players: 10, courts: 2))
        #expect(t.currentRound?.matches.count == 2)
        #expect(bench(t).count == 2)
        let pairs = [["P0", "P1"], ["P2", "P3"], ["P4", "P5"], ["P6", "P7"], ["P8", "P9"]]
        #expect(pairs.contains(bench(t)), "a pair sits out together")
    }

    @Test func theBenchRotatesWholePairsFairly() throws {
        var t = try draw(makeLadder(players: 10, courts: 2))
        var benched = [bench(t)]
        for _ in 1 ..< 5 {
            t = try draw(settle(t, [.a, .b]))
            benched.append(bench(t))
        }
        #expect(Set(benched).count == 5, "every pair sits out once in five rounds")
    }

    @Test func aPairBackFromTheBenchStartsOnTheBottomCourt() throws {
        var t = try draw(makeLadder(players: 10, courts: 2))
        let back = bench(t)
        t = try draw(settle(t, [.a, .a]))
        #expect(courts(t)[1][1] == back)
    }

    @Test func aBenchedWinnersPlaceGoesToTheNextOneDown() throws {
        let base = makeLadder(players: 10, courts: 2)
        var t = try draw(base, sitOuts: [id(base, "P8")])
        #expect(courts(t) == [[["P0", "P1"], ["P2", "P3"]], [["P4", "P5"], ["P6", "P7"]]])
        t = try draw(settle(t, [.a, .a]), sitOuts: [id(t, "P0")])
        #expect(courts(t) == [[["P4", "P5"], ["P2", "P3"]], [["P6", "P7"], ["P8", "P9"]]])
        #expect(bench(t) == ["P0", "P1"])
    }

    @Test func choosingOnePlayerBenchesTheirPartnerToo() throws {
        let base = makeLadder(players: 10, courts: 2)
        let t = try draw(base, sitOuts: [id(base, "P3")])
        #expect(bench(t) == ["P2", "P3"])
    }

    @Test func moreSitOutsThanTheBenchHoldsAreRefused() {
        let base = makeLadder(players: 10, courts: 2)
        #expect(throws: TournamentError.invalidSitOuts) {
            try draw(base, sitOuts: [id(base, "P0"), id(base, "P2")])
        }
    }

    @Test func spareCourtsAreLeftEmpty() throws {
        let t = try draw(makeLadder(players: 8, courts: 3))
        #expect(t.currentRound?.matches.count == 2)
    }

    @Test func anOddNumberOfPlayersCannotBePaired() {
        #expect(throws: TournamentError.unpairedPlayer) { try draw(makeLadder(players: 9, courts: 2)) }
    }

    @Test func aCancelledRoundMovesNobody() throws {
        var t = try draw(makeLadder(players: 8, courts: 2))
        t = try draw(settle(t, [.b, .b]))
        let second = courts(t)
        t.rounds[1].isCancelled = true
        t = try draw(t)
        #expect(courts(t) == second, "drawn from the round before the cancelled one")
    }

    @Test func redrawingAroundTheSameBenchGivesTheSameRound() throws {
        var t = try draw(makeLadder(players: 10, courts: 2, start: .random))
        t = try draw(settle(t, [.a, .b]))
        let sitting = try #require(t.currentRound?.sitOuts)
        let redrawn = try TournamentEngine.redrawingLastRound(of: t, sitOuts: sitting)
        #expect(redrawn.currentRound == t.currentRound)
    }

    @Test func aDrawTakesTheRoundItCarries() throws {
        let first = try draw(makeLadder(players: 8, courts: 2))
        let placed = LadderPlacement(try #require(try draw(settle(first, [.b, .b])).currentRound))
        let here = try TournamentEngine.appendingRound(to: settle(first, [.a, .a]), placed: placed)
        #expect(LadderPlacement(try #require(here.currentRound)) == placed,
                "whatever this device makes of the round before")
    }

    @Test func aCarriedRoundThatDoesNotFitIsDrawnAfresh() throws {
        let t = settle(try draw(makeLadder(players: 8, courts: 2)), [.a, .b])
        var placed = try #require(TournamentEngine.ladderPlacement(of: t))
        placed.courts[0].a[0] = Player(name: "Stranger").id
        #expect(try TournamentEngine.appendingRound(to: t, placed: placed).currentRound == draw(t).currentRound)
    }

    @Test func aRoundNobodyFinishedMovesEachCourtsHigherPairUp() throws {
        var t = try draw(makeLadder(players: 8, courts: 2))
        t = try draw(t)
        #expect(courts(t) == [[["P0", "P1"], ["P4", "P5"]], [["P2", "P3"], ["P6", "P7"]]])
    }

    @Test func theLadderDrawsTheRoundsItAlwaysHas() throws {
        var t = try draw(makeLadder(players: 10, courts: 2, start: .random))
        var drawn = [courts(t)]
        var benched = [bench(t)]
        for winners: [TeamSide] in [[.a, .b], [.b, .b], [.a, .a]] {
            t = try draw(settle(t, winners))
            drawn.append(courts(t))
            benched.append(bench(t))
        }
        #expect(drawn == [
            [[["P0", "P1"], ["P8", "P9"]], [["P2", "P3"], ["P6", "P7"]]],
            [[["P0", "P1"], ["P6", "P7"]], [["P2", "P3"], ["P4", "P5"]]],
            [[["P6", "P7"], ["P4", "P5"]], [["P0", "P1"], ["P8", "P9"]]],
            [[["P0", "P1"], ["P4", "P5"]], [["P8", "P9"], ["P2", "P3"]]],
        ])
        #expect(benched == [["P4", "P5"], ["P8", "P9"], ["P2", "P3"], ["P6", "P7"]])
    }
}

@Suite("Winner court ladder: split partners")
struct LadderSplitTests {
    @Test func aSplitStartPairsOneAndTwoAgainstThreeAndFour() throws {
        let t = try draw(makeLadder(players: 8, courts: 2, partners: .split))
        #expect(courts(t) == [[["P0", "P1"], ["P2", "P3"]], [["P4", "P5"], ["P6", "P7"]]])
    }

    @Test func lastRoundsPartnersFaceEachOther() throws {
        var t = try draw(makeLadder(players: 8, courts: 2, partners: .split))
        t = try draw(settle(t, [.a, .a]))
        #expect(courts(t) == [[["P0", "P4"], ["P1", "P5"]], [["P2", "P6"], ["P3", "P7"]]])
    }

    @Test func nobodyPartnersTheSamePlayerTwoRoundsRunningEvenWithABench() throws {
        var t = try draw(makeLadder(players: 13, courts: 3, partners: .split, start: .random))
        for winners: [TeamSide] in [[.a, .b, .a], [.b, .b, .a], [.a, .a, .b], [.b, .a, .b], [.a, .b, .b]] {
            let before = Set(t.currentRound!.matches.flatMap { [Set($0.teams.a), Set($0.teams.b)] })
            t = try draw(settle(t, winners))
            let after = Set(t.currentRound!.matches.flatMap { [Set($0.teams.a), Set($0.teams.b)] })
            #expect(before.isDisjoint(with: after))
            #expect(t.currentRound?.sitOuts.count == 1)
        }
    }

    @Test func theSplitLadderDrawsTheRoundsItAlwaysHas() throws {
        var t = try draw(makeLadder(players: 9, courts: 2, partners: .split, start: .random))
        var drawn = [courts(t)]
        var benched = [bench(t)]
        for winners: [TeamSide] in [[.a, .b], [.b, .b], [.a, .a]] {
            t = try draw(settle(t, winners))
            drawn.append(courts(t))
            benched.append(bench(t))
        }
        #expect(drawn == [
            [[["P1", "P8"], ["P6", "P2"]], [["P5", "P3"], ["P0", "P7"]]],
            [[["P1", "P0"], ["P7", "P6"]], [["P2", "P5"], ["P3", "P4"]]],
            [[["P6", "P3"], ["P4", "P1"]], [["P0", "P5"], ["P2", "P8"]]],
            [[["P6", "P4"], ["P3", "P0"]], [["P1", "P2"], ["P8", "P7"]]],
        ])
        #expect(benched == [["P4"], ["P8"], ["P7"], ["P5"]])
    }
}

@Suite("Winner court ladder: the table")
struct LadderStandingsTests {
    private func names(_ standings: [Standing]) -> [String] { standings.map(\.player.name) }

    @Test func theLadderRanksByWhereEveryoneFinished() throws {
        let t = settle(try draw(makeLadder(players: 8, courts: 2)), [.b, .a])
        #expect(names(Leaderboard.standings(for: t)) == ["P2", "P3", "P0", "P1", "P4", "P5", "P6", "P7"])
    }

    @Test func theBenchRanksBelowEveryoneWhoPlayed() throws {
        let base = makeLadder(players: 10, courts: 2)
        let t = settle(try draw(base, sitOuts: [id(base, "P0")]), [.a, .a])
        #expect(names(Leaderboard.standings(for: t)).suffix(2) == ["P0", "P1"])
        #expect(Leaderboard.standings(for: t).allSatisfy { $0.compensation == 0 }, "sitting out earns nothing")
    }

    @Test func aLiveRoundRanksByWhereEveryoneIsPlaying() throws {
        var t = settle(try draw(makeLadder(players: 8, courts: 2)), [.b, .a])
        t = try draw(t)
        let standings = Leaderboard.standings(for: t)
        #expect(Set(names(standings).prefix(4)) == ["P2", "P3", "P4", "P5"], "court 1's four on top")
        #expect(standings.prefix(4).allSatisfy { $0.court == 0 })
    }

    @Test func roundsWonAndGamesAreCountedAlongside() throws {
        let t = settle(try draw(makeLadder(players: 8, courts: 2)), [.b, .a])
        let p2 = try #require(Leaderboard.standings(for: t).first { $0.player.name == "P2" })
        #expect(p2.roundsWon == 1)
        #expect(p2.pointsFor == 3)
        #expect(p2.pointsAgainst == 1)
        #expect(p2.roundsPlayed == 1)
    }
}

@Suite("Winner court ladder: saved before it existed")
struct LadderCompatibilityTests {
    @Test func anAmericanoRoundEncodesAsItAlwaysDid() throws {
        var t = Tournament(format: .americano, players: (0 ..< 4).map { Player(name: "P\($0)") })
        t = try TournamentEngine.appendingRound(to: t)
        let json = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        for key in ["games", "decider", "isEnded", "clock", "ladder"] {
            #expect(!json.contains("\"\(key)\""), "no \(key) on a tournament that has none")
        }
    }

    @Test func aRoundSavedBeforeTheWhistleStillDecodes() throws {
        let json = #"{"index":0,"matches":[],"sitOuts":[],"isCancelled":false}"#
        let round = try JSONDecoder().decode(Round.self, from: Data(json.utf8))
        #expect(!round.isEnded)
        #expect(round.clock == nil)
    }

    @Test func aDrawCarryingItsRoundTravelsWhole() throws {
        let t = try draw(makeLadder(players: 10, courts: 2))
        let kind = EventKind.nextRound(after: 0, placed: TournamentEngine.ladderPlacement(of: t))
        #expect(try JSONCoding.decoder.decode(EventKind.self, from: JSONCoding.encoder.encode(kind)) == kind)
    }

    @Test func ladderRulesMissingAKeyFallBackToTheDefaults() throws {
        let rules = try JSONDecoder().decode(LadderRules.self, from: Data(#"{"partners":"split"}"#.utf8))
        #expect(rules.partners == .split)
        #expect(rules.start == .random)
        #expect(rules.roundMinutes == nil, "an absent length is a match round, which is how nil is written")
        #expect(rules.rules.deuceRule == .goldenPoint)
    }
}
