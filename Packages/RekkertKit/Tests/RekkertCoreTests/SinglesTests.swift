import Foundation
import Testing
@testable import RekkertCore

private let singles = BySide(a: TeamInfo.singles("Ada"), b: .singles("Bob"))

private func wonMatch(_ teams: BySide<TeamInfo> = singles) -> SessionState {
    var session = TraditionalSession(rules: TraditionalRules(setsToWin: 1), teams: teams)
    session.score = session.engine.winGames(6, for: .a, from: session.score)
    return .traditional(session)
}

@Suite("Singles in Match, Points and Winner court")
struct SinglesTests {
    // MARK: - Serve

    @Test func aMatchHasTheOnePlayerServeEveryGameTheirSideDoes() {
        var session = TraditionalSession(rules: TraditionalRules(), teams: singles)
        var servers: [String?] = []
        for _ in 0 ..< 4 {
            let board = ScoreboardSnapshot.make(from: .traditional(session))
            servers.append(board?.servingPlayer)
            #expect(board?.canSwapServingPlayer == false)
            session.score = session.engine.winGames(1, for: .a, from: session.score)
        }
        #expect(servers == ["Ada", "Bob", "Ada", "Bob"])
    }

    @Test func aPointsRoundDoesToo() {
        var session = PointCountSession(rules: PointCountRules(target: 16, servesPerTeam: 1), teams: singles)
        var servers: [String?] = []
        for _ in 0 ..< 4 {
            servers.append(ScoreboardSnapshot.make(from: .pointCount(session))?.servingPlayer)
            session.score = session.engine.play([.a], from: session.score)
        }
        #expect(servers == ["Ada", "Bob", "Ada", "Bob"])
    }

    @Test func aWinnerCourtDoesToo() {
        var session = WinnerCourtSession(rules: WinnerCourtRules(), teams: singles)
        var servers: [String?] = []
        for _ in 0 ..< 4 {
            servers.append(ScoreboardSnapshot.make(from: .winnerCourt(session))?.servingPlayer)
            session.score = session.engine.winGames(1, for: .a, from: session.score)
        }
        #expect(servers == ["Ada", "Bob", "Ada", "Bob"])
    }

    @Test func aDoublesSideWithOnlyOneNameStillHasAnUnnamedPartner() {
        let teams = BySide(a: TeamInfo(name: "Us", players: ["Ada"]), b: TeamInfo(name: "Them", players: ["Bob"]))
        var session = TraditionalSession(rules: TraditionalRules(), teams: teams)
        var servers: [String?] = []
        for _ in 0 ..< 4 {
            servers.append(ScoreboardSnapshot.make(from: .traditional(session))?.servingPlayer)
            session.score = session.engine.winGames(1, for: .a, from: session.score)
        }
        #expect(servers == ["Ada", "Bob", nil, nil])
    }

    // MARK: - Result

    @Test func aMatchIsListedAndWonByThePlayers() {
        let state = wonMatch()
        #expect(state.title == "Ada vs Bob")
        #expect(SessionResult.make(from: state).headline == "Ada wins")
    }

    @Test func aTeamStillWinsInThePlural() {
        let state = wonMatch(Filed.teams(["Jonas", "Ada"], ["Kim", "Sam"]))
        #expect(SessionResult.make(from: state).headline == "Us win")
    }

    @Test func aPointsRoundIsWonByThePlayerToo() {
        let state = SessionState.pointCount(PointCountSession(
            rules: PointCountRules(target: 16),
            teams: singles,
            score: PointCountState(points: BySide(a: 6, b: 10))
        ))
        #expect(SessionResult.make(from: state).headline == "Bob wins")
    }

    // MARK: - Players

    @Test func aSinglesMatchCountsTwoPeopleHeadToHead() throws {
        let stats = PlayerStats.make(from: [Filed.record(wonMatch(), day: 0)], links: PlayerLinks())

        #expect(stats.people.map(\.name).sorted() == ["Ada", "Bob"])
        let ada = try #require(stats.named("Ada"))
        #expect(ada.overall == Tally(won: 1))
        #expect(ada.partners.isEmpty)
        #expect(ada.opponents.map(\.name) == ["Bob"])
        #expect(stats.named("Bob")?.overall == Tally(lost: 1))
    }

    // MARK: - Renaming

    @Test func renamingASinglesSideMovesTheNameAndThePlayerTogether() throws {
        let renamed = wonMatch().renamed(.sides(event: "", teams: BySide(a: .singles("Ada K"), b: TeamInfo(name: "Bob"))))

        guard case .traditional(let after) = renamed else {
            Issue.record("still a match")
            return
        }
        #expect(after.teams.a == .singles("Ada K"))
        #expect(after.teams.b == .singles("Bob"), "a blank field leaves the side alone")
        #expect(renamed.title == "Ada K vs Bob")
    }

    // MARK: - TV

    @Test func theTVNamesThePlayerOnceAndLightsThemUpOnEveryServe() throws {
        var session = TraditionalSession(rules: TraditionalRules(), teams: singles)
        session.score = session.engine.winGames(2, for: .a, from: session.score)
        let board = TVBoard.make(from: .traditional(session), lastResult: nil, display: DisplayPreferences())

        guard case .match(let court) = board.content else {
            Issue.record("one court on the TV")
            return
        }
        #expect(court.sides.a.name == nil)
        #expect(court.sides.a.players.map(\.name) == ["Ada"])
        #expect(court.sides.a.players.first?.isServing == true, "the third game is Ada's second serve")
    }
}
