import Foundation
import RekkertCore
import Testing

@Suite("Whether nothing was wrong when a point arrived")
struct ArrivalConditionsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let host = DeviceID()
    private let guest = DeviceID()
    private let otherGuest = DeviceID()

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func entry(_ seconds: Double, _ link: LinkRecordEntry.Link, _ kind: LinkEvent, on device: LinkRecordEntry.Device = .phone) -> LinkRecordEntry {
        LinkRecordEntry(time: at(seconds), device: device, link: link, kind: kind)
    }

    @Test func oneConnectionUpOfTwoIsNothingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(1, .host(host), .proven),
            entry(100, .host(host), .dropped(.closedByPeer)),
        ]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(110), entries: entries))
    }

    @Test func everyConnectionDownIsSomethingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(100, .host(host), .dropped(.closedByPeer)),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(110), entries: entries))
    }

    @Test func outOfReachWithinHalfAMinuteIsSomethingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(100, .host(host), .outOfReach),
            entry(101, .host(host), .backInStep),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(129), entries: entries))
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(131), entries: entries))
    }

    @Test func stillOutOfReachIsSomethingWrongHoweverLongAgo() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(10, .host(host), .outOfReach),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(200), entries: entries))
    }

    @Test func catchingUpWithinHalfAMinuteIsSomethingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(100, .host(host), .caughtUp(events: 12)),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(110), entries: entries))
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(131), entries: entries))
    }

    @Test func theHostLooksOnlyAtTheGuestThePointCameFrom() {
        let entries = [
            entry(0, .guest(guest), .proven),
            entry(0, .guest(otherGuest), .proven),
            entry(100, .guest(otherGuest), .outOfReach),
        ]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(110), from: guest, entries: entries))
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(110), from: otherGuest, entries: entries))
    }

    /// Spec 005, FR-010a: a watch's hop to or from its phone needs only the link between the two,
    /// whatever the phone's own link to the match is doing.
    @Test func aHopNeedsOnlyTheLinkBetweenAWatchAndItsPhone() {
        let watch = [entry(0, .pair, .proven, on: .watch), entry(5, .host(host), .outOfReach, on: .watch)]
        #expect(ArrivalConditions.hopNothingWrong(arrivalAt: at(100), entries: watch))
        let phone = [entry(0, .pair, .proven), entry(5, .host(host), .outOfReach)]
        #expect(ArrivalConditions.hopNothingWrong(arrivalAt: at(10), entries: phone))
        #expect(!ArrivalConditions.hopNothingWrong(arrivalAt: at(10), entries: [entry(5, .host(host), .proven)]))
    }

    @Test func aHopAfterTheWatchLostItsPhoneWithinHalfAMinuteIsSomethingWrong() {
        let back = [entry(0, .pair, .proven, on: .watch), entry(80, .pair, .dropped(.unknown), on: .watch), entry(85, .pair, .proven, on: .watch)]
        #expect(!ArrivalConditions.hopNothingWrong(arrivalAt: at(100), entries: back))
        #expect(ArrivalConditions.hopNothingWrong(arrivalAt: at(116), entries: back))
        let gone = [entry(0, .pair, .proven, on: .watch), entry(50, .pair, .dropped(.unknown), on: .watch)]
        #expect(!ArrivalConditions.hopNothingWrong(arrivalAt: at(100), entries: gone))
    }

    @Test func aHopRightAfterCatchingUpFromThePhoneIsSomethingWrong() {
        let watch = [entry(0, .pair, .proven, on: .watch), entry(90, .pair, .caughtUp(events: 4), on: .watch)]
        #expect(!ArrivalConditions.hopNothingWrong(arrivalAt: at(100), entries: watch))
        #expect(ArrivalConditions.hopNothingWrong(arrivalAt: at(121), entries: watch))
    }

    /// A link written off or redialled after going quiet is as gone as one closed.
    @Test func aLinkThatTimedOutIsDown() {
        let guestPhone = [entry(0, .host(host), .proven), entry(50, .host(host), .redialled)]
        let hostPhone = [entry(0, .guest(guest), .proven), entry(50, .guest(guest), .wroteOff)]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(100), entries: guestPhone))
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(100), from: guest, entries: hostPhone))
    }

    /// Edge Cases: a watch standing in for its phone is on the host itself, and judged as its
    /// phone would be, on its own link to the host.
    @Test func aWatchStandingInIsJudgedOnItsOwnLinkToTheHost() {
        let watch = [
            entry(0, .pair, .proven, on: .watch), entry(40, .pair, .dropped(.unknown), on: .watch),
            entry(60, .host(host), .proven, on: .watch),
        ]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(100), entries: watch))
        let standingDown = watch + [entry(90, .host(host), .dropped(.closedByPeer), on: .watch)]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(100), entries: standingDown))
    }
}
