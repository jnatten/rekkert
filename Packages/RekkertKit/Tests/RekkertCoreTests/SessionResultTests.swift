import Foundation
import Testing
@testable import RekkertCore

private let teams = BySide(a: TeamInfo(name: "Blue"), b: TeamInfo(name: "Orange"))

/// A friendly with `rounds` rounds already played, each won by whichever side `winner` names,
/// six games to two. Round `stopped`, if given, is called off at 3–2 instead.
private func friendly(rounds: Int, winner: (Int) -> TeamSide = { _ in .a }, stopped: Int? = nil) throws -> FriendlySession {
    var session = FriendlySession(
        id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!),
        name: "Thursday",
        rules: TraditionalRules(setsToWin: 1),
        players: (0 ..< 4).map { Player(name: "P\($0)") }
    )
    let engine = session.engine
    for index in 0 ..< rounds {
        session = try FriendlyScheduler.appendingRound(to: session)
        let side = winner(index)
        if index == stopped {
            session.rounds[index].score = engine.winGames(3, for: side, from: session.rounds[index].score)
            session.rounds[index].score = engine.winGames(2, for: side.other, from: session.rounds[index].score)
            session.rounds[index].isStopped = true
        } else {
            session.rounds[index].score = engine.winGames(2, for: side.other, from: session.rounds[index].score)
            session.rounds[index].score = engine.winGames(6, for: side, from: session.rounds[index].score)
        }
    }
    return session
}

@Suite("Session results")
struct SessionResultTests {
    @Test func eachModeNamesItself() throws {
        let match = SessionState.traditional(TraditionalSession(rules: TraditionalRules(), teams: teams))
        #expect(match.modeName == "Match")

        let points = SessionState.pointCount(PointCountSession(rules: PointCountRules(), teams: teams))
        #expect(points.modeName == "Points")

        let court = SessionState.winnerCourt(WinnerCourtSession(rules: WinnerCourtRules(), teams: teams))
        #expect(court.modeName == "Winner court")

        let mixer = SessionState.friendly(FriendlySession(
            players: (0 ..< 4).map { Player(name: "P\($0)") }
        ))
        #expect(mixer.modeName == "Friendly")

        for format in TournamentFormat.allCases {
            let tournament = SessionState.tournament(Tournament(
                name: "Thursday", format: format,
                players: (0 ..< 4).map { Player(name: "P\($0)") },
                config: TournamentConfig()
            ))
            #expect(tournament.modeName == format.displayName, "named by its format, not \"tournament\"")
        }
    }

    @Test func aWonMatchNamesTheWinnerAndTheSets() {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams)
        let engine = session.engine
        session.score = engine.winGames(6, for: .a, from: session.score)
        session.score = engine.winGames(4, for: .b, from: session.score)
        session.score = engine.winGames(6, for: .a, from: session.score)

        let result = SessionResult.make(from: .traditional(session))
        #expect(result.headline == "Blue win")
        #expect(result.score == "6–0  6–4")
        #expect(result.detail == "2 sets to 0")
        #expect(result.winningSide == .a)
        #expect(result.outcome == .won)
    }

    @Test func aMatchStoppedPartWayShowsTheSetInProgress() {
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams, isStopped: true)
        session.score = session.engine.winGames(3, for: .a, from: session.score)
        session.score = session.engine.winGames(1, for: .b, from: session.score)

        let result = SessionResult.make(from: .traditional(session))
        #expect(result.headline == "Match stopped")
        #expect(result.score == "3–1", "the unfinished set still counts as played")
        #expect(result.winningSide == nil)
        #expect(result.outcome == .stopped)
    }

    @Test func aStoppedMatchWithNothingPlayedSaysSo() {
        let session = TraditionalSession(rules: TraditionalRules(), teams: teams, isStopped: true)
        let result = SessionResult.make(from: .traditional(session))
        #expect(result.detail == "Nothing was played")
    }

    @Test func aCountedRoundReportsTheMargin() {
        var session = PointCountSession(rules: PointCountRules(target: 16), teams: teams)
        session.score.points = BySide(a: 9, b: 7)

        let result = SessionResult.make(from: .pointCount(session))
        #expect(result.headline == "Blue win")
        #expect(result.score == "9–7")
        #expect(result.detail == "by 2")
    }

    @Test func aLevelCountedRoundIsADraw() {
        var session = PointCountSession(rules: PointCountRules(target: 16), teams: teams)
        session.score.points = BySide(a: 8, b: 8)

        let result = SessionResult.make(from: .pointCount(session))
        #expect(result.headline == "All square")
        #expect(result.winningSide == nil)
        #expect(result.outcome == .drawn)
    }

    @Test func winnerCourtCountsRoundsAndGames() {
        var session = WinnerCourtSession(rules: WinnerCourtRules(), teams: teams, isFinished: true)
        let engine = session.engine
        for winner in [TeamSide.a, .a, .b] {
            session.score = engine.winGames(4, for: winner, from: session.score)
            session.score = engine.winGames(2, for: winner.other, from: session.score)
            session.score = engine.endingRound(session.score)
        }

        let result = SessionResult.make(from: .winnerCourt(session))
        #expect(result.headline == "Blue win")
        #expect(result.score == "2–1")
        #expect(result.detail == "3 rounds · games 10–8")
    }

    @Test func aTournamentRanksEveryone() throws {
        var tournament = try TournamentEngine.appendingRound(to: Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        ))
        tournament.rounds[0].matches[0].state.points = BySide(a: 11, b: 5)
        tournament.isFinished = true

        let result = SessionResult.make(from: .tournament(tournament))
        #expect(result.placings.count == 4)
        #expect(result.placings.first?.rank == 1)
        #expect(result.placings.first?.value == "11")
        #expect(result.detail == "1 round · 4 players")
        #expect(result.winningSide == nil, "a tournament has no team colour to celebrate")
        #expect(result.outcome == .drawn, "after one round the winning pair share the top score")
    }

    @Test func aClearLeaderWinsTheTournament() throws {
        // The draw is seeded from the tournament's id, so it has to be pinned for the
        // pairings to be the same on every run.
        var tournament = Tournament(
            id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!),
            name: "Thursday", format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        )
        // Two rounds, because partners change between them — one round can only ever end
        // with the winning pair level at the top.
        for round in 0 ..< 2 {
            tournament = try TournamentEngine.appendingRound(to: tournament)
            tournament.rounds[round].matches[0].state.points = BySide(a: 16, b: 0)
        }
        tournament.isFinished = true

        let result = SessionResult.make(from: .tournament(tournament))
        #expect(result.outcome == .won)
        #expect(result.headline == "P1 wins", "the only player on the winning side twice")
        #expect(result.score == "32")
    }

    @Test func aSharedTopScoreIsCalledATie() throws {
        var tournament = try TournamentEngine.appendingRound(to: Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        ))
        tournament.rounds[0].matches[0].state.points = BySide(a: 8, b: 8)
        tournament.isFinished = true

        let result = SessionResult.make(from: .tournament(tournament))
        #expect(result.headline.hasSuffix("tie"), "four players all on eight")
    }

    @Test func aCancelledRoundIsLeftOutOfTheSummary() throws {
        var tournament = Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 5).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        )
        for round in 0 ..< 2 {
            tournament = try TournamentEngine.appendingRound(to: tournament)
            tournament.rounds[round].matches[0].state.points = BySide(a: 10, b: 6)
        }
        tournament.rounds[1].isCancelled = true
        tournament.isFinished = true

        let result = SessionResult.make(from: .tournament(tournament))
        #expect(result.detail == "1 round · 5 players")
        #expect(result.score == "10")
    }

    @Test func aTournamentWhoseOnlyRoundWasCancelledHasNothingToKeep() throws {
        var tournament = try TournamentEngine.appendingRound(to: Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 5).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        ))
        tournament.rounds[0].matches[0].state.points = BySide(a: 3, b: 2)
        #expect(SessionState.tournament(tournament).hasResults)

        tournament.rounds[0].isCancelled = true
        #expect(!SessionState.tournament(tournament).hasResults)
    }

    // MARK: - Friendly

    @Test func aFriendlySummaryListsEveryRound() throws {
        let session = try friendly(rounds: 3)
        let result = SessionResult.make(from: .friendly(session))

        #expect(result.rounds.map(\.title) == ["Round 1", "Round 2", "Round 3"])
        #expect(result.rounds.allSatisfy { $0.score == "2–6" || $0.score == "6–2" })
        #expect(result.rounds.allSatisfy { $0.winner != nil })
        #expect(result.rounds.allSatisfy { $0.sitOuts == nil }, "four players, nobody out")
        #expect(result.rounds[0].teams.a.contains(" & "), "partnerships, not people")
    }

    @Test func aFriendlySummaryRanksThePlayers() throws {
        let session = try friendly(rounds: 3)
        let result = SessionResult.make(from: .friendly(session))

        #expect(result.placings.count == 4)
        #expect(result.placings.map(\.rank) == [1, 2, 3, 4])
        #expect(result.headline.hasSuffix("wins") || result.headline.hasSuffix("tie"))
        #expect(result.detail == "3 rounds · 4 players")
        #expect(result.score == "2 of 3" || result.score == "3 of 3")
        #expect(result.winningSide == nil, "won by a person, not by a side")
        // Everybody plays every round with four of them, so the wins add up to the rounds.
        #expect(result.placings.compactMap { Int($0.value.prefix(1)) }.reduce(0, +) == 6,
                "two winners a round, three rounds")
        #expect(result.placings.allSatisfy { ($0.detail ?? "").hasSuffix("games") })
    }

    @Test func aRoundStoppedPartWayStillShowsWhatWasPlayed() throws {
        let session = try friendly(rounds: 2, stopped: 1)
        let result = SessionResult.make(from: .friendly(session))

        let line = try #require(result.rounds.last)
        #expect(line.isStopped)
        #expect(line.winner == nil, "stopped is not won")
        #expect(line.score == "3–2" || line.score == "2–3")
        #expect(result.outcome == .won, "the round that was played out still decides it")
    }

    @Test func aFriendlyWithNothingPlayedSaysSo() throws {
        let session = try friendly(rounds: 0)
        let drawn = try FriendlyScheduler.appendingRound(to: session)
        let result = SessionResult.make(from: .friendly(drawn))

        #expect(result.outcome == .stopped)
        #expect(result.headline == "Friendly stopped")
        #expect(result.detail == "Nothing was played")
        #expect(result.rounds.isEmpty, "a round merely drawn has nothing to report")
        #expect(result.placings.count == 4, "the table is still there, all zeroes")
    }

    @Test func aFriendlyWhereNoRoundWasWonCrownsNobody() throws {
        let session = try friendly(rounds: 1, stopped: 0)
        let result = SessionResult.make(from: .friendly(session))

        #expect(result.outcome == .stopped)
        #expect(result.detail == "1 round · 4 players · no round was won")
        #expect(result.rounds.count == 1)
    }

    @Test func roundLinesAreEmptyForEveryOtherMode() {
        let match = SessionState.traditional(TraditionalSession(rules: TraditionalRules(), teams: teams))
        let points = SessionState.pointCount(PointCountSession(rules: PointCountRules(), teams: teams))
        let court = SessionState.winnerCourt(WinnerCourtSession(rules: WinnerCourtRules(), teams: teams))
        let tournament = SessionState.tournament(Tournament(
            format: .americano, players: (0 ..< 4).map { Player(name: "P\($0)") }
        ))
        for state in [match, points, court, tournament] {
            #expect(SessionResult.make(from: state).rounds.isEmpty)
        }
    }
}
