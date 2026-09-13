import Foundation
import Testing
@testable import RekkertCore

private let teams = BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange"))

/// Plays points and hands back what would be said after each one. Team A serves the first
/// game, so a call reading "love, fifteen" means the receivers took the point.
private struct Umpire {
    private var session: TraditionalSession
    private var last: ScoreboardSnapshot

    init(_ rules: TraditionalRules = TraditionalRules()) {
        session = TraditionalSession(rules: rules, teams: teams)
        last = ScoreboardSnapshot.make(from: .traditional(session))!
    }

    @discardableResult
    mutating func point(_ side: TeamSide) -> ScoreCall? {
        session.score = session.engine.scoringPoint(side, in: session.score)
        return moved()
    }

    @discardableResult
    mutating func game(_ side: TeamSide) -> ScoreCall? {
        (0 ..< 4).reduce(nil) { _, _ in point(side) }
    }

    /// Puts the score back where it was two points ago, the way undo does.
    mutating func rewind(to earlier: ScoreboardSnapshot) -> ScoreCall? {
        let call = ScoreCaller.call(from: last, to: earlier)
        last = earlier
        return call
    }

    var scoreboard: ScoreboardSnapshot { last }

    private mutating func moved() -> ScoreCall? {
        let next = ScoreboardSnapshot.make(from: .traditional(session))!
        defer { last = next }
        return ScoreCaller.call(from: last, to: next)
    }
}

@Suite("Calling the score")
struct ScoreCallTests {
    @Test func theServersScoreComesFirst() {
        var umpire = Umpire()
        #expect(umpire.point(.b)?.phrases == ["Love, fifteen"])
        #expect(umpire.point(.a)?.phrases == ["Fifteen all"])
        #expect(umpire.point(.a)?.phrases == ["Thirty, fifteen"])
    }

    @Test func levelScoresAreCalledAll() {
        var umpire = Umpire()
        umpire.point(.a)
        #expect(umpire.point(.b)?.phrases == ["Fifteen all"])
        umpire.point(.a)
        #expect(umpire.point(.b)?.phrases == ["Thirty all"])
    }

    @Test func fortyAllIsDeuce() {
        var umpire = Umpire()
        for _ in 0 ..< 2 { umpire.point(.a); umpire.point(.b) }
        umpire.point(.a)
        #expect(umpire.point(.b)?.phrases == ["Deuce"])
    }

    @Test func theAdvantageIsNamed() {
        var umpire = Umpire()
        for _ in 0 ..< 3 { umpire.point(.a); umpire.point(.b) }
        #expect(umpire.point(.b)?.phrases == ["Advantage Orange"])
        #expect(umpire.point(.a)?.phrases == ["Deuce"])
        #expect(umpire.point(.a)?.phrases == ["Advantage Blue"])
    }

    @Test func aDecidingPointIsFlagged() {
        var umpire = Umpire(TraditionalRules(deuceRule: .goldenPoint))
        for _ in 0 ..< 2 { umpire.point(.a); umpire.point(.b) }
        umpire.point(.a)
        #expect(umpire.point(.b)?.phrases == ["Deuce", "Sudden death"])
    }

    @Test func aWonGameIsCalledWithTheGamesTally() {
        var umpire = Umpire()
        #expect(umpire.game(.a)?.phrases == ["Game, Blue", "1 game to 0, Blue"])
        #expect(umpire.game(.b)?.phrases == ["Game, Orange", "1 game all"])
        #expect(umpire.game(.b)?.phrases == ["Game, Orange", "2 games to 1, Orange"])
    }

    @Test func aWonGameSaysNothingAboutLoveAll() throws {
        var umpire = Umpire()
        let won = umpire.game(.a)
        let call = try #require(won)
        #expect(call.phrases.first == "Game, Blue", "the score is back to love-all, which nobody calls")
    }

    @Test func aWonSetIsCalledWithTheSetsTally() {
        var umpire = Umpire()
        for _ in 0 ..< 5 { umpire.game(.a) }
        #expect(umpire.game(.a)?.phrases == ["Game and set, Blue, 6 to 0", "1 set to 0, Blue"])
    }

    @Test func theLastPointOfTheMatchIsCalledAsSuch() {
        var umpire = Umpire()
        for _ in 0 ..< 11 { umpire.game(.a) }
        #expect(umpire.game(.a)?.phrases == ["Game, set and match, Blue"])
    }

    @Test func aTiebreakIsCalledInPlainNumbers() {
        var umpire = Umpire()
        for _ in 0 ..< 6 { umpire.game(.a); umpire.game(.b) }
        umpire.point(.a)
        #expect(umpire.point(.b)?.phrases == ["1 all"], "6-6 is a tiebreak, counted one by one")
    }

    @Test func undoingAGameDoesNotCallOneWon() throws {
        var umpire = Umpire()
        for _ in 0 ..< 3 { umpire.point(.a) }
        let atFortyLove = umpire.scoreboard
        umpire.point(.a)

        let undone = umpire.rewind(to: atFortyLove)
        let call = try #require(undone)
        #expect(call.phrases == ["Forty, love"], "just the score it went back to")
    }

    @Test func correctingTheServeSaysNothing() {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams)
        session.score = session.engine.scoringPoint(.a, in: session.score)
        let before = ScoreboardSnapshot.make(from: .traditional(session))!

        session.score.firstServerIndex = 1
        let after = ScoreboardSnapshot.make(from: .traditional(session))!

        #expect(before != after, "the scoreboard did change")
        #expect(ScoreCaller.call(from: before, to: after) == nil, "but the score did not")
    }

    @Test func theWhistleClosesARoundRatherThanASet() {
        var session = WinnerCourtSession(rules: WinnerCourtRules(), teams: teams)
        session.score = session.engine.winGames(3, for: .a, from: session.score)
        session.score = session.engine.winGames(1, for: .b, from: session.score)
        let before = ScoreboardSnapshot.make(from: .winnerCourt(session))!

        session.score = session.engine.endingRound(session.score)
        let after = ScoreboardSnapshot.make(from: .winnerCourt(session))!

        #expect(ScoreCaller.call(from: before, to: after)?.phrases == ["Round to Blue, 3 to 1"])
    }

    @Test func aLevelRoundIsCalledDrawn() {
        var session = WinnerCourtSession(rules: WinnerCourtRules(), teams: teams)
        session.score = session.engine.winGames(2, for: .a, from: session.score)
        session.score = session.engine.winGames(2, for: .b, from: session.score)
        let before = ScoreboardSnapshot.make(from: .winnerCourt(session))!

        session.score = session.engine.endingRound(session.score)
        let after = ScoreboardSnapshot.make(from: .winnerCourt(session))!

        #expect(ScoreCaller.call(from: before, to: after)?.phrases == ["Round drawn, 2 all"])
    }

    @Test func aCourtCountIsCalledAsNumbersAndThenFinished() throws {
        var tournament = try TournamentEngine.appendingRound(to: Tournament(
            name: "Test",
            format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        ))
        let empty = ScoreboardSnapshot.make(from: .tournament(tournament))!

        tournament.rounds[0].matches[0].state.points = BySide(a: 5, b: 5)
        let midway = ScoreboardSnapshot.make(from: .tournament(tournament))!
        #expect(ScoreCaller.call(from: empty, to: midway)?.phrases == ["5 all"])

        tournament.rounds[0].matches[0].state.points = BySide(a: 9, b: 7)
        let done = ScoreboardSnapshot.make(from: .tournament(tournament))!
        #expect(ScoreCaller.call(from: midway, to: done)?.phrases == ["9, 7", "Court 1 finished"])
    }

    @Test func theSpokenLineReadsAsSentences() {
        let call = ScoreCall(phrases: ["Game, Blue", "1 game to 0, Blue"])
        #expect(call.spoken == "Game, Blue. 1 game to 0, Blue.")
    }
}
