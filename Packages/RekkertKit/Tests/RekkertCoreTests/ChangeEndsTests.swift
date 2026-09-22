import Testing
@testable import RekkertCore

private func engine(
    _ rule: ChangeEndsRule,
    setsToWin: Int = 2,
    gamesPerSet: Int = 6,
    tiebreakAtGames: Int? = 6,
    decidingSet: DecidingSet = .normal
) -> TraditionalEngine {
    TraditionalEngine(rules: TraditionalRules(
        setsToWin: setsToWin,
        gamesPerSet: gamesPerSet,
        tiebreakAtGames: tiebreakAtGames,
        decidingSet: decidingSet,
        changeEnds: rule
    ))
}

/// Plays out a set that finishes `a`-`b`, sharing the games out so it does not close before
/// it gets there — six straight would end at 6-0 rather than reaching 6-6.
private func playSet(_ engine: TraditionalEngine, _ a: Int, _ b: Int, from state: TraditionalState) -> TraditionalState {
    var state = state
    var won = BySide(both: 0)
    while won.a < a || won.b < b {
        let side: TeamSide = won.a < a && (won.b >= b || won.a <= won.b) ? .a : .b
        state = engine.winGames(1, for: side, from: state)
        won[side] += 1
    }
    return state
}

/// Games won one each, so a set runs on rather than ending while the walks are being counted.
private func alternating(_ engine: TraditionalEngine, games: Int) -> [TraditionalState] {
    var state = engine.initialState()
    var states = [state]
    for index in 0 ..< games {
        state = engine.winGames(1, for: index.isMultiple(of: 2) ? .a : .b, from: state)
        states.append(state)
    }
    return states
}

@Suite("Changing ends")
struct ChangeEndsTests {
    @Test func aMatchNeverChangesEndsUnlessItIsAskedTo() {
        #expect(TraditionalRules().changeEnds == .off)

        let e = engine(.off)
        let states = alternating(e, games: 8)
        #expect(states.allSatisfy { e.changeovers($0) == 0 })
        #expect(states.allSatisfy { !e.endsSwapped($0) })
    }

    @Test func winnerCourtNeverChangesEnds() {
        #expect(WinnerCourtRules().scoring.changeEnds == .off)
        #expect(TraditionalRules.endless(deuceRule: .goldenPoint).changeEnds == .off)
    }

    /// The walks fall a pair of games apart, so which end you are at repeats every four
    /// games rather than every two. Counting the parity of the games themselves would read
    /// correctly for two games and then be wrong for the rest of the match.
    @Test func theCourtTurnsOverInPairsOfGames() {
        let e = engine(.oddGames, setsToWin: 3, gamesPerSet: 99, tiebreakAtGames: nil)
        let swapped = alternating(e, games: 8).map { e.endsSwapped($0) }
        #expect(swapped == [false, true, true, false, false, true, true, false, false])
    }

    /// Both leave everyone on the far side — five walks either way, since the tenth game of
    /// a 6-4 adds none. What the set's length decides is when the next walk comes: straight
    /// after the first game of the new set when the last one ran even, a game later when it
    /// ran odd. Counting the games across the match carries that over on its own.
    @Test func theNextSetPicksUpWhereTheLastOneLeftOff() {
        let e = engine(.oddGames)

        let odd = playSet(e, 6, 3, from: e.initialState())
        #expect(odd.completedSets.count == 1)
        #expect(e.endsSwapped(odd))
        #expect(e.endsSwapped(e.winGames(1, for: .a, from: odd)), "still, one game in")
        #expect(!e.endsSwapped(e.winGames(2, for: .a, from: odd)), "and back after the second")

        let even = playSet(e, 6, 4, from: e.initialState())
        #expect(even.completedSets.count == 1)
        #expect(e.endsSwapped(even))
        #expect(!e.endsSwapped(e.winGames(1, for: .a, from: even)), "back after the first")
    }

    @Test func aTiebreakChangesEndsEverySixPoints() {
        let e = engine(.oddGames)
        let sixAll = playSet(e, 6, 6, from: e.initialState())
        guard case .tiebreak = e.phase(sixAll) else { return #expect(Bool(false), "expected a tiebreak") }

        let before = e.changeovers(sixAll)
        #expect(e.changeovers(e.play(repeated([.a, .b], 2), from: sixAll)) == before, "nothing at four points")
        #expect(e.changeovers(e.play(repeated([.a, .b], 3), from: sixAll)) == before + 1, "a walk at six")
        #expect(e.changeovers(e.play(repeated([.a, .b], 6), from: sixAll)) == before + 2, "and another at twelve")
    }

    /// Banking a tiebreak swaps the games it was played at for a set in the list, which is
    /// where the count could jump: the set adds a game and the tiebreak's own points stop
    /// being read live. Dropping the walk that would have landed on the tiebreak's last
    /// point is what keeps the step to one, however long the tiebreak ran.
    @Test func bankingATiebreakMovesTheCourtOnByOne() {
        for tiebreak in [[TeamSide].init(repeating: .a, count: 7),      // 7-0
                         repeated([.a, .b], 5) + [.a, .a],              // 7-5
                         repeated([.a, .b], 6) + [.a, .a],              // 8-6
                         repeated([.a, .b], 10) + [.a, .a]] {           // 12-10
            let e = engine(.oddGames)
            let sixAll = playSet(e, 6, 6, from: e.initialState())
            let before = e.changeovers(sixAll)

            var running = sixAll
            var counts = [before]
            for side in tiebreak {
                running = e.scoringPoint(side, in: running)
                counts.append(e.changeovers(running))
            }

            #expect(running.completedSets.count == 1, "the tiebreak closed the set")
            #expect(counts.last == counts[counts.count - 2] + 1, "one walk as the set is banked")
            #expect(zip(counts, counts.dropFirst()).allSatisfy { $1 - $0 == 0 || $1 - $0 == 1 },
                    "and never two at a time anywhere in it")
            #expect(counts.first == before)
        }
    }

    /// A deciding super tiebreak is in the tiebreak phase from its very first point, so the
    /// walk into it can only come from the game the last set ended on.
    @Test func theWalkIntoASuperTiebreak() {
        let e = engine(.oddGames, decidingSet: .standardSuperTiebreak)
        let onePlusOne = playSet(e, 4, 6, from: playSet(e, 6, 3, from: e.initialState()))
        #expect(onePlusOne.completedSets.count == 2)
        guard case .tiebreak = e.phase(onePlusOne) else { return #expect(Bool(false), "expected a super tiebreak") }

        // 6-3 and 4-6 is nineteen games, and the nineteenth is a walk.
        let oneGameShort = playSet(e, 4, 5, from: playSet(e, 6, 3, from: e.initialState()))
        let before = e.changeovers(onePlusOne)
        #expect(before == e.changeovers(oneGameShort) + 1, "taken on the way in")

        #expect(e.changeovers(e.play(repeated([.a, .b], 3), from: onePlusOne)) == before + 1, "and six at a time inside it")
    }

    @Test func nobodyWalksOverToShakeHands() {
        let e = engine(.oddGames, setsToWin: 1)
        let matchPoint = e.winGames(5, for: .a, from: e.initialState())
        let onTheLastGame = e.endsSwapped(matchPoint)

        let won = e.winGames(1, for: .a, from: matchPoint)
        #expect(won.isFinished)
        #expect(e.endsSwapped(won) == onTheLastGame, "the board holds the ends the last point was played at")
    }

    @Test func everySetTurnsOverBetweenSetsOnly() {
        let e = engine(.everySet, setsToWin: 3)
        let midSet = e.winGames(3, for: .a, from: e.initialState())
        #expect(!e.endsSwapped(midSet), "games do not move it")

        let oneSet = e.winGames(6, for: .a, from: e.initialState())
        #expect(oneSet.completedSets.count == 1)
        #expect(e.endsSwapped(oneSet))

        let twoSets = e.winGames(6, for: .b, from: oneSet)
        #expect(!e.endsSwapped(twoSets), "and back again")
    }

    /// A friendly is a single set by default, and a single set ends the match — so there is
    /// never a set break to walk at.
    @Test func everySetIsInertInAOneSetMatch() {
        let e = engine(.everySet, setsToWin: 1)
        let won = e.winGames(6, for: .a, from: e.initialState())
        #expect(won.isFinished)
        #expect(!e.endsSwapped(won))
    }

    @Test func theCourtRewindsWithTheScore() {
        let e = engine(.oddGames)
        let afterOne = e.winGames(1, for: .a, from: e.initialState())
        #expect(e.endsSwapped(afterOne))

        // What undo leaves behind: the same state, two points short of the game.
        let partWay = e.play([.a, .a], from: e.initialState())
        #expect(!e.endsSwapped(partWay))
        #expect(e.changeovers(partWay) == 0)
    }

    @Test func theScoreboardCarriesTheCourt() {
        let rules = TraditionalRules(changeEnds: .oddGames)
        let session = TraditionalSession(
            rules: rules,
            teams: BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange")),
            score: TraditionalEngine(rules: rules).winGames(1, for: .a, from: TraditionalState())
        )
        let snapshot = ScoreboardSnapshot.make(from: .traditional(session))
        #expect(snapshot?.changeovers == 1)
        #expect(snapshot?.endsSwapped == true)
    }

    @Test func theModesWithNoEndsRuleNeverTurnOver() {
        let points = PointCountSession(
            rules: PointCountRules(),
            teams: BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange"))
        )
        #expect(ScoreboardSnapshot.make(from: .pointCount(points))?.endsSwapped == false)

        let court = WinnerCourtSession(
            rules: WinnerCourtRules(),
            teams: BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange"))
        )
        #expect(ScoreboardSnapshot.make(from: .winnerCourt(court))?.endsSwapped == false)
    }
}
