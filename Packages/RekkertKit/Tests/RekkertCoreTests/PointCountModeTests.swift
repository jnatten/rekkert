import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID()

private func log(target: Int = 16, kind: TargetKind = .totalPointsPlayed) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.pointCount(
        rules: PointCountRules(target: target, targetKind: kind),
        teams: BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange"))
    )), from: device)
    return log
}

private func session(_ log: MatchLog) -> PointCountSession? {
    guard case .pointCount(let value)? = SessionReducer.state(of: log) else { return nil }
    return value
}

private func board(_ log: MatchLog) -> ScoreboardSnapshot? {
    SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }
}

private func score(_ log: inout MatchLog, _ sequence: [TeamSide]) {
    for team in sequence { log.append(.point(round: 0, court: 0, team: team), from: device) }
}

@Suite("Points mode")
struct PointCountModeTests {
    @Test func pointsCountOneAtATime() throws {
        var value = log()
        score(&value, [.a, .b, .a, .a])

        let state = try #require(session(value))
        #expect(state.score.points == BySide(a: 3, b: 1))
        #expect(state.isFinished == false)
    }

    @Test func theRoundEndsWhenTheTargetIsReached() throws {
        var value = log(target: 6)
        score(&value, [.a, .a, .a, .a, .b, .b])

        let state = try #require(session(value))
        #expect(state.isFinished, "six points played out of six")
        #expect(state.winner == .a)
    }

    @Test func furtherPointsAfterTheTargetAreIgnored() throws {
        var value = log(target: 4)
        score(&value, [.a, .a, .a, .b, .a, .a])

        #expect(try #require(session(value)).score.points == BySide(a: 3, b: 1))
    }

    @Test func anEvenTargetCanEndLevel() throws {
        var value = log(target: 4)
        score(&value, [.a, .b, .a, .b])

        let state = try #require(session(value))
        #expect(state.isFinished)
        #expect(state.winner == nil, "a draw, so nobody won it")
    }

    @Test func firstToTargetEndsOnTheLeadersScore() throws {
        var value = log(target: 5, kind: .firstToTarget)
        score(&value, [.a, .a, .a, .a, .b, .a])

        let state = try #require(session(value))
        #expect(state.isFinished)
        #expect(state.score.points == BySide(a: 5, b: 1))
        #expect(state.winner == .a)
    }

    @Test func theScoreCanBeSetOutright() throws {
        var value = log()
        value.append(.setScore(round: 0, court: 0, points: BySide(a: 9, b: 7)), from: device)

        let state = try #require(session(value))
        #expect(state.score.points == BySide(a: 9, b: 7))
        #expect(state.isFinished, "which also finishes it, the same as playing it out")
    }

    @Test func settingAScoreIsClampedToTheTarget() throws {
        var value = log(target: 16)
        value.append(.setScore(round: 0, court: 0, points: BySide(a: 40, b: 40)), from: device)

        #expect(try #require(session(value)).score.points == BySide(a: 16, b: 0))
    }

    @Test func theRoundCanBeCalledOffBeforeTheTarget() throws {
        var value = log()
        score(&value, [.a, .b, .a])
        value.append(.finish(archive: false), from: device)

        let state = try #require(SessionReducer.state(of: value))
        #expect(state.isFinished, "stopped, though the target was never reached")
        #expect(state.hasResults, "and three points were played")
    }

    @Test func servingAlternatesEveryTwoPointsLikeAnAmericanoCourt() throws {
        var value = log()
        var serving: [TeamSide] = []
        for _ in 0 ..< 5 {
            serving.append(try #require(session(value)).engine.serve(session(value)!.score).slot.team)
            score(&value, [.a])
        }
        #expect(serving == [.a, .a, .b, .b, .a])
    }

    @Test func theSwapServeCorrectionWorksHereToo() throws {
        var value = log()
        value.append(.setFirstServer(round: 0, court: 0, index: 1), from: device)

        let state = try #require(session(value))
        #expect(state.engine.serve(state.score).slot.team == .b)
    }

    @Test func undoTakesAPointBack() throws {
        var value = log()
        score(&value, [.a, .a])
        let last = try #require(value.lastUndoableEvent())
        value.append(.undo(last.id), from: device)

        #expect(try #require(session(value)).score.points == BySide(a: 1, b: 0))
    }

    @Test func theScoreboardReadsAsPlainNumbers() throws {
        var value = log(target: 16)
        score(&value, [.a, .a, .b])

        let snapshot = try #require(board(value))
        #expect(snapshot.kind == .pointCount)
        #expect(snapshot.primary == BySide(a: "2", b: "1"))
        #expect(snapshot.games == nil, "no games or sets in this mode")
        #expect(snapshot.detail == "13 to play")
    }

    @Test func reachingTheTargetIsCalledOutLoud() throws {
        var value = log(target: 4)
        score(&value, [.a, .a, .b])
        let before = try #require(board(value))

        score(&value, [.a])
        let after = try #require(board(value))

        #expect(ScoreCaller.call(from: before, to: after)?.phrases == ["3, 1", "Game to Blue"])
    }

    @Test func aDrawIsCalledAllSquare() throws {
        var value = log(target: 2)
        score(&value, [.a])
        let before = try #require(board(value))

        score(&value, [.b])
        let after = try #require(board(value))

        #expect(ScoreCaller.call(from: before, to: after)?.phrases == ["1 all", "Finished, all square"])
    }

    @Test func aPresetMintsTheSameRules() {
        let configuration = PresetConfiguration.pointCount(
            rules: PointCountRules(target: 21, targetKind: .firstToTarget),
            teams: BySide(a: .home, b: .away)
        )
        guard case .pointCount(let rules, let teams) = configuration.makeSetup() else {
            Issue.record("expected a point-count setup")
            return
        }
        #expect(rules.target == 21)
        #expect(teams.a.name == "Us")
        #expect(configuration.drawsRounds == false, "there is only the one round")
    }
}
