import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "DDDDDDDD-0000-0000-0000-00000000000A")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)

private let teams = BySide(
    a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]),
    b: TeamInfo(name: "Them", players: ["Kim", "Sam"])
)

private func match(_ rules: TraditionalRules = TraditionalRules(), _ build: (TraditionalEngine) -> TraditionalState) -> SessionState {
    .traditional(TraditionalSession(rules: rules, teams: teams, score: build(TraditionalEngine(rules: rules)), startedAt: noon))
}

private func tournament(players: Int = 8, courts: Int = 2, name: (Int) -> String = { "P\($0)" }) -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "44444444-0000-0000-0000-000000000000")!)
    let tournament = Tournament(
        name: "Thursday",
        format: .americano,
        players: (0 ..< players).map { Player(name: name($0)) },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
    )
    log.append(.configure(.tournament(tournament), at: noon), from: phone)
    log.drawRound(from: phone, at: noon)
    return log
}

@Suite("The score on the Lock Screen")
struct LiveScoreTests {
    @Test func aMatchCarriesItsBoard() throws {
        let state = match { engine in
            engine.play([.a, .a, .a, .b], from: engine.winGames(2, for: .b, from: engine.winGames(6, for: .a, from: engine.initialState())))
        }
        let snapshot = try #require(ScoreboardSnapshot.make(from: state))
        let score = LiveScore.make(from: state, display: DisplayPreferences())

        #expect(score.kind == .traditional)
        #expect(score.title == "Us vs Them")
        #expect(score.detail == snapshot.detail)
        #expect(score.clockStart == noon)
        #expect(score.round == nil)
        #expect(score.leaders.isEmpty)
        #expect(score.result == nil)

        let board = try #require(score.boards.first)
        #expect(score.boards.count == 1)
        #expect(board.points == BySide(a: "40", b: "15"))
        #expect(board.games == BySide(a: 0, b: 2))
        #expect(board.sets.map(\.games) == [BySide(a: 6, b: 0)])
        #expect(board.serving == snapshot.serving)
        #expect(!board.isDone)
    }

    @Test func aGoldenPointIsMarked() throws {
        let state = match(TraditionalRules(deuceRule: .goldenPoint)) { $0.play(repeated([.a, .b], 3)) }
        let board = try #require(LiveScore.make(from: state, display: DisplayPreferences()).boards.first)
        #expect(board.isSuddenDeath)
        #expect(board.points == BySide(a: "40", b: "40"))
    }

    @Test func theLeftSideFollowsThePhonesOwnBoard() {
        let start = match { $0.initialState() }
        let changed = match(TraditionalRules(changeEnds: .oddGames)) { $0.winGames(1, for: .a, from: $0.initialState()) }
        let mirrored = DisplayPreferences(isMirrored: true)

        #expect(LiveScore.make(from: start, display: DisplayPreferences()).leftSide == .a)
        #expect(LiveScore.make(from: start, display: mirrored).leftSide == .b)
        #expect(LiveScore.make(from: changed, display: DisplayPreferences()).leftSide == .b)
        #expect(LiveScore.make(from: changed, display: mirrored).leftSide == .a, "a flip and a changeover cancel out")
    }

    @Test func swappedColoursTravel() {
        let score = LiveScore.make(from: match { $0.initialState() }, display: DisplayPreferences(areColorsSwapped: true))
        #expect(score.colorsSwapped)
    }

    @Test func aTournamentShowsEveryCourtOfTheRound() throws {
        var log = tournament()
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 16, b: 0)), from: phone)
        let state = try #require(SessionReducer.state(of: log))
        guard case .tournament(let tournament) = state else { Issue.record("not a tournament"); return }
        let score = LiveScore.make(from: state, display: DisplayPreferences())

        #expect(score.kind == .tournament)
        #expect(score.title == "Thursday")
        #expect(score.round == 1)
        #expect(score.detail == "Round 1")
        #expect(score.clockStart == noon, "the round is live while a court still is")
        #expect(score.boards.map(\.label) == ["Court 1", "Court 2"])
        #expect(score.boards.map(\.isDone) == [true, false])
        #expect(score.boards[0].points == BySide(a: "16", b: "0"))
        #expect(score.leaders == Leaderboard.standings(for: tournament).prefix(3).map {
            LiveScore.Leader(name: $0.player.name, total: $0.total)
        })
        #expect(score.leaders.first?.total == 16)
    }

    @Test func aTournamentWithNoRoundSaysSo() throws {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(format: .mexicano, players: (0 ..< 4).map { Player(name: "P\($0)") })), at: noon), from: phone)
        let score = LiveScore.make(from: try #require(SessionReducer.state(of: log)), display: DisplayPreferences())

        #expect(score.boards.isEmpty)
        #expect(score.round == nil)
        #expect(score.detail == "Waiting for the first round")
    }

    @Test func theFinalUpdateCarriesTheResult() {
        let state = match(TraditionalRules(setsToWin: 1)) { $0.winGames(6, for: .a, from: $0.initialState()) }
        let result = SessionResult.make(from: state)
        let score = LiveScore.final(from: state, display: DisplayPreferences())

        #expect(score.isOver)
        #expect(score.result == "\(result.headline) · \(result.score)")
        #expect(score.clockStart == nil)
        #expect(score.boards.first?.winner == .a)
        #expect(!LiveScore.make(from: state, display: DisplayPreferences()).isOver)
    }

    @Test func itSurvivesTheTripToTheExtension() throws {
        let state = match { $0.play([.a, .b, .b], from: $0.winGames(3, for: .a, from: $0.initialState())) }
        let score = LiveScore.make(from: state, display: DisplayPreferences(isMirrored: true, areColorsSwapped: true))
        let decoded = try JSONDecoder().decode(LiveScore.self, from: JSONEncoder().encode(score))
        #expect(decoded == score)
    }

    @Test func aBigAmericanoFitsInsideTheLimit() throws {
        let log = tournament(players: 32, courts: 8) { "Kristoffersen-Haugland \($0)" }
        let score = LiveScore.make(from: try #require(SessionReducer.state(of: log)), display: DisplayPreferences())

        #expect(score.boards.count == 8)
        #expect(try JSONEncoder().encode(score).count < 4096, "ActivityKit refuses content over 4 KB")
    }
}
