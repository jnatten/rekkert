import Testing
@testable import RekkertCore

@Suite("Point counting")
struct PointCountTests {
    @Test func totalPointsPlayedAlwaysSumsToTheTarget() {
        let e = PointCountEngine(rules: PointCountRules(target: 16, targetKind: .totalPointsPlayed))
        var state = e.play(repeated([.a, .a, .b], 5))
        #expect(state.points == BySide(a: 10, b: 5))
        #expect(!e.isFinished(state))
        #expect(e.pointsRemaining(state) == 1)

        state = e.play([.b], from: state)
        #expect(e.isFinished(state))
        #expect(state.points.total == 16)
        #expect(e.winner(state) == .a)
    }

    @Test func totalPointsPlayedCanEndLevel() {
        let e = PointCountEngine(rules: PointCountRules(target: 16, targetKind: .totalPointsPlayed))
        let state = e.play(repeated([.a, .b], 8))
        #expect(e.isFinished(state))
        #expect(e.winner(state) == nil, "8-8 is a legitimate draw")
    }

    @Test func firstToTargetEndsOnTheLeadersScore() {
        let e = PointCountEngine(rules: PointCountRules(target: 16, targetKind: .firstToTarget))
        var state = e.play(repeated([.a, .b], 15))
        #expect(state.points == BySide(a: 15, b: 15))
        #expect(!e.isFinished(state), "30 points played, still not over")

        state = e.play([.b], from: state)
        #expect(e.isFinished(state))
        #expect(e.winner(state) == .b)
    }

    @Test func finishedRoundIgnoresFurtherPoints() {
        let e = PointCountEngine(rules: PointCountRules(target: 4))
        let done = e.play(repeated([.a], 4))
        #expect(e.play([.b, .b], from: done) == done)
    }

    @Test(arguments: [16, 21, 24, 32])
    func anyTargetIsSupported(target: Int) {
        let e = PointCountEngine(rules: PointCountRules(target: target))
        let state = e.play(repeated([.a], target))
        #expect(e.isFinished(state))
        #expect(state.points.a == target)
    }

    @Test func eachTeamServesTwiceInTurn() {
        let e = PointCountEngine(rules: PointCountRules(target: 32, servesPerTeam: 2))
        let teams = (0 ..< 8).map { n in
            e.serve(e.play(Array(repeating: TeamSide.a, count: n))).slot.team
        }
        #expect(teams == [.a, .a, .b, .b, .a, .a, .b, .b])
    }

    @Test func allFourPlayersTakeATurnServing() {
        let e = PointCountEngine(rules: PointCountRules(target: 32, servesPerTeam: 2))
        let slots = stride(from: 0, to: 16, by: 2).map { n in
            e.serve(e.play(Array(repeating: TeamSide.a, count: n))).slot
        }
        #expect(slots == [
            ServeSlot(team: .a, playerIndex: 0),
            ServeSlot(team: .b, playerIndex: 0),
            ServeSlot(team: .a, playerIndex: 1),
            ServeSlot(team: .b, playerIndex: 1),
            ServeSlot(team: .a, playerIndex: 0),
            ServeSlot(team: .b, playerIndex: 0),
            ServeSlot(team: .a, playerIndex: 1),
            ServeSlot(team: .b, playerIndex: 1),
        ])
    }

    @Test func settingScoreClampsToTheTotalTarget() {
        let e = PointCountEngine(rules: PointCountRules(target: 16, targetKind: .totalPointsPlayed))
        let state = e.settingScore(BySide(a: 12, b: 99), in: e.initialState())
        #expect(state.points == BySide(a: 12, b: 4))
    }

    @Test func settingScoreRejectsNegatives() {
        let e = PointCountEngine(rules: PointCountRules(target: 16))
        let state = e.settingScore(BySide(a: -5, b: 3), in: e.initialState())
        #expect(state.points == BySide(a: 0, b: 3))
    }

    @Test func settingScoreCannotMakeBothSidesWin() {
        let e = PointCountEngine(rules: PointCountRules(target: 16, targetKind: .firstToTarget))
        let state = e.settingScore(BySide(a: 20, b: 20), in: e.initialState())
        #expect(state.points == BySide(a: 16, b: 15))
        #expect(e.winner(state) == .a)
    }
}
