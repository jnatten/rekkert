import Foundation
import Testing
@testable import RekkertCore

private let deviceA = DeviceID(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!)
private let deviceB = DeviceID(UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!)

private let traditionalSetup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

private func configuredLog() -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "11111111-0000-0000-0000-000000000000")!)
    log.append(.configure(traditionalSetup), from: deviceA)
    return log
}

private func score(_ log: MatchLog) -> BySide<Int>? {
    guard case .traditional(let session) = SessionReducer.state(of: log) else { return nil }
    return session.score.points
}

@Suite("Match log")
struct MatchLogTests {
    @Test func sequenceNumbersAreConsecutivePerDevice() {
        var log = configuredLog()
        log.append(.point(court: 0, team: .a), from: deviceB)
        log.append(.point(court: 0, team: .a), from: deviceB)
        #expect(log.vector[deviceA] == 1)
        #expect(log.vector[deviceB] == 2)
    }

    @Test func lamportStampsIncreaseAcrossDevices() {
        var log = configuredLog()
        let one = log.append(.point(court: 0, team: .a), from: deviceB)
        let two = log.append(.point(court: 0, team: .b), from: deviceA)
        #expect(one.lamport < two.lamport)
    }

    @Test func mergeIsIdempotent() {
        var log = configuredLog()
        log.append(.point(court: 0, team: .a), from: deviceA)
        let snapshot = log.ordered

        #expect(log.merge(snapshot) == false)
        #expect(log.merge(snapshot + snapshot) == false)
        #expect(log.ordered == snapshot)
    }

    @Test func mergeIsOrderIndependent() {
        var log = configuredLog()
        log.append(.point(court: 0, team: .a), from: deviceA)
        log.append(.point(court: 0, team: .b), from: deviceB)
        let events = log.ordered

        var forward = MatchLog(sessionID: log.sessionID)
        forward.merge(events)
        var backward = MatchLog(sessionID: log.sessionID)
        backward.merge(events.reversed())

        #expect(forward.ordered == backward.ordered)
        #expect(score(forward) == score(backward))
    }

    @Test func missingEventsAreComputedFromTheVersionVector() {
        var mine = configuredLog()
        mine.append(.point(court: 0, team: .a), from: deviceA)
        mine.append(.point(court: 0, team: .a), from: deviceA)

        var theirs = MatchLog(sessionID: mine.sessionID)
        theirs.merge(Array(mine.ordered.prefix(2)))

        let missing = mine.events(missingRelativeTo: theirs.vector)
        #expect(missing.count == 1)
        #expect(missing[0].id.seq == 3)
    }

    @Test func concurrentTapsOnBothDevicesBothCount() {
        var phone = configuredLog()
        var watch = phone

        let fromPhone = phone.append(.point(court: 0, team: .a), from: deviceA)
        let fromWatch = watch.append(.point(court: 0, team: .a), from: deviceB)

        phone.merge([fromWatch])
        watch.merge([fromPhone])

        #expect(score(phone) == BySide(a: 2, b: 0), "neither tap is lost")
        #expect(score(phone) == score(watch))
    }

    @Test func undoRemovesItsTargetButNotLaterPoints() {
        var log = configuredLog()
        let first = log.append(.point(court: 0, team: .a), from: deviceA)
        log.append(.point(court: 0, team: .a), from: deviceA)
        log.append(.undo(first.id), from: deviceA)

        #expect(score(log) == BySide(a: 1, b: 0))
    }

    @Test func undoingAnUndoRestoresThePoint() {
        var log = configuredLog()
        let point = log.append(.point(court: 0, team: .a), from: deviceA)
        let undo = log.append(.undo(point.id), from: deviceA)
        #expect(score(log) == BySide(a: 0, b: 0))

        log.append(.undo(undo.id), from: deviceA)
        #expect(score(log) == BySide(a: 1, b: 0))
    }

    @Test func undoOnOneDeviceAndAPointOnTheOtherConverge() {
        var phone = configuredLog()
        let point = phone.append(.point(court: 0, team: .a), from: deviceA)
        var watch = phone

        let undo = phone.append(.undo(point.id), from: deviceA)
        let extra = watch.append(.point(court: 0, team: .b), from: deviceB)

        phone.merge([extra])
        watch.merge([undo])

        #expect(score(phone) == BySide(a: 0, b: 1))
        #expect(score(phone) == score(watch))
    }

    @Test func lastUndoableEventSkipsConfigurationAndUndos() {
        var log = configuredLog()
        let point = log.append(.point(court: 0, team: .a), from: deviceA)
        #expect(log.lastUndoableEvent()?.id == point.id)

        log.append(.undo(point.id), from: deviceA)
        #expect(log.lastUndoableEvent() == nil, "the only scoring event was taken back")
    }

    @Test func replayIsDeterministicUnderShufflingAndDuplication() {
        var source = configuredLog()
        var generator = SeededGenerator(seed: 99)
        for index in 0 ..< 60 {
            let team: TeamSide = index.isMultiple(of: 3) ? .b : .a
            source.append(.point(court: 0, team: team), from: index.isMultiple(of: 2) ? deviceA : deviceB)
        }
        let expected = SessionReducer.state(of: source)

        for _ in 0 ..< 25 {
            var replica = MatchLog(sessionID: source.sessionID)
            var delivery = source.ordered.shuffled(using: &generator)
            delivery += delivery.prefix(10)
            for event in delivery.shuffled(using: &generator) {
                replica.merge([event])
            }
            #expect(SessionReducer.state(of: replica) == expected)
        }
    }

    @Test func aLossyBidirectionalExchangeStillConverges() {
        var phone = configuredLog()
        var watch = phone
        var generator = SeededGenerator(seed: 7)
        var inFlightToWatch: [MatchEvent] = []
        var inFlightToPhone: [MatchEvent] = []

        var tapped = 0

        for round in 0 ..< 80 {
            if Bool.random(using: &generator) {
                inFlightToWatch.append(phone.append(.point(court: 0, team: .a), from: deviceA))
                tapped += 1
            }
            if Bool.random(using: &generator) {
                inFlightToPhone.append(watch.append(.point(court: 0, team: .b), from: deviceB))
                tapped += 1
            }
            // Deliver a random prefix; the rest stays queued in the outbox.
            if round.isMultiple(of: 3) {
                let take = Int.random(in: 0 ... inFlightToWatch.count, using: &generator)
                watch.merge(Array(inFlightToWatch.prefix(take)))
                inFlightToWatch.removeFirst(take)

                let other = Int.random(in: 0 ... inFlightToPhone.count, using: &generator)
                phone.merge(Array(inFlightToPhone.prefix(other)))
                inFlightToPhone.removeFirst(other)
            }
        }

        // Anti-entropy on reconnect: each side ships what the other is missing.
        watch.merge(phone.events(missingRelativeTo: watch.vector))
        phone.merge(watch.events(missingRelativeTo: phone.vector))

        #expect(phone.ordered == watch.ordered)
        #expect(SessionReducer.state(of: phone) == SessionReducer.state(of: watch))

        let delivered = phone.effectiveEvents.count { if case .point = $0.kind { true } else { false } }
        #expect(delivered == tapped, "every tap survived the lossy exchange")
        #expect(tapped > 50, "the fixed seed should actually exercise the path")
    }
}
