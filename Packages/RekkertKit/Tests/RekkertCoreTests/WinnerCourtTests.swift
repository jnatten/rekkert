import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID()

private func log(_ rule: DeuceRule = .goldenPoint) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.winnerCourt(
        rules: WinnerCourtRules(deuceRule: rule),
        teams: BySide(a: .home, b: .away)
    )), from: device)
    return log
}

private func session(_ log: MatchLog) -> WinnerCourtSession? {
    guard case .winnerCourt(let value)? = SessionReducer.state(of: log) else { return nil }
    return value
}

private func score(_ log: inout MatchLog, _ sequence: [TeamSide]) {
    for team in sequence { log.append(.point(round: 0, court: 0, team: team), from: device) }
}

@Suite("Winner court")
struct WinnerCourtTests {
    @Test func gamesAccumulateWithoutEverCompletingASet() {
        var value = log()
        for _ in 0 ..< 9 { score(&value, [.a, .a, .a, .a]) }

        let state = try! #require(session(value))
        #expect(state.score.games == BySide(a: 9, b: 0), "a set of nine games and counting")
        #expect(state.score.completedSets.isEmpty, "no set ends on its own")
        #expect(state.roundNumber == 1)
        #expect(state.score.isFinished == false, "and the match never ends on its own")
    }

    @Test func scoringStillRunsFifteenThirtyForty() {
        var value = log()
        score(&value, [.a, .b, .a])

        let engine = try! #require(session(value)).engine
        let display = engine.pointDisplay(try! #require(session(value)).score)
        #expect(display.a.text == "30")
        #expect(display.b.text == "15")
    }

    @Test func theWhistleAwardsTheGameInProgressToWhoeverLeads() {
        var value = log()
        score(&value, [.a, .a, .a, .a])   // 1-0 in games
        score(&value, [.a, .a, .b])       // 30-15 to A in the game under way
        value.blowWhistle(from: device)

        let state = try! #require(session(value))
        #expect(state.completedRounds.count == 1)
        #expect(state.completedRounds[0].games == BySide(a: 2, b: 0), "the part-played game counts")
        #expect(state.completedRounds[0].winner == .a)
        #expect(state.score.games == BySide(both: 0), "the next round starts clean")
        #expect(state.roundNumber == 2)
    }

    @Test func aLevelGameInProgressIsDiscarded() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        score(&value, [.a, .b, .a, .b])   // 30-30, nobody ahead
        value.blowWhistle(from: device)

        #expect(session(value)?.completedRounds[0].games == BySide(a: 1, b: 0))
    }

    @Test func aRoundCanEndLevelWithNoWinner() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        score(&value, [.b, .b, .b, .b])
        value.blowWhistle(from: device)

        let round = try! #require(session(value)?.completedRounds.first)
        #expect(round.games == BySide(a: 1, b: 1))
        #expect(round.winner == nil, "1-1 is a draw, not a win for either side")
    }

    @Test func theWhistleOnAnUntouchedRoundDoesNothing() {
        var value = log()
        value.blowWhistle(from: device)
        #expect(session(value)?.completedRounds.isEmpty == true)
        #expect(session(value)?.roundNumber == 1)
    }

    @Test func roundsAndTotalsAddUpAcrossTheSession() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        score(&value, [.a, .a, .a, .a])
        value.blowWhistle(from: device)      // round 1: 2-0 to us

        score(&value, [.b, .b, .b, .b])
        value.blowWhistle(from: device)      // round 2: 0-1 to them

        score(&value, [.a, .a, .a, .a])            // round 3 under way

        let state = try! #require(session(value))
        #expect(state.roundNumber == 3)
        #expect(state.roundsWon == BySide(a: 1, b: 1))
        #expect(state.totalGames == BySide(a: 3, b: 1), "including the round in progress")
    }

    @Test func goldenPointDecidesAtFortyForty() {
        var value = log(.goldenPoint)
        score(&value, [.a, .b, .a, .b, .a, .b])

        let state = try! #require(session(value))
        #expect(state.engine.isSuddenDeathPoint(state.score))

        score(&value, [.b])
        #expect(session(value)?.score.games == BySide(a: 0, b: 1))
    }

    @Test func deuceIsPlayedOutWhenConfigured() {
        var value = log(.advantage)
        score(&value, [.a, .b, .a, .b, .a, .b])

        let state = try! #require(session(value))
        #expect(!state.engine.isSuddenDeathPoint(state.score))

        score(&value, [.a])
        #expect(session(value)?.engine.pointDisplay(session(value)!.score).a.text == "AD")
        #expect(session(value)?.score.games == BySide(both: 0), "advantage is not the game")

        score(&value, [.a])
        #expect(session(value)?.score.games == BySide(a: 1, b: 0))
    }

    @Test func serviceAlternatesBetweenTheTeamsEveryGame() {
        var value = log()
        var teams: [TeamSide] = []
        for _ in 0 ..< 4 {
            teams.append(try! #require(session(value)).engine.serve(session(value)!.score).slot.team)
            score(&value, [.a, .a, .a, .a])
        }
        #expect(teams == [.a, .b, .a, .b])
    }

    @Test func finishingLocksTheSession() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        value.append(.finish(archive: true), from: device)

        #expect(session(value)?.isFinished == true)
        #expect(SessionReducer.state(of: value)?.isFinished == true)

        score(&value, [.b, .b, .b, .b])
        #expect(session(value)?.score.games == BySide(a: 1, b: 0), "a finished session ignores points")
    }

    @Test func bothDevicesWhistlingAtOnceClosesOneRound() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        let watch = DeviceID()

        var onPhone = value
        var onWatch = value
        let fromPhone = onPhone.blowWhistle(from: device)
        let fromWatch = onWatch.blowWhistle(from: watch)

        onPhone.merge([fromWatch])
        onWatch.merge([fromPhone])

        #expect(session(onPhone)?.completedRounds.count == 1, "one whistle, one round")
        #expect(session(onPhone)?.roundNumber == 2)
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func aPointThatLandsBetweenTwoWhistlesDoesNotCloseASecondRound() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        let watch = DeviceID()

        var onPhone = value
        var onWatch = value
        let fromPhone = onPhone.blowWhistle(from: device)
        // The watch scores one more, then whistles too.
        onWatch.append(.point(round: 0, court: 0, team: .b), from: watch)
        let fromWatch = onWatch.blowWhistle(from: watch)

        onPhone.merge([fromWatch] + onWatch.ordered)
        onWatch.merge([fromPhone])

        #expect(session(onPhone)?.completedRounds.count == 1, "still just the one round")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func undoingTheWhistleReopensTheRound() {
        var value = log()
        score(&value, [.a, .a, .a, .a])
        let whistle = value.blowWhistle(from: device)
        #expect(session(value)?.roundNumber == 2)

        value.append(.undo(whistle.id), from: device)
        #expect(session(value)?.roundNumber == 1)
        #expect(session(value)?.score.games == BySide(a: 1, b: 0), "back where we were")
    }
}
