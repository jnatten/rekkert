import Testing
@testable import RekkertCore

@Suite("Sets and matches")
struct SetAndMatchTests {
    let standard = TraditionalEngine(rules: TraditionalRules())

    @Test func sixGamesWinsASet() {
        let state = standard.winGames(6, for: .a, from: standard.initialState())
        #expect(state.completedSets.count == 1)
        #expect(state.completedSets[0].games == BySide(a: 6, b: 0))
        #expect(state.completedSets[0].winner == .a)
        #expect(state.games == BySide(both: 0), "games reset for the next set")
    }

    @Test func sixFiveIsNotASetButSevenFiveIs() {
        var state = standard.winGames(5, for: .a, from: standard.initialState())
        state = standard.winGames(5, for: .b, from: state)
        #expect(state.games == BySide(a: 5, b: 5))

        state = standard.winGames(1, for: .a, from: state)
        #expect(state.completedSets.isEmpty, "6-5 is not a set")

        state = standard.winGames(1, for: .a, from: state)
        #expect(state.completedSets.count == 1)
        #expect(state.completedSets[0].games == BySide(a: 7, b: 5))
    }

    @Test func sixAllEntersATiebreak() {
        var state = standard.winGames(5, for: .a, from: standard.initialState())
        state = standard.winGames(5, for: .b, from: state)
        state = standard.winGames(1, for: .a, from: state)
        state = standard.winGames(1, for: .b, from: state)

        #expect(standard.phase(state) == .tiebreak(target: 7))
        #expect(standard.pointDisplay(state) == BySide(a: .count(0), b: .count(0)))
    }

    @Test func tiebreakNeedsSevenPointsAndTwoClear() {
        var state = standard.winGames(5, for: .a, from: standard.initialState())
        state = standard.winGames(5, for: .b, from: state)
        state = standard.winGames(1, for: .a, from: state)
        state = standard.winGames(1, for: .b, from: state)

        state = standard.play(repeated([.a, .b], 6), from: state)
        #expect(state.points == BySide(a: 6, b: 6))
        #expect(state.completedSets.isEmpty, "7-6 in a tiebreak is not enough")

        state = standard.play([.a], from: state)
        #expect(state.completedSets.isEmpty)

        state = standard.play([.a], from: state)
        #expect(state.completedSets.count == 1)
        #expect(state.completedSets[0].games == BySide(a: 7, b: 6))
        #expect(state.completedSets[0].tiebreak == BySide(a: 8, b: 6))
    }

    @Test func tiebreakServeChangesAfterOnePointThenEveryTwo() {
        var state = standard.winGames(5, for: .a, from: standard.initialState())
        state = standard.winGames(5, for: .b, from: state)
        state = standard.winGames(1, for: .a, from: state)
        state = standard.winGames(1, for: .b, from: state)

        let teams = (0 ..< 7).map { n in
            standard.serve(standard.play(Array(repeating: TeamSide.a, count: n), from: state)).slot.team
        }
        #expect(teams == [.a, .b, .b, .a, .a, .b, .b])
    }

    @Test func bestOfThreeEndsAfterTwoSets() {
        var state = standard.winGames(6, for: .a, from: standard.initialState())
        #expect(state.winner == nil)

        state = standard.winGames(6, for: .a, from: state)
        #expect(state.winner == .a)
        #expect(standard.phase(state) == .finished)
    }

    @Test func finishedMatchIgnoresFurtherPoints() {
        var state = standard.winGames(6, for: .a, from: standard.initialState())
        state = standard.winGames(6, for: .a, from: state)
        let after = standard.play([.b, .b, .b, .b], from: state)
        #expect(after == state)
    }

    @Test func superTiebreakReplacesTheDecidingSet() {
        let engine = TraditionalEngine(
            rules: TraditionalRules(decidingSet: .standardSuperTiebreak)
        )
        var state = engine.winGames(6, for: .a, from: engine.initialState())
        state = engine.winGames(6, for: .b, from: state)
        #expect(engine.isDecidingSet(state))
        #expect(engine.phase(state) == .tiebreak(target: 10))

        state = engine.play(repeated([.a], 10), from: state)
        #expect(state.winner == .a)
        #expect(state.completedSets.last?.tiebreak == BySide(a: 10, b: 0))
    }

    @Test func advantageSetHasNoTiebreak() {
        let engine = TraditionalEngine(rules: TraditionalRules(tiebreakAtGames: nil))
        var state = engine.initialState()
        for _ in 0 ..< 6 {
            state = engine.winGames(1, for: .a, from: state)
            state = engine.winGames(1, for: .b, from: state)
        }
        #expect(state.games == BySide(a: 6, b: 6))
        #expect(engine.phase(state) == .game, "an advantage set never tiebreaks")

        state = engine.winGames(1, for: .a, from: state)
        #expect(state.completedSets.isEmpty, "7-6 does not win an advantage set")

        state = engine.winGames(1, for: .a, from: state)
        #expect(state.completedSets.first?.games == BySide(a: 8, b: 6))
    }

    @Test func serveAlternatesTeamsEveryGame() {
        var state = standard.initialState()
        var teams: [TeamSide] = []
        for _ in 0 ..< 4 {
            teams.append(standard.serve(state).slot.team)
            state = standard.winGames(1, for: .a, from: state)
        }
        #expect(teams == [.a, .b, .a, .b])
    }

    @Test func partnersAlternateServiceTurns() {
        var state = standard.initialState()
        var slots: [ServeSlot] = []
        for _ in 0 ..< 5 {
            slots.append(standard.serve(state).slot)
            state = standard.winGames(1, for: .a, from: state)
        }
        #expect(slots.map(\.playerIndex) == [0, 0, 1, 1, 0])
    }

    @Test func theRotationCarriesOnIntoTheNextSet() {
        var state = standard.winGames(6, for: .a, from: standard.initialState())
        #expect(state.completedSets.count == 1)
        #expect(standard.serve(state).slot == ServeSlot(team: .a, playerIndex: 1), "six games on, two steps round")

        state = standard.winGames(1, for: .a, from: state)
        #expect(standard.serve(state).slot == ServeSlot(team: .b, playerIndex: 1))

        state.serversSwapped[.b] = true
        #expect(standard.serve(state).slot == ServeSlot(team: .b, playerIndex: 0), "B's partners the other way round")
    }

    @Test func theTeamThatServedFirstInTheTiebreakReceivesFirstInTheNextSet() {
        var state = standard.winGames(5, for: .a, from: standard.initialState())
        state = standard.winGames(5, for: .b, from: state)
        state = standard.winGames(1, for: .a, from: state)
        state = standard.winGames(1, for: .b, from: state)
        #expect(standard.serve(state).slot.team == .a, "A opens the tiebreak")

        state = standard.play(Array(repeating: .a, count: 7), from: state)
        #expect(state.completedSets.count == 1)
        #expect(standard.serve(state).slot.team == .b, "so B serves the first game of the next set")
    }
}
