import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID()

private func traditional(_ rule: DeuceRule = .advantage) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.traditional(
        rules: TraditionalRules(deuceRule: rule),
        teams: BySide(a: .home, b: .away)
    )), from: device)
    return log
}

private func snapshot(_ log: MatchLog) -> ScoreboardSnapshot? {
    SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }
}

private func score(_ log: inout MatchLog, _ count: Int) {
    for index in 0 ..< count {
        log.append(.point(round: 0, court: 0, team: index.isMultiple(of: 2) ? .a : .b), from: device)
    }
}

@Suite("Serve side")
struct ServeSideTests {
    @Test func serviceAlternatesSidesEveryPoint() {
        var log = traditional()
        var sides: [ServeCourt] = []
        for _ in 0 ..< 5 {
            sides.append(try! #require(snapshot(log)?.servingCourt))
            score(&log, 1)
        }
        #expect(sides == [.deuce, .ad, .deuce, .ad, .deuce], "the first point of a game is served from the right")
    }

    @Test func theSideIsNamedFromTheServersPointOfView() {
        #expect(ServeCourt.deuce.sideName == "Right")
        #expect(ServeCourt.ad.sideName == "Left")
        #expect(ServeCourt.deuce.displayName == "Deuce")
        #expect(ServeCourt.ad.displayName == "Ad")
    }

    @Test func aNewGameStartsFromTheRightAgain() {
        var log = traditional()
        score(&log, 3)
        #expect(snapshot(log)?.servingCourt == .ad, "three points played, so the next is from the left")

        // Finish the game off.
        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        #expect(snapshot(log)?.servingCourt == .deuce)
    }

    @Test func theReceiversChoiceDecidesTheSuddenDeathSide() {
        var log = traditional(.goldenPoint)
        for team in [TeamSide.a, .b, .a, .b, .a, .b] {
            log.append(.point(round: 0, court: 0, team: team), from: device)
        }
        #expect(snapshot(log)?.isSuddenDeath == true)
        #expect(snapshot(log)?.servingCourt == .deuce, "six points played is an even total")

        log.append(.chooseServeSide(.ad), from: device)
        #expect(snapshot(log)?.servingCourt == .ad, "the badge follows what the receivers picked")
    }

    @Test func aFinishedMatchShowsNoServe() {
        var log = traditional()
        for _ in 0 ..< 2 {
            for _ in 0 ..< 6 {
                for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
            }
        }
        #expect(snapshot(log)?.isFinished == true)
        #expect(snapshot(log)?.serving == nil)
        #expect(snapshot(log)?.servingCourt == nil)
    }

    @Test func tournamentCourtsCarryASideToo() {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            name: "T", format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 1)
        ))), from: device)
        log.drawRound(from: device)

        #expect(SessionReducer.state(of: log)
            .flatMap { ScoreboardSnapshot.make(from: $0, court: 0) }?.servingCourt == .deuce)

        log.append(.point(round: 0, court: 0, team: .a), from: device)
        #expect(SessionReducer.state(of: log)
            .flatMap { ScoreboardSnapshot.make(from: $0, court: 0) }?.servingCourt == .ad)
    }
}
