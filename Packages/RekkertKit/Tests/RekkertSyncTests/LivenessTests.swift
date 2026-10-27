import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Liveness rules")
struct LinkLivenessRuleTests {
    @Test func aGuestQuietForTenSecondsSaysHelloOncePerQuietSpell() {
        var liveness = LinkLiveness(now: .zero)
        var nudges: [Bool] = []
        for second in [9, 10, 15, 20] { nudges.append(liveness.shouldNudge(now: .seconds(second))) }
        liveness.sent(at: .seconds(21))
        for second in [30, 31] { nudges.append(liveness.shouldNudge(now: .seconds(second))) }
        #expect(nudges == [false, true, false, true, false, true])
    }

    @Test func aWrittenOffGuestIsAskedAtOnceAndThenEveryFifteenSeconds() {
        var liveness = LinkLiveness(now: .zero)
        var probes: [Bool] = []
        for second in [3, 17, 18] { probes.append(liveness.shouldProbe(now: .seconds(second))) }
        liveness.answered()
        probes.append(liveness.shouldProbe(now: .seconds(19)))
        #expect(probes == [true, false, true, true])
    }
}

@Suite("Liveness over the radio", .serialized)
@MainActor
struct LivenessTests {
    private func sharedCourt(guests: Int = 1, timing: CourtHarness.Timing = CourtHarness.Timing()) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: false, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    @Test func anIdleGuestIsHeardFromWithinTenSeconds() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        await court.run(for: .seconds(2))
        let heard = court.host.phone.store.participants.participant(for: guest.id)?.lastHeard
        await court.run(for: .seconds(12))
        let later = court.host.phone.store.participants.participant(for: guest.id)?.lastHeard
        #expect(heard != nil && later != nil && later! > heard!)
    }

    @Test func aWrittenOffGuestIsAskedAgainAndComesBack() async {
        var timing = CourtHarness.Timing()
        timing.retryInterval = .seconds(600)
        let court = await sharedCourt(guests: 2, timing: timing)
        let quiet = court.guests.last!.phone
        quiet.radio.missesIncoming = true
        for _ in 0 ..< 4 {
            court.score(on: court.host.phone)
            await court.run(for: .seconds(6))
        }
        #expect(court.host.phone.core.reachableCount == 1, "written off")
        quiet.radio.missesIncoming = false
        #expect(await court.until(within: .seconds(20)) { court.host.phone.core.reachableCount == 2 })
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }

    @Test func aGuestWhoseHellosGoUnansweredDialsAgain() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        let changes = LinkChangeLog(guest.core.linkChanges)
        defer { changes.stop() }
        guest.radio.missesIncoming = true
        #expect(await court.until(within: .seconds(60)) { changes.reasons.contains(.timeout) })
        guest.radio.missesIncoming = false
        #expect(await court.until(within: .seconds(60)) { changes.ups >= 1 })
    }

    @Test func aGuestBackInRangeIsInStepWithinThirtySeconds() async {
        let court = await sharedCourt()
        let guest = court.guests.first!.phone
        court.outOfRange(guest)
        for _ in 0 ..< 5 {
            court.score(on: court.host.phone)
            await court.run(for: .seconds(10))
        }
        court.backInRange(guest)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }
}

@MainActor
final class LinkChangeLog {
    private(set) var changes: [LinkChange] = []
    private var listening: Task<Void, Never>?

    init(_ stream: AsyncStream<LinkChange>) {
        listening = Task { [weak self] in
            for await change in stream { self?.changes.append(change) }
        }
    }

    var ups: Int { changes.count { if case .up = $0 { true } else { false } } }
    var reasons: [LinkDropReason] {
        changes.compactMap { if case .down(_, let reason) = $0 { reason } else { nil } }
    }

    func stop() { listening?.cancel() }
}
