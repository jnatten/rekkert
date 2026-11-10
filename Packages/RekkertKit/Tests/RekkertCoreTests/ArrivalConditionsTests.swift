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
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(110), on: .phone, entries: entries))
    }

    @Test func everyConnectionDownIsSomethingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(100, .host(host), .dropped(.closedByPeer)),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(110), on: .phone, entries: entries))
    }

    @Test func outOfReachWithinHalfAMinuteIsSomethingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(100, .host(host), .outOfReach),
            entry(101, .host(host), .backInStep),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(129), on: .phone, entries: entries))
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(131), on: .phone, entries: entries))
    }

    @Test func stillOutOfReachIsSomethingWrongHoweverLongAgo() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(10, .host(host), .outOfReach),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(200), on: .phone, entries: entries))
    }

    @Test func catchingUpWithinHalfAMinuteIsSomethingWrong() {
        let entries = [
            entry(0, .host(host), .proven),
            entry(100, .host(host), .caughtUp(events: 12)),
        ]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(110), on: .phone, entries: entries))
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(131), on: .phone, entries: entries))
    }

    @Test func theHostLooksOnlyAtTheGuestThePointCameFrom() {
        let entries = [
            entry(0, .guest(guest), .proven),
            entry(0, .guest(otherGuest), .proven),
            entry(100, .guest(otherGuest), .outOfReach),
        ]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(110), on: .phone, from: guest, entries: entries))
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(110), on: .phone, from: otherGuest, entries: entries))
    }

    @Test func aWatchFollowsItsPhone() {
        let watch = [entry(0, .pair, .proven, on: .watch)]
        let phoneFine = [entry(0, .host(host), .proven)]
        let phoneCut = [entry(0, .host(host), .proven), entry(50, .host(host), .dropped(.timeout))]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(100), on: .watch, entries: watch, pairEntries: phoneFine))
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(100), on: .watch, entries: watch, pairEntries: phoneCut))
    }

    @Test func aPointFromTheDevicesOwnPairNeedsOnlyThatLink() {
        let phone = [entry(0, .pair, .proven), entry(5, .host(host), .outOfReach)]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(10), on: .phone, fromPairedDevice: true, entries: phone))
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(10), on: .phone, fromPairedDevice: true, entries: [entry(5, .host(host), .proven)]))
    }

    @Test func theHostsWatchFollowsTheHostsViewOfTheGuest() {
        let watch = [entry(0, .pair, .proven, on: .watch)]
        let hostPhone = [entry(0, .guest(guest), .proven)]
        #expect(ArrivalConditions.nothingWrong(arrivalAt: at(100), on: .watch, from: guest, entries: watch, pairEntries: hostPhone))
    }

    @Test func aWatchWithItsPairLinkDownIsSomethingWrong() {
        let watch = [entry(0, .pair, .proven, on: .watch), entry(50, .pair, .dropped(.unknown), on: .watch)]
        let phoneFine = [entry(0, .host(host), .proven)]
        #expect(!ArrivalConditions.nothingWrong(arrivalAt: at(100), on: .watch, entries: watch, pairEntries: phoneFine))
    }
}
