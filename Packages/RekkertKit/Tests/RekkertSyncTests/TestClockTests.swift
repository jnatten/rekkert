import Foundation
import Testing

@Suite("The test clock")
struct TestClockTests {
    @Test func nothingScheduledHasNothingDue() {
        #expect(TestClock().nextDue == nil)
    }

    @Test func theEarliestScheduledRunIsDue() {
        let clock = TestClock()
        clock.run(after: .seconds(5)) {}
        clock.run(after: .seconds(2)) {}
        #expect(clock.nextDue == .seconds(2))
    }

    @Test func aCancelledRunIsNotDue() {
        let clock = TestClock()
        clock.run(after: .seconds(1)) {}.cancel()
        clock.run(after: .seconds(3)) {}
        #expect(clock.nextDue == .seconds(3))
    }

    @Test func whatHasRunIsNoLongerDue() {
        let clock = TestClock()
        clock.run(after: .seconds(1)) {}
        clock.advance(by: .seconds(1))
        #expect(clock.nextDue == nil)
    }
}
