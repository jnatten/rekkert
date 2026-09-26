import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "DDDDDDDD-0000-0000-0000-00000000000B")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)

private let teams = BySide(
    a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]),
    b: TeamInfo(name: "Them", players: ["Kim", "Sam"])
)

private func match(
    _ rules: TraditionalRules = TraditionalRules(),
    teams: BySide<TeamInfo> = teams,
    _ build: (TraditionalEngine) -> TraditionalState
) -> SessionState {
    .traditional(TraditionalSession(rules: rules, teams: teams, score: build(TraditionalEngine(rules: rules)), startedAt: noon))
}

private func board(_ state: SessionState?, lastResult: SessionState? = nil, display: DisplayPreferences = DisplayPreferences()) -> TVBoard {
    TVBoard.make(from: state, lastResult: lastResult, display: display)
}

private func tournament(players: Int = 8, courts: Int = 2) -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "55555555-0000-0000-0000-000000000000")!)
    let tournament = Tournament(
        name: "Thursday",
        format: .americano,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
    )
    log.append(.configure(.tournament(tournament), at: noon), from: phone)
    log.drawRound(from: phone, at: noon)
    return log
}

private func friendly(players: Int = 5, draw: Bool = true) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.friendly(FriendlySession(
        id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!),
        name: "Thursday",
        rules: TraditionalRules(setsToWin: 1, gamesPerSet: 6),
        players: (0 ..< players).map { Player(name: "P\($0)") }
    )), at: noon), from: phone)
    if draw { log.drawFriendlyRound(from: phone, at: noon) }
    return log
}

private func court(_ board: TVBoard) -> TVBoard.Court? {
    guard case .match(let court) = board.content else { return nil }
    return court
}

private func courts(_ board: TVBoard) -> [TVBoard.Court] {
    guard case .courts(let courts) = board.content else { return [] }
    return courts
}

@Suite("The board on a TV")
struct TVBoardTests {
    @Test func nothingOnIsIdle() {
        #expect(board(nil) == .idle)
    }

    @Test func aMatchNamesEveryPlayerAndMarksTheServer() throws {
        let state = match { $0.initialState() }
        let snapshot = try #require(ScoreboardSnapshot.make(from: state))
        let value = board(state)
        let court = try #require(court(value))

        #expect(value.title == "Us vs Them")
        #expect(value.mode == "Match")
        #expect(value.detail == "Set 1")
        #expect(value.clockStart == noon)
        #expect(court.sides.a.name == "Us")
        #expect(court.sides.a.players.map(\.name) == ["Jonas", "Ada"])
        #expect(court.sides.b.players.map(\.name) == ["Kim", "Sam"])

        let serving = try #require(snapshot.serving)
        #expect(court.sides[serving].isServing)
        #expect(!court.sides[serving.other].isServing)
        #expect(court.sides[serving].players.filter(\.isServing).map(\.name) == [snapshot.servingPlayer])
        #expect(court.sides[serving.other].players.allSatisfy { !$0.isServing })
    }

    @Test func aBlankSlotIsNobody() throws {
        let unnamed = BySide(a: TeamInfo(name: "Us", players: ["", "Ada"]), b: TeamInfo(name: "Them"))
        let court = try #require(court(board(match(teams: unnamed) { $0.initialState() })))

        #expect(court.sides.a.players.map(\.name) == ["Ada"])
        #expect(court.sides.b.players.isEmpty)
        #expect(court.sides.b.name == "Them")
    }

    @Test func theSetsStripReadsTheWayTheMatchWent() throws {
        let state = match { engine in
            engine.play([.a, .a, .a, .b], from: engine.winGames(2, for: .b, from: engine.winGames(6, for: .a, from: engine.initialState())))
        }
        let court = try #require(court(board(state)))

        #expect(court.sides.a.sets == [6])
        #expect(court.sides.b.sets == [0])
        #expect(court.sides.a.games == 0)
        #expect(court.sides.b.games == 2)
        #expect(court.sides.a.points == "40")
        #expect(court.sides.b.points == "15")
        #expect(!court.isDone)
    }

    @Test func theLeftSideFollowsThePhonesOwnBoard() {
        let start = match { $0.initialState() }
        let changed = match(TraditionalRules(changeEnds: .oddGames)) { $0.winGames(1, for: .a, from: $0.initialState()) }
        let mirrored = DisplayPreferences(isMirrored: true)

        #expect(board(start).leftSide == .a)
        #expect(board(start, display: mirrored).leftSide == .b)
        #expect(board(changed).leftSide == .b)
        #expect(board(changed, display: mirrored).leftSide == .a, "a flip and a changeover cancel out")
    }

    @Test func pointsHaveNoGames() throws {
        var log = MatchLog()
        log.append(.configure(.pointCount(rules: PointCountRules(target: 16), teams: teams), at: noon), from: phone)
        log.append(.point(round: 0, court: 0, team: .a), from: phone)
        let value = board(try #require(SessionReducer.state(of: log)))
        let court = try #require(court(value))

        #expect(value.mode == "Points")
        #expect(value.detail == "15 to play")
        #expect(court.sides.a.points == "1")
        #expect(court.sides.a.games == nil)
        #expect(court.sides.a.sets.isEmpty)
    }

    @Test func aWinnerCourtCountsRoundsWon() throws {
        var log = MatchLog()
        log.append(.configure(.winnerCourt(rules: WinnerCourtRules(), teams: teams), at: noon), from: phone)
        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .b), from: phone) }
        log.blowWhistle(from: phone, at: noon)
        let court = try #require(court(board(try #require(SessionReducer.state(of: log)))))

        #expect(court.sides.a.roundsWon == 0)
        #expect(court.sides.b.roundsWon == 1)
        #expect(court.sides.b.sets.isEmpty, "the rounds are counted, not listed")
        #expect(court.sides.b.games == 0)
    }

    @Test func aFinishedMatchShowsTheSetsAsItsScore() throws {
        let single = try #require(court(board(match(TraditionalRules(setsToWin: 1)) { engine in
            engine.winGames(6, for: .a, from: engine.winGames(3, for: .b, from: engine.initialState()))
        })))
        #expect(single.isDone)
        #expect(single.sides.a.points == "6")
        #expect(single.sides.b.points == "3")
        #expect(single.sides.a.sets.isEmpty)
        #expect(single.sides.a.games == nil)

        let three = try #require(court(board(match { engine in
            let first = engine.winGames(6, for: .a, from: engine.initialState())
            let second = engine.winGames(6, for: .b, from: first)
            return engine.winGames(6, for: .a, from: second)
        })))
        #expect(three.sides.a.points == "2")
        #expect(three.sides.b.points == "1")
        #expect(three.sides.a.sets == [6, 0, 6])
        #expect(three.sides.b.sets == [0, 6, 0])
    }

    @Test func aFriendlyNamesItsPlayersOnce() throws {
        let log = friendly()
        let state = try #require(SessionReducer.state(of: log))
        guard case .friendly(let session) = state, let round = session.currentRound else {
            Issue.record("not a friendly"); return
        }
        let value = board(state)
        let court = try #require(court(value))

        #expect(value.mode == "Friendly")
        #expect(value.detail == "Round 1")
        #expect(court.sides.a.name == nil)
        #expect(court.sides.a.players.map(\.name) == round.teams.a.map(session.name))
        #expect(value.sittingOut == session.sitOutNames(in: round))
        #expect(value.sittingOut.count == 1)
        #expect(value.standings.count == 5)
        #expect(value.upNext == nil)
    }

    @Test func betweenFriendlyRoundsTheNextDrawIsUpNext() throws {
        var log = friendly()
        for _ in 0 ..< 24 { log.append(.point(round: 0, court: 0, team: .a), from: phone) }
        let state = try #require(SessionReducer.state(of: log))
        guard case .friendly(let session) = state else { Issue.record("not a friendly"); return }
        let next = try #require(session.nextDraw())
        let value = board(state)

        #expect(court(value)?.isDone == true)
        #expect(court(value)?.sides.a.isWinner == true)
        #expect(court(value)?.sides.a.points == "6")
        #expect(court(value)?.sides.b.points == "0")
        #expect(value.upNext == TVBoard.UpNext(teams: session.teamNames(in: next), sittingOut: session.sitOutNames(in: next)))
    }

    @Test func aFriendlyWithNothingDrawnIsWaiting() throws {
        let value = board(try #require(SessionReducer.state(of: friendly(draw: false))))
        #expect(value.content == .waiting)
        #expect(value.standings.count == 5)
    }

    @Test func aTournamentShowsEveryCourtOfTheRound() throws {
        var log = tournament()
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 16, b: 0)), from: phone)
        let state = try #require(SessionReducer.state(of: log))
        guard case .tournament(let tournament) = state else { Issue.record("not a tournament"); return }
        let value = board(state)
        let shown = courts(value)

        #expect(value.title == "Thursday")
        #expect(value.mode == "Americano")
        #expect(value.detail == "Round 1")
        #expect(value.clockStart == noon, "the round is live while a court still is")
        #expect(shown.map(\.label) == ["Court 1", "Court 2"])
        #expect(shown.map(\.isDone) == [true, false])
        #expect(shown.map(\.status) == [nil, "16 to play"])
        #expect(shown[0].sides.a.isWinner)
        #expect(shown[0].sides.a.points == "16")

        let match = try #require(tournament.currentRound?.matches.first { $0.courtIndex == 1 })
        #expect(shown[1].sides.a.name == nil)
        #expect(shown[1].sides.a.players.map(\.name) == match.teams.a.compactMap { tournament.player($0)?.name })
        #expect(shown[1].sides.a.players.count == 2)

        #expect(value.standings.count == 8)
        #expect(value.standings.first?.value == "16")
        #expect(value.standings.first?.detail == "+16")
        #expect(value.standings.last?.detail == "-16")
        #expect(value.sittingOut.isEmpty)
    }

    @Test func theBenchIsNamed() throws {
        let state = try #require(SessionReducer.state(of: tournament(players: 9)))
        guard case .tournament(let tournament) = state, let round = tournament.currentRound else {
            Issue.record("not a tournament"); return
        }
        let value = board(state)

        #expect(value.sittingOut.count == 1)
        #expect(value.sittingOut == round.sitOuts.compactMap { tournament.player($0)?.name })
    }

    @Test func aTournamentWithNoRoundIsWaiting() throws {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(format: .mexicano, players: (0 ..< 4).map { Player(name: "P\($0)") })), at: noon), from: phone)
        let value = board(try #require(SessionReducer.state(of: log)))

        #expect(value.content == .waiting)
        #expect(value.detail == "Waiting for the first round")
        #expect(value.standings.count == 4)
    }

    @Test func aBigAmericanoHasEveryCourt() throws {
        let value = board(try #require(SessionReducer.state(of: tournament(players: 32, courts: 8))))

        #expect(courts(value).map(\.id) == Array(0 ..< 8))
        #expect(value.standings.count == 32)
    }

    @Test func aFinishedSessionShowsItsResult() {
        let state = match(TraditionalRules(setsToWin: 1)) { $0.winGames(6, for: .a, from: $0.initialState()) }
        let value = board(nil, lastResult: state)

        #expect(value.content == .result(SessionResult.make(from: state)))
        #expect(value.title == "Us vs Them")
        #expect(value.clockStart == nil)
    }

    @Test func aLiveSessionOutranksTheLastResult() {
        let finished = match(TraditionalRules(setsToWin: 1)) { $0.winGames(6, for: .a, from: $0.initialState()) }
        let value = board(match { $0.initialState() }, lastResult: finished)
        #expect(court(value) != nil)
    }
}
