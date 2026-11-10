import Foundation
import RekkertCore
import Testing

@Suite("What one device knows of another's clock")
struct ClockBoundsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    /// The far clock runs 2.5 s ahead; the question took 40 ms there and back.
    private var sample: ClockBounds {
        ClockBounds(asked: at(0), farClock: at(2.52), heard: at(0.04))
    }

    @Test func oneRoundTripBoundsTheOffset() {
        #expect(abs(sample.lower - 2.48) < 1e-6)
        #expect(abs(sample.upper - 2.52) < 1e-6)
        #expect(abs(sample.estimate - 2.5) < 1e-6)
        #expect(abs(sample.halfWidth - 0.02) < 1e-6)
    }

    @Test func boundsWidenAsTheyAge() {
        let hourLater = sample.aged(at: at(3_600))
        #expect(abs(hourLater.halfWidth - (0.02 + (3_600 - 0.04) * ClockBounds.drift)) < 1e-6)
        #expect(abs(hourLater.estimate - sample.estimate) < 1e-6)
    }

    @Test func theNarrowerSampleIsKept() {
        let wide = ClockBounds(asked: at(10), farClock: at(12.6), heard: at(10.2))
        var book = ClockBook()
        let device = DeviceID()
        book.learn(sample, for: device, at: at(10.2))
        book.learn(wide, for: device, at: at(10.2))
        #expect(book[device] == sample)
        book.learn(ClockBounds(asked: at(20), farClock: at(22.505), heard: at(20.01)), for: device, at: at(20.01))
        #expect(abs((book[device]?.halfWidth ?? 1) - 0.005) < 1e-6)
    }

    @Test func twoHopsAddUp() {
        let toHost = ClockBounds(lower: 1.0, upper: 1.04, sampledAt: at(0))
        let hostToGuest = ClockBounds(lower: -0.5, upper: -0.46, sampledAt: at(0))
        let composed = toHost.composed(with: hostToGuest)
        #expect(abs(composed.estimate - 0.54) < 1e-6)
        #expect(abs(composed.halfWidth - 0.04) < 1e-6)
    }

    @Test func aDelayIsCountedFromTheTapOnTheFarClock() {
        // Tapped at 100.00 by the far clock, which is 2.5 s ahead: 97.5 by this one. Here at 98.1.
        let delay = sample.delay(arrivedAt: at(98.1), tappedAt: at(100))
        #expect(delay.map { abs($0 - 0.6) < 0.03 } == true)
    }

    @Test func boundsTooWideGiveNoDelay() {
        let wide = ClockBounds(asked: at(0), farClock: at(2.6), heard: at(0.2))
        #expect(wide.delay(arrivedAt: at(1), tappedAt: at(3)) == nil)
    }

    @Test func boundsAgedPastTheBudgetGiveNoDelay() {
        let aDayLater = at(86_400)
        #expect(sample.delay(arrivedAt: aDayLater, tappedAt: aDayLater) == nil)
    }

    @Test func aSpanOnTheWireNeverClaimsMoreThanWasKnown() {
        let bounds = ClockBounds(lower: -2.7004, upper: -2.6891, sampledAt: at(0))
        let span = ClockSpan(bounds)
        #expect(span == ClockSpan(lower: -2_701, upper: -2_689))
        let back = span.bounds(at: at(5))
        #expect(back.lower <= bounds.lower && back.upper >= bounds.upper)
        #expect(back.sampledAt == at(5))
    }
}
