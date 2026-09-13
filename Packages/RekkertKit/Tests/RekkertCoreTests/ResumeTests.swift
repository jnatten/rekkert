import Foundation
import Testing
@testable import RekkertCore

private let teams = BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange"))

@Suite("Resuming an archived session")
struct ResumeTests {
    @Test func aMatchPlayedToItsEndCannotBeResumed() {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams)
        let engine = session.engine
        session.score = engine.winGames(6, for: .a, from: session.score)
        session.score = engine.winGames(6, for: .a, from: session.score)

        #expect(session.score.winner == .a, "somebody won it")
        #expect(SessionState.traditional(session).canResume == false)
        #expect(SessionState.traditional(session).resumed() == nil)
    }

    @Test func aStoppedMatchComesBackWithItsScore() throws {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams, isStopped: true)
        session.score = session.engine.winGames(3, for: .a, from: session.score)

        let state = SessionState.traditional(session)
        #expect(state.canResume)

        guard case .traditional(let resumed)? = state.resumed() else {
            Issue.record("expected a traditional session")
            return
        }
        #expect(resumed.isStopped == false, "it is in play again")
        #expect(resumed.score.games == BySide(a: 3, b: 0), "with the games it had")
        #expect(SessionState.traditional(resumed).isFinished == false)
    }

    @Test func aFinishedTournamentCanAlwaysBeCarriedOn() throws {
        var tournament = try TournamentEngine.appendingRound(to: Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        ))
        tournament.rounds[0].matches[0].state.points = BySide(a: 9, b: 7)
        tournament.isFinished = true

        let state = SessionState.tournament(tournament)
        #expect(state.canResume, "there is always another round to draw")

        guard case .tournament(let resumed)? = state.resumed() else {
            Issue.record("expected a tournament")
            return
        }
        #expect(resumed.isFinished == false)
        #expect(resumed.rounds.count == 1, "with the round it had played")
        #expect(resumed.rounds[0].matches[0].state.points == BySide(a: 9, b: 7))
    }

    @Test func aCountedRoundThatReachedItsTargetIsDone() {
        var session = PointCountSession(rules: PointCountRules(target: 16), teams: teams)
        session.score.points = BySide(a: 9, b: 7)
        #expect(SessionState.pointCount(session).canResume == false)
    }

    @Test func aCountedRoundStoppedShortCanGoOn() throws {
        var session = PointCountSession(rules: PointCountRules(target: 16), teams: teams, isStopped: true)
        session.score.points = BySide(a: 5, b: 3)

        guard case .pointCount(let resumed)? = SessionState.pointCount(session).resumed() else {
            Issue.record("expected a point-count session")
            return
        }
        #expect(resumed.isStopped == false)
        #expect(resumed.score.points == BySide(a: 5, b: 3))
    }

    @Test func winnerCourtCanAlwaysGoOn() {
        var session = WinnerCourtSession(rules: WinnerCourtRules(), teams: teams, isFinished: true)
        session.score = session.engine.winGames(2, for: .a, from: session.score)
        #expect(SessionState.winnerCourt(session).canResume, "the rounds never run out")
    }

    @Test func restoringRebuildsTheSessionFromOneEvent() throws {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams)
        session.score = session.engine.winGames(4, for: .a, from: session.score)
        session.score = session.engine.winGames(2, for: .b, from: session.score)

        var log = MatchLog()
        log.append(.restore(.traditional(session)), from: DeviceID())

        guard case .traditional(let rebuilt)? = SessionReducer.state(of: log) else {
            Issue.record("expected a traditional session")
            return
        }
        #expect(rebuilt.score.games == BySide(a: 4, b: 2))
    }

    @Test func scoringCarriesOnFromWhereARestoreLeftOff() throws {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams)
        session.score = session.engine.winGames(4, for: .a, from: session.score)

        let device = DeviceID()
        var log = MatchLog()
        log.append(.restore(.traditional(session)), from: device)
        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }

        guard case .traditional(let rebuilt)? = SessionReducer.state(of: log) else {
            Issue.record("expected a traditional session")
            return
        }
        #expect(rebuilt.score.games == BySide(a: 5, b: 0), "a fifth game, on top of the four it came back with")
    }

    @Test func aRestoreIsNotSomethingUndoCanTakeBack() {
        var log = MatchLog()
        log.append(.restore(.traditional(TraditionalSession(rules: TraditionalRules(), teams: teams))), from: DeviceID())
        #expect(log.lastUndoableEvent() == nil, "undo means taking back a score, not the session itself")
    }
}
