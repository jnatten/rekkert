import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Bug `host-loses-quiet-guests`: a guest that only follows was heard by the host only when it
/// answered a point, so with points more than 15 s apart it went out of reach between them.
@Suite("A guest that only follows stays in reach", .serialized)
@MainActor
struct QuietGuestTests {
    /// As on 14 November: the host's watch scores every 20 s, one guest is on this build and
    /// the other on 1.1, each phone on the match with its watch following it, and neither guest
    /// taps anything.
    private func court(radios: CourtHarness.Radios) async -> (CourtHarness, start: Date) {
        let court = CourtHarness(guests: 2, guestRadios: { _ in radios })
        let older = court.guests.last!
        older.phone.store.actsAsOlderBuild = true
        older.watch!.store.actsAsOlderBuild = true
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })
        await court.run(for: .seconds(20))
        return (court, court.wallClock)
    }

    private func goneOutOfReach(on court: CourtHarness, since start: Date) -> [LinkRecordEntry] {
        court.host.phone.recorder.read().entries.filter { $0.kind == .outOfReach && $0.time >= start }
    }

    private func whoWent(on court: CourtHarness, since start: Date) -> Comment {
        let gone = goneOutOfReach(on: court, since: start)
        let counts = court.guests.enumerated().map { index, guest in
            "guest\(index + 1): \(gone.filter { $0.link == .guest(guest.phone.id) }.count)"
        }
        return Comment(rawValue: "out of reach: " + counts.joined(separator: ", "))
    }

    private func playOnTheHostsWatch(_ court: CourtHarness, points: Int, every gap: Duration) async {
        for _ in 0 ..< points {
            court.score(on: court.host.watch!)
            await court.run(for: gap)
        }
    }

    @Test(arguments: [CourtHarness.Radios.bluetooth, .both])
    func guestsThatOnlyFollowAreNeverOutOfReach(radios: CourtHarness.Radios) async {
        let (court, start) = await court(radios: radios)
        await playOnTheHostsWatch(court, points: 15, every: .seconds(20))

        #expect(court.allInStep())
        #expect(goneOutOfReach(on: court, since: start).isEmpty, whoWent(on: court, since: start))
    }

    /// As Amandus's phone was: iOS runs it only for a while after each Bluetooth event.
    @Test func guestsWithTheirPhonesInABagAreNeverOutOfReach() async {
        let (court, start) = await court(radios: .bluetooth)
        for guest in court.guests { guest.phone.wakefulness.isInABag = true }
        await playOnTheHostsWatch(court, points: 15, every: .seconds(20))

        #expect(court.allInStep())
        #expect(goneOutOfReach(on: court, since: start).isEmpty, whoWent(on: court, since: start))
    }

    /// A break with nobody scoring: still on, and each guest asked no more than once every 12 s.
    @Test func aQuietBreakKeepsEveryoneInReachWithoutFloodingTheRadio() async {
        let (court, start) = await court(radios: .bluetooth)
        for guest in court.guests { guest.phone.wakefulness.isInABag = true }
        let asked = court.host.phone.store.quietGuestsAsked
        await court.run(for: .seconds(120))

        #expect(goneOutOfReach(on: court, since: start).isEmpty, whoWent(on: court, since: start))
        #expect(court.host.phone.store.quietGuestsAsked - asked <= 2 * 10)
    }
}
