import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("When the wrist stands in")
struct StandInPolicyTests {
    private let start = ContinuousClock.now
    private let timing = StandInPolicy.Timing()

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int(seconds * 1_000))
    }

    private func onTheMatch(
        after seconds: Double,
        phoneThrough: Bool = false,
        standingIn: Bool = false,
        hasCode: Bool = true,
        hostsMatch: Bool = true
    ) -> StandInPolicy.Circumstances {
        StandInPolicy.Circumstances(
            now: at(seconds),
            isPhoneThrough: phoneThrough,
            phoneLastThrough: start,
            hasCode: hasCode,
            isOnHostsMatch: hostsMatch,
            isStandingIn: standingIn
        )
    }

    private func asked(_ join: StandInPolicy.Join, after seconds: Double) -> StandInPolicy.Circumstances {
        StandInPolicy.Circumstances(now: at(seconds), join: join, phoneLastThrough: start)
    }

    @Test func thePhoneIsGivenItsGo() {
        let circumstances = asked(.askedPhone(since: start), after: 5)
        #expect(StandInPolicy.next(circumstances, timing: timing) == .nothing)
    }

    @Test func aPhoneThatDoesNotGetThereInTimeHandsOver() {
        let circumstances = asked(.askedPhone(since: start), after: 12)
        #expect(StandInPolicy.next(circumstances, timing: timing) == .lookOnTheWrist)
    }

    @Test func aPhoneThatFoundNothingHandsOverAtOnce() {
        var circumstances = asked(.askedPhone(since: start), after: 1)
        circumstances.phoneFailure = .notFound
        #expect(StandInPolicy.next(circumstances, timing: timing) == .lookOnTheWrist)
        circumstances.phoneFailure = .blocked
        #expect(StandInPolicy.next(circumstances, timing: timing) == .lookOnTheWrist)
    }

    @Test func aPhoneThatWentAwayMidJoinHandsOver() {
        var circumstances = asked(.askedPhone(since: start), after: 1)
        circumstances.isPairReachable = false
        #expect(StandInPolicy.next(circumstances, timing: timing) == .lookOnTheWrist)
    }

    @Test func aWrongCodeIsNotTriedOnTheWrist() {
        var circumstances = asked(.askedPhone(since: start), after: 1)
        circumstances.phoneFailure = .rejected
        #expect(StandInPolicy.next(circumstances, timing: timing) == .refused(.rejected))
    }

    @Test func landingEndsTheJoinWhoeverFoundIt() {
        var phone = asked(.askedPhone(since: start), after: 30)
        phone.hasLanded = true
        #expect(StandInPolicy.next(phone, timing: timing) == .landed)
        var own = asked(.own(since: start), after: 30)
        own.hasLanded = true
        #expect(StandInPolicy.next(own, timing: timing) == .landed)
    }

    @Test func theWristLooksForSoLongAndThenSaysSo() {
        #expect(StandInPolicy.next(asked(.own(since: start), after: 19), timing: timing) == .nothing)
        #expect(StandInPolicy.next(asked(.own(since: start), after: 20), timing: timing) == .giveUp)
    }

    @Test func aMatchThePhoneIsCarryingIsLeftToIt() {
        #expect(StandInPolicy.next(onTheMatch(after: 60, phoneThrough: true), timing: timing) == .nothing)
    }

    @Test func aPhoneGoneAMomentIsWaitedFor() {
        #expect(StandInPolicy.next(onTheMatch(after: 14), timing: timing) == .nothing)
    }

    @Test func aPhoneGonePastTheGraceIsStoodInFor() {
        #expect(StandInPolicy.next(onTheMatch(after: 15), timing: timing) == .standIn)
    }

    @Test func theWristAlreadyOnItStaysOn() {
        #expect(StandInPolicy.next(onTheMatch(after: 60, standingIn: true), timing: timing) == .nothing)
    }

    @Test func aPhoneThroughAgainIsHandedItBack() {
        #expect(StandInPolicy.next(onTheMatch(after: 60, phoneThrough: true, standingIn: true), timing: timing) == .standDown)
    }

    @Test func nothingIsStoodInForWithoutACodeOrAHost() {
        #expect(StandInPolicy.next(onTheMatch(after: 60, hasCode: false), timing: timing) == .nothing)
        #expect(StandInPolicy.next(onTheMatch(after: 60, hostsMatch: false), timing: timing) == .nothing)
    }
}
