import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-00000000000A")!)
private let watch = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-00000000000B")!)

private let noon = Date(timeIntervalSince1970: 1_700_000_000)
private func minutes(_ count: Double) -> Date { noon.addingTimeInterval(count * 60) }

private func log(_ sessionID: String = "33333333-0000-0000-0000-000000000000") -> MatchLog {
    MatchLog(sessionID: UUID(uuidString: sessionID)!)
}

private func teams() -> BySide<TeamInfo> {
    BySide(a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]), b: TeamInfo(name: "Them", players: ["Kim", "Sam"]))
}

private func tournament(players: Int = 8, courts: Int = 2) -> Tournament {
    Tournament(
        id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!),
        name: "Thursday",
        format: .americano,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
    )
}

private func friendly() -> FriendlySession {
    FriendlySession(
        id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!),
        name: "Thursday",
        rules: TraditionalRules(setsToWin: 1, deuceRule: .goldenPoint),
        players: (0 ..< 4).map { Player(name: "P\($0)") }
    )
}

private func clock(_ log: MatchLog, round: Int? = nil, court: Int = 0) -> Date? {
    SessionReducer.state(of: log)
        .flatMap { ScoreboardSnapshot.make(from: $0, round: round, court: court) }?
        .clockStart
}

@Suite("The clock on the board")
struct RoundClockTests {
    // MARK: - Where it starts

    @Test func aMatchIsTimedFromTheMomentItWasSetUp() {
        var value = log()
        value.append(.configure(.traditional(rules: TraditionalRules(), teams: teams()), at: noon), from: phone)
        #expect(clock(value) == noon)
    }

    @Test func aDrawnRoundIsTimedFromTheDrawRatherThanTheSetup() {
        var value = log()
        value.append(.configure(.tournament(tournament()), at: noon), from: phone)
        value.drawRound(from: phone, at: minutes(2))

        #expect(clock(value) == minutes(2))
        #expect(clock(value, court: 1) == minutes(2), "one clock for the round, on every court")
    }

    @Test func drawingTheNextRoundMovesTheClockOn() {
        var value = log()
        value.append(.configure(.tournament(tournament()), at: noon), from: phone)
        value.drawRound(from: phone, at: minutes(0))
        for court in 0 ..< 2 {
            value.append(.setScore(round: 0, court: court, points: BySide(a: 9, b: 7)), from: phone)
        }
        value.drawRound(from: phone, at: minutes(11))

        #expect(clock(value) == minutes(11))

        guard case .tournament(let played)? = SessionReducer.state(of: value) else {
            Issue.record("expected a tournament")
            return
        }
        #expect(played.rounds[0].startedAt == minutes(0), "the round before it keeps its own")
    }

    @Test func theWhistleStartsTheNextWinnerCourtRound() {
        var value = log()
        value.append(.configure(.winnerCourt(rules: WinnerCourtRules(), teams: teams()), at: noon), from: phone)
        #expect(clock(value) == noon, "the first round runs from the setup — nothing draws it")

        for _ in 0 ..< 4 { value.append(.point(round: 0, court: 0, team: .a), from: phone) }
        value.blowWhistle(from: phone, at: minutes(9))

        #expect(clock(value) == minutes(9))
    }

    // MARK: - Where it stops

    @Test func aWonMatchHasNoClock() {
        var value = log()
        value.append(
            .configure(.traditional(rules: TraditionalRules(setsToWin: 1), teams: teams()), at: noon),
            from: phone
        )
        #expect(clock(value) == noon)

        // Six games straight, which is the set and so the match.
        for _ in 0 ..< 24 { value.append(.point(round: 0, court: 0, team: .a), from: phone) }
        #expect(clock(value) == nil, "nothing left to time")
    }

    @Test func aFriendlyRoundStopsBeingTimedWhenItEndsAndTheNextOneStartsAgain() {
        var value = log()
        value.append(.configure(.friendly(friendly()), at: noon), from: phone)
        value.drawFriendlyRound(from: phone, at: minutes(1))
        #expect(clock(value) == minutes(1))

        for _ in 0 ..< 4 { value.append(.point(round: 0, court: 0, team: .a), from: phone) }
        value.append(.endRound(round: 0, at: minutes(14)), from: phone)
        #expect(clock(value) == nil, "a round that has been called off is not still running")

        value.drawFriendlyRound(from: phone, at: minutes(16))
        #expect(clock(value) == minutes(16))
    }

    @Test func anEarlierRoundBeingLookedBackAtIsNotTimed() {
        var value = log()
        value.append(.configure(.tournament(tournament()), at: noon), from: phone)
        value.drawRound(from: phone, at: minutes(0))
        for court in 0 ..< 2 {
            value.append(.setScore(round: 0, court: court, points: BySide(a: 9, b: 7)), from: court == 0 ? phone : watch)
        }
        value.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: phone)
        value.drawRound(from: phone, at: minutes(11))

        #expect(clock(value, round: 0) == nil, "a confirmed round is history")
        #expect(clock(value, round: 1) == minutes(11))
    }

    // MARK: - Two devices

    @Test func bothDevicesDrawingAtOnceAgreeOnTheClock() {
        var onPhone = log()
        onPhone.append(.configure(.tournament(tournament()), at: noon), from: phone)
        var onWatch = onPhone

        // Three seconds apart, which is about as far as two phones ever drift.
        onPhone.drawRound(from: phone, at: minutes(1))
        onWatch.drawRound(from: watch, at: minutes(1).addingTimeInterval(3))

        onPhone.merge(Array(onWatch.events.values))
        onWatch.merge(Array(onPhone.events.values))

        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
        let settled = clock(onPhone)
        #expect(
            settled == minutes(1) || settled == minutes(1).addingTimeInterval(3),
            "one of the two stamps, never something in between"
        )
    }

    @Test func theDrawThatWasTurnedAwayNeverMovesTheClock() {
        var onPhone = log()
        onPhone.append(.configure(.tournament(tournament()), at: noon), from: phone)
        var onWatch = onPhone

        onPhone.drawRound(from: phone, at: minutes(1))
        onWatch.drawRound(from: watch, at: minutes(1).addingTimeInterval(3))

        let before = clock(onPhone)
        // The watch's draw turns up afterwards. The guard in the reducer refuses it, so the
        // stamp it carries must not land either — which is the whole reason the reducer does
        // the stamping rather than a second pass over the log.
        onPhone.merge(Array(onWatch.events.values))
        #expect(clock(onPhone) == before)
    }

    @Test func foldingTheSameLogTwiceGivesTheSameClock() {
        var value = log()
        value.append(.configure(.tournament(tournament()), at: noon), from: phone)
        value.drawRound(from: phone, at: minutes(1))

        // The guard against anybody reaching for `Date()` inside the reducer.
        #expect(SessionReducer.state(of: value) == SessionReducer.state(of: value))
        #expect(clock(value) == minutes(1))
    }

    @Test func takingTheDrawBackPutsTheClockOnTheRoundBefore() {
        var value = log()
        value.append(.configure(.tournament(tournament()), at: noon), from: phone)
        value.drawRound(from: phone, at: minutes(0))
        for court in 0 ..< 2 {
            value.append(.setScore(round: 0, court: court, points: BySide(a: 9, b: 7)), from: phone)
        }
        let second = value.drawRound(from: phone, at: minutes(11))
        #expect(clock(value) == minutes(11))

        value.append(.undo(second.id), from: phone)
        guard case .tournament(let rewound)? = SessionReducer.state(of: value) else {
            Issue.record("expected a tournament")
            return
        }
        #expect(rewound.rounds.count == 1)
        #expect(rewound.rounds[0].startedAt == minutes(0), "back on the round that is current again")
        // The board itself shows no clock, because that round was played out to draw the one
        // just taken back. Rebuilt by the fold either way, never carried over from before.
        #expect(clock(value) == nil)
    }

    // MARK: - Corrections and old logs

    @Test func puttingTheNamesRightDoesNotRestartTheClock() {
        var value = log()
        value.append(.configure(.traditional(rules: TraditionalRules(), teams: teams()), at: noon), from: phone)
        for _ in 0 ..< 4 { value.append(.point(round: 0, court: 0, team: .a), from: phone) }

        let corrected = BySide(
            a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]),
            b: TeamInfo(name: "Them", players: ["Kim", "Samuel"])
        )
        value.append(.configure(.traditional(rules: TraditionalRules(), teams: corrected), at: minutes(20)), from: phone)

        #expect(clock(value) == noon, "the match did not start again just because a name did")
    }

    @Test func aSessionPlayedBeforeTheClockExistedSimplyHasNone() {
        var value = log()
        value.append(.configure(.tournament(tournament())), from: phone)
        value.drawRound(from: phone)

        #expect(SessionReducer.state(of: value) != nil, "it still replays")
        #expect(clock(value) == nil)
    }

    @Test func aLogWrittenWithoutStampsStillDecodes() throws {
        var value = log()
        value.append(.configure(.winnerCourt(rules: WinnerCourtRules(), teams: teams()), at: noon), from: phone)
        value.blowWhistle(from: phone, at: minutes(9))

        let roundtripped = try JSONCoding.decoder.decode(
            MatchLog.self, from: JSONCoding.encoder.encode(value)
        )
        #expect(clock(roundtripped) == minutes(9))
    }

    @Test func pickingASessionUpOutOfHistoryStartsItsClockAgain() throws {
        var value = log()
        value.append(.configure(.winnerCourt(rules: WinnerCourtRules(), teams: teams()), at: noon), from: phone)
        for _ in 0 ..< 4 { value.append(.point(round: 0, court: 0, team: .a), from: phone) }

        let archived = try #require(SessionReducer.state(of: value))
        let resumed = try #require(archived.resumed())
        #expect(clock(value) == noon)

        let daysLater = noon.addingTimeInterval(3 * 24 * 60 * 60)
        guard case .winnerCourt(let session) = resumed.restarted(at: daysLater) else {
            Issue.record("expected a winner court session")
            return
        }
        #expect(session.roundStartedAt == daysLater, "it did not go on running in the cupboard")
        #expect(session.score == archived.winnerCourtScore, "and nothing else moved")
    }
}

private extension SessionState {
    var winnerCourtScore: TraditionalState? {
        guard case .winnerCourt(let session) = self else { return nil }
        return session.score
    }
}
