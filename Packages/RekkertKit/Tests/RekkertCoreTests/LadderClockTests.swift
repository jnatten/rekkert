import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000EE")!)
private let watch = DeviceID(UUID(uuidString: "FFFFFFFF-0000-0000-0000-0000000000EE")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)
private func minutes(_ count: Double) -> Date { noon.addingTimeInterval(count * 60) }

private func timedLog(players: Int = 8, minutes length: Int? = 12) -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "44444444-0000-0000-0000-0000000000EE")!)
    log.append(.configure(.tournament(makeLadder(players: players, courts: 2, minutes: length)), at: noon), from: phone)
    log.drawRound(from: phone, at: noon)
    return log
}

private func clock(_ log: MatchLog) -> RoundClock? {
    ladder(log)?.currentRound?.clock
}

@Suite("Winner court ladder: the countdown")
struct LadderClockTests {
    @Test func aTimedRoundsCountdownStartsWhenItIsDrawn() {
        let log = timedLog()
        #expect(clock(log) == RoundClock(length: 12 * 60, runningSince: noon))
        #expect(board(log, court: 1)?.countdown == clock(log), "every court shows the round's countdown")
    }

    @Test func aMatchRoundHasNoCountdown() {
        let log = timedLog(minutes: nil)
        #expect(clock(log) == nil)
        #expect(board(log, court: 0)?.countdown == nil)
    }

    @Test func twoDevicesSnoozingAtOnceAddTheMinutesOnce() throws {
        let start = timedLog()
        let snoozed = try #require(clock(start)).snoozing(by: 120, at: minutes(5))
        var onPhone = start
        var onWatch = start
        onPhone.append(.setRoundClock(round: 0, clock: snoozed), from: phone)
        let fromWatch = onWatch.append(.setRoundClock(round: 0, clock: snoozed), from: watch)
        onPhone.merge([fromWatch])
        #expect(clock(onPhone)?.endsAt == minutes(14))
    }

    @Test func aClockChangeIsNotSomethingToUndo() throws {
        var log = timedLog()
        score(&log, court: 0, [.a])
        let point = try #require(log.ordered.last)
        log.append(.setRoundClock(round: 0, clock: try #require(clock(log)).pausing(at: minutes(3))), from: phone)
        #expect(log.lastUndoableEvent()?.id == point.id)
    }

    @Test func pausingAndResumingTravelWithTheLog() throws {
        var log = timedLog()
        log.append(.setRoundClock(round: 0, clock: try #require(clock(log)).pausing(at: minutes(4))), from: phone)
        #expect(clock(log)?.isPaused == true)
        log.append(.setRoundClock(round: 0, clock: try #require(clock(log)).resuming(at: minutes(6))), from: watch)
        #expect(clock(log)?.endsAt == minutes(14))
    }

    @Test func redrawingTheBenchStartsTheCountdownAgain() throws {
        var log = timedLog(players: 10)
        let late = try #require(ladder(log)?.players.first { !(ladder(log)?.currentRound?.sitOuts.contains($0.id) ?? true) })
        let tournament = try #require(ladder(log))
        log.append(.nextRound(after: tournament.rounds.count - 2, at: minutes(3), sitOuts: [late.id]), from: phone)
        #expect(ladder(log)?.currentRound?.sitOuts.contains(late.id) == true)
        #expect(clock(log)?.runningSince == minutes(3))
    }

    @Test func theWhistleHidesTheCountdownAndFreezesIt() throws {
        var log = timedLog()
        let before = clock(log)
        log.blowWhistle(from: phone, at: minutes(12))
        #expect(board(log, court: 0)?.countdown == nil)
        log.append(.setRoundClock(round: 0, clock: try #require(before).snoozing(by: 60, at: minutes(12))), from: phone)
        #expect(clock(log) == before, "a whistled round has nothing left to time")
    }

    @Test func pickingTheRoundUpAgainStartsAFullCountdown() throws {
        var log = timedLog()
        log.append(.finish(archive: true), from: phone)
        let resumed = try #require(SessionReducer.state(of: log)?.resumed()?.restarted(at: minutes(30)))
        guard case .tournament(let tournament) = resumed else { Issue.record(); return }
        #expect(tournament.currentRound?.clock == RoundClock(length: 12 * 60, runningSince: minutes(30)))
    }

    @Test func foldingTheSameLogTwiceGivesTheSameClock() {
        var log = timedLog()
        log.append(.setRoundClock(round: 0, clock: RoundClock(length: 840, runningSince: noon)), from: phone)
        #expect(SessionReducer.state(of: log) == SessionReducer.state(of: log))
    }
}

private func ring(_ alarm: inout RoundAlarm, at now: Date) -> Bool {
    alarm.tick(at: now)
}

@Suite("Winner court ladder: time's up")
struct RoundAlarmTests {
    private let session = UUID(uuidString: "44444444-0000-0000-0000-0000000000EE")!

    private func state(_ log: MatchLog) -> SessionState? { SessionReducer.state(of: log) }

    @Test func theAlarmGoesOnceWhenTimeRunsOut() {
        var alarm = RoundAlarm()
        alarm.heard(state(timedLog()), session: session, at: noon)
        #expect(alarm.nextDeadline == minutes(12))
        #expect(!ring(&alarm, at: minutes(11)))
        #expect(ring(&alarm, at: minutes(12)))
        #expect(!ring(&alarm, at: minutes(13)), "once")
        #expect(alarm.nextDeadline == nil)
    }

    @Test func snoozingLetsTheAlarmGoAgain() throws {
        var log = timedLog()
        var alarm = RoundAlarm()
        alarm.heard(state(log), session: session, at: noon)
        #expect(ring(&alarm, at: minutes(12)))

        log.append(.setRoundClock(round: 0, clock: try #require(clock(log)).snoozing(by: 120, at: minutes(12.5))), from: phone)
        alarm.heard(state(log), session: session, at: minutes(12.5))
        #expect(alarm.nextDeadline == minutes(14.5))
        #expect(ring(&alarm, at: minutes(14.5)))
    }

    @Test func aWhistleBeforeTheEndSilencesTheAlarm() {
        var log = timedLog()
        log.blowWhistle(from: phone, at: minutes(10))
        var alarm = RoundAlarm()
        alarm.heard(state(log), session: session, at: minutes(10))
        #expect(alarm.nextDeadline == nil)
        #expect(!ring(&alarm, at: minutes(12)))
    }

    @Test func aPausedCountdownNeverRings() throws {
        var log = timedLog()
        log.append(.setRoundClock(round: 0, clock: try #require(clock(log)).pausing(at: minutes(3))), from: phone)
        var alarm = RoundAlarm()
        alarm.heard(state(log), session: session, at: minutes(3))
        #expect(!ring(&alarm, at: minutes(20)))
    }

    @Test func aRoundLongOverWhenFirstSeenIsNotRungFor() {
        var alarm = RoundAlarm()
        alarm.heard(state(timedLog()), session: session, at: minutes(20))
        #expect(!ring(&alarm, at: minutes(20)))
    }

    @Test func theNextRoundArmsItAgain() {
        var log = timedLog()
        var alarm = RoundAlarm()
        alarm.heard(state(log), session: session, at: noon)
        #expect(ring(&alarm, at: minutes(12)))
        log.blowWhistle(from: phone, at: minutes(13))
        log.drawRound(from: phone, at: minutes(14))
        alarm.heard(state(log), session: session, at: minutes(14))
        #expect(alarm.nextDeadline == minutes(26))
    }
}
