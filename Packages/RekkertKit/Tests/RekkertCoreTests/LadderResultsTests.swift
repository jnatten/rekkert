import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000EE")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)

private func playedLog() -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "55555555-0000-0000-0000-0000000000EE")!)
    log.append(.configure(.tournament(makeLadder(players: 8, courts: 2)), at: noon), from: phone)
    log.drawRound(from: phone, at: noon)
    score(&log, court: 0, repeated([.b], 8))
    score(&log, court: 1, repeated([.a], 4))
    return log
}

@Suite("Winner court ladder: everywhere it shows")
struct LadderResultsTests {
    @Test func theTVShowsEveryCourtInGamesWithTheCountdown() throws {
        let board = TVBoard.make(from: SessionReducer.state(of: playedLog()), lastResult: nil, display: DisplayPreferences())
        guard case .courts(let courts) = board.content else { Issue.record("courts"); return }
        #expect(courts.map { $0.sides.b.games } == [2, 0])
        #expect(courts.allSatisfy { $0.status == nil }, "nothing to count down to on a court")
        #expect(board.countdown?.endsAt == noon.addingTimeInterval(12 * 60))
    }

    @Test func theTVSaysWhichCourtsArePlayingADecidingPoint() throws {
        var log = playedLog()
        score(&log, court: 1, repeated([.b], 4))
        log.blowWhistle(from: phone)
        let board = TVBoard.make(from: SessionReducer.state(of: log), lastResult: nil, display: DisplayPreferences())
        guard case .courts(let courts) = board.content else { Issue.record("courts"); return }
        #expect(courts.map(\.status) == [nil, "Deciding point"])
        #expect(board.countdown == nil)
    }

    @Test func theTableCountsRoundsWon() throws {
        var log = playedLog()
        log.blowWhistle(from: phone)
        let board = TVBoard.make(from: SessionReducer.state(of: log), lastResult: nil, display: DisplayPreferences())
        #expect(board.standings.prefix(2).map(\.name) == ["P2", "P3"])
        #expect(board.standings.first?.value == "1")
    }

    @Test func theLockScreenCarriesTheCountdownAndTheLeaders() throws {
        var log = playedLog()
        log.blowWhistle(from: phone)
        log.drawRound(from: phone, at: noon.addingTimeInterval(13 * 60))
        let score = LiveScore.make(from: try #require(SessionReducer.state(of: log)), display: DisplayPreferences())
        #expect(score.countdown?.endsAt == noon.addingTimeInterval(25 * 60))
        #expect(score.leaders.map(\.total) == [1, 1, 1])
        #expect(score.boards.allSatisfy { $0.games == BySide(a: 0, b: 0) })
    }

    @Test func aBigLadderFitsInsideTheLimit() throws {
        var tournament = makeLadder(players: 32, courts: 8)
        tournament.players = tournament.players.enumerated().map { Player(id: $1.id, name: "Kristoffersen-Haugland \($0)") }
        var log = MatchLog()
        log.append(.configure(.tournament(tournament), at: noon), from: phone)
        log.drawRound(from: phone, at: noon)
        for court in 0 ..< 8 { score(&log, court: court, repeated([.a, .b], 9)) }
        let live = LiveScore.make(from: try #require(SessionReducer.state(of: log)), display: DisplayPreferences())
        #expect(try JSONEncoder().encode(live).count < 4096, "ActivityKit refuses content over 4 KB")
    }

    @Test func theResultNamesCourtOnesWinners() throws {
        var log = playedLog()
        log.blowWhistle(from: phone)
        let result = SessionResult.make(from: try #require(SessionReducer.state(of: log)))
        #expect(result.headline == "P2 & P3 win")
        #expect(result.score == "2–0")
        #expect(result.placings.map(\.name).prefix(4) == ["P2", "P3", "P0", "P1"])
        #expect(result.detail == "1 round · 8 players")
    }

    @Test func aLadderNobodyPlayedSaysSo() throws {
        var log = MatchLog()
        log.append(.configure(.tournament(makeLadder(players: 8, courts: 2))), from: phone)
        log.drawRound(from: phone)
        let result = SessionResult.make(from: try #require(SessionReducer.state(of: log)))
        #expect(result.outcome == .stopped)
        #expect(result.detail == "Nothing was played")
    }

    @Test func aLadderCourtCountsAsAGameWonWithoutPoints() throws {
        var log = playedLog()
        log.blowWhistle(from: phone)
        let state = try #require(SessionReducer.state(of: log))
        let stats = PlayerStats.make(from: [Filed.record(state, day: 0)], links: PlayerLinks())
        let p2 = try #require(stats.people.first { $0.name == "P2" })
        #expect(p2.overall.won == 1)
        #expect(p2.points.isEmpty, "games are not points")
        #expect(Set(p2.opponents.map(\.name)) == ["P0", "P1"], "the other side of the net is known on a ladder")
    }

    @Test func theTimelineReadsALadderCourtInGames() throws {
        let timeline = MatchTimeline.make(from: playedLog())
        let last = try #require(timeline.entries.last { $0.court == 0 })
        #expect(last.board.games == BySide(a: 0, b: 2))
        #expect(last.ended == .game(.b))
    }

    @Test func aPresetSaysHowLongARoundIs() {
        let timed = PresetConfiguration.tournament(
            format: .winnerCourt, name: "", players: (0 ..< 16).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 4, ladder: LadderRules())
        )
        #expect(timed.summary == "Winner court · 16 players · 4 courts · 12 min")
        #expect(timed.symbol == "arrow.up.arrow.down")
        #expect(GameMode(timed) == .winnerCourt)
    }
}
