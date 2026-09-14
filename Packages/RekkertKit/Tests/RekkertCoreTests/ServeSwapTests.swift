import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID()

private func traditional() -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.traditional(
        rules: TraditionalRules(),
        teams: BySide(a: .home, b: .away)
    )), from: device)
    return log
}

private func serving(_ log: MatchLog) -> TeamSide? {
    SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }?.serving
}

/// What `MatchStore.swapServingTeam` does, so the tests exercise the same arithmetic.
private func swapServe(_ log: inout MatchLog, round: Int = 0, court: Int = 0) {
    guard let current = SessionReducer.state(of: log)?.firstServerIndex(round: round, court: court) else { return }
    log.append(
        .setFirstServer(round: round, court: court, index: (current + 1) % ServeRotation.order.count),
        from: device
    )
}

@Suite("Swapping service")
struct ServeSwapTests {
    @Test func swappingHandsServiceToTheOtherTeam() {
        var log = traditional()
        #expect(serving(log) == .a)

        swapServe(&log)
        #expect(serving(log) == .b)

        swapServe(&log)
        #expect(serving(log) == .a, "and back again")
    }

    @Test func theCorrectionCarriesThroughLaterGames() {
        var log = traditional()
        swapServe(&log)
        #expect(serving(log) == .b)

        // Win a game; service passes to the other team, from the corrected rotation.
        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        #expect(serving(log) == .a)

        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        #expect(serving(log) == .b)
    }

    @Test func bothDevicesCorrectingAtOnceSwapOnce() {
        let watch = DeviceID()
        let base = traditional()
        #expect(serving(base) == .a)

        var onPhone = base
        var onWatch = base
        swapServe(&onPhone)
        // The watch works it out from the same state and reaches the same answer.
        let current = SessionReducer.state(of: onWatch)!.firstServerIndex()!
        let fromWatch = onWatch.append(
            .setFirstServer(round: 0, court: 0, index: (current + 1) % ServeRotation.order.count),
            from: watch
        )
        onPhone.merge([fromWatch])
        onWatch.merge(onPhone.ordered)

        #expect(serving(onPhone) == .b, "one correction, not two")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func swappingDoesNotDisturbTheScore() {
        var log = traditional()
        for _ in 0 ..< 3 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        swapServe(&log)

        let snapshot = SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }
        #expect(snapshot?.primary.a == "40")
        #expect(snapshot?.serving == .b)
    }

    @Test func undoTargetsTheScoreRatherThanTheCorrection() {
        var log = traditional()
        let point = log.append(.point(round: 0, court: 0, team: .a), from: device)
        swapServe(&log)

        #expect(log.lastUndoableEvent()?.id == point.id,
                "a serve correction is not something undo should reach for")
    }

    @Test func eachTournamentCourtIsCorrectedOnItsOwn() {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            name: "T", format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 2)
        ))), from: device)
        log.drawRound(from: device)

        swapServe(&log, court: 1)

        let state = SessionReducer.state(of: log)
        #expect(ScoreboardSnapshot.make(from: state!, court: 0)?.serving == .a, "court 1 is untouched")
        #expect(ScoreboardSnapshot.make(from: state!, court: 1)?.serving == .b)
    }
}

@Suite("Swapping service on a tournament court")
struct CourtServeSwapTests {
    private func tournament(courts: Int = 2, players: Int = 8) -> MatchLog {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!),
            name: "Test", format: .americano,
            players: (0 ..< players).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
        ))), from: device)
        log.drawRound(from: device)
        return log
    }

    private func serving(_ log: MatchLog, court: Int) -> TeamSide? {
        SessionReducer.state(of: log)
            .flatMap { ScoreboardSnapshot.make(from: $0, court: court) }?
            .serving
    }

    @Test func everyCourtCanBeCorrectedOnItsOwn() {
        var log = tournament()
        #expect(serving(log, court: 0) == .a)
        #expect(serving(log, court: 1) == .a)

        swapServe(&log, court: 1)

        #expect(serving(log, court: 1) == .b, "the court that was corrected")
        #expect(serving(log, court: 0) == .a, "and only that one")
    }

    @Test func aCorrectionOnALaterRoundLeavesTheEarlierOneAlone() {
        var log = tournament()
        for court in 0 ..< 2 {
            log.append(.setScore(round: 0, court: court, points: BySide(a: 9, b: 7)), from: device)
        }
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.drawRound(from: device)

        swapServe(&log, round: 1, court: 0)

        guard case .tournament(let value)? = SessionReducer.state(of: log) else {
            Issue.record("expected a tournament")
            return
        }
        #expect(value.rounds[1].matches[0].state.firstServerIndex == 1)
        #expect(value.rounds[0].matches[0].state.firstServerIndex == 0, "round one is untouched")
    }

    @Test func swappingTwiceOnOneCourtPutsItBack() {
        var log = tournament()
        swapServe(&log, court: 1)
        swapServe(&log, court: 1)
        #expect(serving(log, court: 1) == .a)
    }
}
