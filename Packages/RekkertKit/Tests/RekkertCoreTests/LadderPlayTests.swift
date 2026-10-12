import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000EE")!)
private let later = DeviceID(UUID(uuidString: "FFFFFFFF-0000-0000-0000-0000000000EE")!)

func ladderLog(players: Int = 8, courts: Int = 2, minutes: Int? = 12, rules: TraditionalRules? = nil) -> MatchLog {
    var tournament = makeLadder(players: players, courts: courts, minutes: minutes)
    if let rules { tournament.config.ladder?.rules = rules }
    var log = MatchLog(sessionID: UUID(uuidString: "33333333-0000-0000-0000-0000000000EE")!)
    log.append(.configure(.tournament(tournament)), from: device)
    log.drawRound(from: device)
    return log
}

func ladder(_ log: MatchLog) -> Tournament? {
    guard case .tournament(let value)? = SessionReducer.state(of: log) else { return nil }
    return value
}

func score(_ log: inout MatchLog, round: Int = 0, court: Int, _ sequence: [TeamSide], from author: DeviceID = device) {
    for team in sequence { log.append(.point(round: round, court: court, team: team), from: author) }
}

private func games(_ log: MatchLog, round: Int = 0, court: Int) -> TraditionalState? {
    ladder(log)?.rounds[round].matches.first { $0.courtIndex == court }?.games
}

func board(_ log: MatchLog, round: Int? = nil, court: Int) -> ScoreboardSnapshot? {
    SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }
}

@Suite("Winner court ladder: scoring a court")
struct LadderPlayTests {
    @Test func aLadderCourtCountsFifteenThirtyForty() throws {
        var log = ladderLog()
        score(&log, court: 1, [.a, .b, .a])

        let snapshot = try #require(board(log, court: 1))
        #expect(snapshot.primary == BySide(a: "30", b: "15"))
        #expect(snapshot.games == BySide(a: 0, b: 0))
        #expect(games(log, court: 0)?.points == BySide(a: 0, b: 0), "the other court is left alone")
    }

    @Test func timedCourtsRunUpGamesWithoutFinishingASet() throws {
        var log = ladderLog()
        score(&log, court: 0, repeated([.a], 4 * 9))

        #expect(games(log, court: 0)?.games == BySide(a: 9, b: 0))
        #expect(games(log, court: 0)?.completedSets.isEmpty == true)
        let status = try #require(ladder(log)?.status(round: 0, court: 0))
        #expect(!status.isFinished, "a timed court is only over when the whistle goes")
        #expect(status.line == BySide(a: 9, b: 0))
    }

    @Test func aMatchCourtIsWonOnSets() throws {
        var log = ladderLog(minutes: nil, rules: TraditionalRules(setsToWin: 1, gamesPerSet: 4, deuceRule: .goldenPoint))
        score(&log, court: 0, repeated([.b], 4 * 4))

        let status = try #require(ladder(log)?.status(round: 0, court: 0))
        #expect(status.winner == .b)
        #expect(status.isFinished)
        score(&log, court: 0, [.a])
        #expect(ladder(log)?.status(round: 0, court: 0) == status, "a won court takes nothing more")
    }

    @Test func thePickedSideLandsOnTheGoldenPointsCourt() throws {
        var log = ladderLog()
        score(&log, court: 1, [.a, .b, .a, .b, .a, .b])
        log.append(.chooseServeSide(.ad, round: 0, court: 1), from: device)

        #expect(games(log, court: 1)?.suddenDeathCourt == .ad)
        #expect(games(log, court: 0)?.suddenDeathCourt == nil)
        let snapshot = try #require(board(log, court: 1))
        #expect(snapshot.isSuddenDeath)
        #expect(snapshot.servingCourt == .ad)
    }

    @Test func aSideChoiceWrittenBeforeCourtsWereNamedStillDecodes() throws {
        let legacy = try JSONCoding.decoder.decode(EventKind.self, from: Data(#"{"chooseServeSide":{"_0":"ad"}}"#.utf8))
        #expect(legacy == .chooseServeSide(.ad))
        let written = String(decoding: try JSONCoding.encoder.encode(EventKind.chooseServeSide(.ad)), as: UTF8.self)
        #expect(written == #"{"chooseServeSide":{"_0":"ad"}}"#, "and one without a court is written as it always was")
    }

    @Test func typedScoresSetTheGamesOnATimedCourt() {
        var log = ladderLog()
        score(&log, court: 0, [.a, .a])
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 5, b: 3)), from: device)

        #expect(games(log, court: 0)?.games == BySide(a: 5, b: 3))
        #expect(games(log, court: 0)?.points == BySide(a: 0, b: 0))
    }

    @Test func typedScoresDoNotLandOnAMatchCourt() {
        var log = ladderLog(minutes: nil)
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 5, b: 3)), from: device)
        #expect(games(log, court: 0)?.games == BySide(a: 0, b: 0))
    }

    @Test func swappingTheServerWorksOnALadderCourt() throws {
        var log = ladderLog()
        let order = ServeOrder(firstServerIndex: 1, serversSwapped: BySide(a: true, b: false))
        log.append(.setServeOrder(round: 0, court: 1, order: order), from: device)

        #expect(games(log, court: 1)?.serveOrder == order)
        #expect(SessionReducer.state(of: log)?.serveOrder(round: 0, court: 1) == order)
        #expect(SessionReducer.state(of: log)?.serve(round: 0, court: 1)?.slot.team == .b)
    }

    @Test func onlyAnUntouchedLadderRoundCanBeRedrawn() throws {
        var log = ladderLog(players: 10)
        #expect(ladder(log)?.canRedrawCurrentRound == true)
        score(&log, court: 0, [.a])
        #expect(ladder(log)?.canRedrawCurrentRound == false)
        #expect(SessionReducer.state(of: log)?.hasResults == true)
    }

    @Test func aLadderCourtShowsGamesAndTheServe() throws {
        var log = ladderLog()
        score(&log, court: 0, repeated([.a], 4) + [.b])

        let snapshot = try #require(board(log, court: 0))
        #expect(snapshot.kind == .tournament)
        #expect(snapshot.courtLabel == "Court 1")
        #expect(snapshot.games == BySide(a: 1, b: 0))
        #expect(snapshot.primary == BySide(a: "0", b: "15"))
        #expect(snapshot.serving == .b, "the second game is served by the other side")
        #expect(snapshot.detail == "Round 1")
        #expect(snapshot.clockStart == nil, "drawn without a stamp")
    }
}
