import Foundation
import Testing
@testable import RekkertCore

@Suite("Participants")
struct ParticipantStateTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func vector(_ pairs: (DeviceID, UInt32)...) -> VersionVector {
        VersionVector(Dictionary(uniqueKeysWithValues: pairs))
    }

    @Test func coveringIsHavingEverythingTheOtherHas() {
        let a = DeviceID(), b = DeviceID()
        #expect(vector((a, 3), (b, 1)).covers(vector((a, 3))))
        #expect(!vector((a, 2)).covers(vector((a, 3))))
        #expect(!vector((a, 3)).covers(vector((a, 3), (b, 1))))
        #expect(VersionVector().covers(VersionVector()))
    }

    @Test func aGuestHeardFromLatelyWithEverythingIsInStep() {
        let guest = DeviceID(), host = DeviceID()
        var participants = Participants()
        participants.heard(from: guest, vector: vector((host, 4)), at: start)
        let state = participants.all[0].state(now: start.addingTimeInterval(15), hostCoverage: vector((host, 4)))
        #expect(state == .inStep)
    }

    @Test func aGuestHeardFromLatelyThatIsBehindIsCatchingUp() {
        let guest = DeviceID(), host = DeviceID()
        var participants = Participants()
        participants.heard(from: guest, vector: vector((host, 2)), at: start)
        let state = participants.all[0].state(now: start.addingTimeInterval(5), hostCoverage: vector((host, 4)))
        #expect(state == .catchingUp)
    }

    @Test func aGuestQuietForMoreThanFifteenSecondsIsOutOfReachSinceItWasLastHeard() {
        let guest = DeviceID(), host = DeviceID()
        var participants = Participants()
        participants.heard(from: guest, vector: vector((host, 4)), at: start)
        let state = participants.all[0].state(now: start.addingTimeInterval(15.1), hostCoverage: vector((host, 4)))
        #expect(state == .outOfReach(since: start))
    }

    @Test func sevenGuestsGetOnAndTheEighthIsTurnedAway() {
        var participants = Participants()
        for _ in 0 ..< 7 { #expect(participants.heard(from: DeviceID(), at: start) == .admitted) }
        #expect(participants.heard(from: DeviceID(), at: start) == .full)
        #expect(participants.all.count == 7)
    }

    @Test func aWatchStandingInForItsPhoneCountsWithIt() {
        let phone = DeviceID(), watch = DeviceID()
        var participants = Participants()
        for _ in 0 ..< 6 { participants.heard(from: DeviceID(), at: start) }
        #expect(participants.heard(from: phone, at: start) == .admitted)
        #expect(participants.heard(from: watch, pairedTo: phone, at: start) == .known)
        #expect(participants.all.count == 7)
        #expect(participants.participant(for: watch)?.id == phone)
    }

    @Test func aWatchThatArrivesBeforeItsPhoneIsStillOneGuest() {
        let phone = DeviceID(), watch = DeviceID()
        var participants = Participants()
        #expect(participants.heard(from: watch, pairedTo: phone, at: start) == .admitted)
        #expect(participants.heard(from: phone, at: start.addingTimeInterval(1)) == .known)
        #expect(participants.all.count == 1)
        #expect(participants.all[0].id == phone)
        #expect(participants.all[0].devices == [watch, phone])
    }

    @Test func hearingAgainMovesLastHeardOnAndNeverBack() {
        let guest = DeviceID()
        var participants = Participants()
        participants.heard(from: guest, at: start)
        #expect(participants.heard(from: guest, name: "Ada", at: start.addingTimeInterval(9)) == .known)
        participants.heard(from: guest, at: start.addingTimeInterval(3))
        #expect(participants.all[0].lastHeard == start.addingTimeInterval(9))
        #expect(participants.all[0].name == "Ada")
    }

    @Test func aGuestRemovedFreesItsPlace() {
        var participants = Participants()
        let first = DeviceID()
        participants.heard(from: first, at: start)
        for _ in 0 ..< 6 { participants.heard(from: DeviceID(), at: start) }
        participants.remove(first)
        #expect(participants.heard(from: DeviceID(), at: start) == .admitted)
    }
}
