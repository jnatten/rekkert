import Testing
@testable import RekkertCore

private func engine(_ rule: DeuceRule) -> TraditionalEngine {
    TraditionalEngine(rules: TraditionalRules(deuceRule: rule))
}

/// Four points each takes the game to 40-40 (deuce #1).
private let toDeuce: [TeamSide] = [.a, .b, .a, .b, .a, .b]

@Suite("Deuce rules")
struct DeuceRuleTests {
    @Test func ladderRunsLoveFifteenThirtyForty() {
        let e = engine(.advantage)
        let displays = (0 ... 3).map { n in
            e.pointDisplay(e.play(Array(repeating: .a, count: n))).a.text
        }
        #expect(displays == ["0", "15", "30", "40"])
    }

    @Test func straightGameNeedsFourPoints() {
        let e = engine(.advantage)
        let state = e.play([.a, .a, .a, .a])
        #expect(state.games.a == 1)
        #expect(state.points.total == 0)
    }

    @Test func advantageRequiresTwoClearPoints() {
        let e = engine(.advantage)
        var state = e.play(toDeuce)
        #expect(state.deuceCount == 1)
        #expect(e.pointDisplay(state) == BySide(a: .forty, b: .forty))

        state = e.scoringPoint(.a, in: state)
        #expect(e.pointDisplay(state).a == .advantage)
        #expect(state.games.a == 0)

        state = e.scoringPoint(.b, in: state)
        #expect(state.deuceCount == 2)
        #expect(e.pointDisplay(state) == BySide(a: .forty, b: .forty))

        state = e.play([.a, .a], from: state)
        #expect(state.games.a == 1)
    }

    @Test func advantageNeverReachesSuddenDeath() {
        let e = engine(.advantage)
        let state = e.play(toDeuce + repeated([.a, .b], 20))
        #expect(state.deuceCount == 21)
        #expect(!e.isSuddenDeathPoint(state))
        #expect(state.games.a == 0)
    }

    @Test func goldenPointDecidesTheFirstDeuce() {
        let e = engine(.goldenPoint)
        let state = e.play(toDeuce)
        #expect(state.deuceCount == 1)
        #expect(e.isSuddenDeathPoint(state))

        let won = e.scoringPoint(.b, in: state)
        #expect(won.games.b == 1)
        #expect(won.games.a == 0)
    }

    @Test func starPointPlaysTwoDeucesThenDecides() {
        let e = engine(.starPoint)
        var state = e.play(toDeuce)

        #expect(state.deuceCount == 1)
        #expect(!e.isSuddenDeathPoint(state), "first deuce is played with advantage")

        state = e.play([.a, .b], from: state)
        #expect(state.deuceCount == 2)
        #expect(!e.isSuddenDeathPoint(state), "second deuce is played with advantage")

        state = e.play([.b, .a], from: state)
        #expect(state.deuceCount == 3)
        #expect(e.isSuddenDeathPoint(state), "third 40-40 is sudden death")

        let won = e.scoringPoint(.a, in: state)
        #expect(won.games.a == 1)
    }

    @Test func starPointGameCanStillBeWonOnAdvantage() {
        let e = engine(.starPoint)
        let state = e.play(toDeuce + [.a, .a])
        #expect(state.games.a == 1)
        #expect(state.deuceCount == 0, "deuce count resets with the game")
    }

    @Test func theServeSideChoiceSurvivesReplayAndClearsAfterThePoint() {
        let device = DeviceID()
        var log = MatchLog()
        log.append(.configure(.traditional(
            rules: TraditionalRules(deuceRule: .goldenPoint),
            teams: BySide(a: .home, b: .away)
        )), from: device)
        for team in toDeuce { log.append(.point(round: 0, court: 0, team: team), from: device) }
        log.append(.chooseServeSide(.ad), from: device)

        guard case .traditional(let atDeuce)? = SessionReducer.state(of: log) else {
            Issue.record("no session")
            return
        }
        #expect(atDeuce.engine.serve(atDeuce.score).court == .ad)
        #expect(log.lastUndoableEvent()?.kind != .chooseServeSide(.ad), "undo still targets the last point")

        log.append(.point(round: 0, court: 0, team: .a), from: device)
        guard case .traditional(let after)? = SessionReducer.state(of: log) else { return }
        #expect(after.score.suddenDeathCourt == nil)
        #expect(after.score.games.a == 1)
    }

    @Test func receiversPickSideOnlyOnTheSuddenDeathPoint() {
        let e = engine(.goldenPoint)
        var state = e.play(toDeuce)
        #expect(e.serve(state).court == .deuce, "6 points played is an even total")

        state.suddenDeathCourt = .ad
        #expect(e.serve(state).court == .ad)

        let after = e.scoringPoint(.a, in: state)
        #expect(after.suddenDeathCourt == nil)
    }
}
