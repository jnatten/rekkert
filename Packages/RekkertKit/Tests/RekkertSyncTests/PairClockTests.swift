import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-006: a phone times its own watch's clock on the small `clock` exchange, as it does
/// every device it has a link to, rather than only on the points the two pass between them.
@Suite("A phone asks its own watch the time", .serialized)
@MainActor
struct PairClockTests {
    /// Every watch's clock 1.5 s ahead of its phone's.
    private func sharedCourt(olderGuestWatch: Bool = false) async -> CourtHarness {
        let court = CourtHarness(guests: 1, clockSkew: { _, isWatch in (isWatch ? 1.5 : 0, 0) })
        if olderGuestWatch { court.guests.first!.watch!.store.actsAsOlderBuild = true }
        court.startMatch()
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(60)) { court.allInStep() })
        return court
    }

    @Test func eachPhoneAsksItsWatchTheTimeWhileSharing() async {
        let court = await sharedCourt()
        let watches = court.players.map { $0.watch! }
        let before = watches.map(\.store.clockQuestionsHeard)
        await court.run(for: .seconds(65))

        for (watch, heard) in zip(watches, before) {
            #expect(watch.store.clockQuestionsHeard - heard >= 2, "\(watch.name) was asked \(watch.store.clockQuestionsHeard - heard) times")
        }
    }

    /// Asked and answered: with no point passing between them, what the phone knows of its
    /// watch's clock is fresh, and right.
    @Test func thePhoneLearnsItsWatchsClockFromTheAnswer() async {
        let court = await sharedCourt()
        let (phone, watch) = (court.host.phone.store!, court.host.watch!)
        let before = phone.knownClock(of: watch.id)?.sampledAt
        await court.run(for: .seconds(65))

        let known = phone.knownClock(of: watch.id)
        #expect(known != nil && known?.sampledAt != before, "learned at \(String(describing: known?.sampledAt)), before \(String(describing: before))")
        #expect(abs((known?.estimate ?? 0) - 1.5) <= 0.1, "estimate \(String(describing: known?.estimate))")
    }

    /// FR-015's mixed versions: a 1.1 watch never hears `clock`, which it cannot read.
    @Test func aWatchOn11IsNeverAskedTheTime() async {
        let court = await sharedCourt(olderGuestWatch: true)
        await court.run(for: .seconds(65))

        #expect(court.guests.first!.watch!.store.clockQuestionsHeard == 0)
        #expect(court.host.watch!.store.clockQuestionsHeard >= 2)
    }
}
