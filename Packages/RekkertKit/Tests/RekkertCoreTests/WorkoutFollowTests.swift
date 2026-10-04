import Foundation
import Testing
@testable import RekkertCore

@Suite("A workout following the match")
struct WorkoutFollowTests {
    private let match = UUID()
    private let other = UUID()
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func watch() -> WorkoutFollow { WorkoutFollow(handlesEndings: true) }

    private func settled(_ cue: WorkoutCue) -> WorkoutFollow {
        var follow = watch()
        follow.ended(match, cue: cue, isTracking: true, at: now)
        _ = follow.tick(at: now + WorkoutFollow.settle, isTracking: true)
        return follow
    }

    // MARK: - Starting

    @Test func aBeginningDoesWhatTheCueSays() {
        var off = watch()
        #expect(off.began(match, cue: .off, isTracking: false) == [])
        #expect(off.pending == nil)

        var ask = watch()
        #expect(ask.began(match, cue: .ask, isTracking: false) == [], "a question, not a start")
        #expect(ask.isAskingToStart)

        var automatic = watch()
        #expect(automatic.began(match, cue: .automatic, isTracking: false) == [.start])
        #expect(automatic.pending == nil)
    }

    @Test func aWorkoutAlreadyRunningIsLeftAlone() {
        for cue in WorkoutCue.allCases {
            var follow = watch()
            #expect(follow.began(match, cue: cue, isTracking: true) == [])
            #expect(follow.pending == nil, "nothing to ask about either")
        }
    }

    @Test func oneMatchIsOneStartHoweverOftenItIsHeard() {
        var follow = watch()
        #expect(follow.began(match, cue: .automatic, isTracking: false) == [.start])
        #expect(follow.began(match, cue: .automatic, isTracking: false) == [], "the stand-in saying it again")
        #expect(follow.began(other, cue: .automatic, isTracking: false) == [.start], "but the next match is its own")
    }

    @Test func theStartQuestionGoesOnceItIsMoot() {
        var started = watch()
        _ = started.began(match, cue: .ask, isTracking: false)
        started.tracking(true)
        #expect(!started.isAskingToStart, "started some other way")

        var over = watch()
        _ = over.began(match, cue: .ask, isTracking: false)
        over.ended(match, cue: .off, isTracking: false, at: now)
        #expect(!over.isAskingToStart, "the match it was about is over")

        var replaced = watch()
        _ = replaced.began(match, cue: .ask, isTracking: false)
        replaced.inPlay(match)
        #expect(replaced.isAskingToStart, "its own match coming on is no reason to drop it")
        replaced.inPlay(other)
        #expect(!replaced.isAskingToStart, "another one is")
    }

    @Test func theStartQuestionIsAnswered() {
        var yes = watch()
        _ = yes.began(match, cue: .ask, isTracking: false)
        #expect(yes.answerStart(true) == [.start])
        #expect(yes.pending == nil)

        var no = watch()
        _ = no.began(match, cue: .ask, isTracking: false)
        #expect(no.answerStart(false) == [])
        #expect(no.pending == nil)
        #expect(no.answerStop(true) == [], "and a stale answer to the other question does nothing")
    }

    // MARK: - Ending

    @Test func anEndingWithNothingRunningDoesNothing() {
        var follow = watch()
        follow.ended(match, cue: .automatic, isTracking: false, at: now)
        #expect(follow.pending == nil)
        #expect(follow.tick(at: now + 600, isTracking: false) == [])
    }

    @Test func anEndingLeftAloneIsLeftAlone() {
        var follow = watch()
        follow.ended(match, cue: .off, isTracking: true, at: now)
        #expect(follow.pending == nil)
    }

    @Test func thePhoneLeavesEndingsToTheWatch() {
        var phone = WorkoutFollow(handlesEndings: false)
        phone.ended(match, cue: .automatic, isTracking: true, at: now)
        #expect(phone.pending == nil)
    }

    @Test func anAutomaticStopWaitsOutTheGrace() {
        var follow = watch()
        follow.ended(match, cue: .automatic, isTracking: true, at: now)
        #expect(follow.tick(at: now + 1, isTracking: true) == [], "not believed yet")
        #expect(follow.nextDeadline == now + WorkoutFollow.settle)

        #expect(follow.tick(at: now + WorkoutFollow.settle, isTracking: true) == [.buzz], "the wrist is told")
        #expect(follow.stopsAt == now + WorkoutFollow.grace)
        #expect(follow.nextDeadline == now + WorkoutFollow.grace)

        #expect(follow.tick(at: now + 30, isTracking: true) == [])
        #expect(follow.tick(at: now + WorkoutFollow.grace, isTracking: true) == [.stop])
        #expect(follow.pending == nil)
    }

    @Test func aStopWorksOnAWorkoutStartedByHand() {
        var follow = watch()
        follow.ended(match, cue: .automatic, isTracking: true, at: now)
        #expect(follow.tick(at: now + WorkoutFollow.grace, isTracking: true) == [.buzz, .stop])
    }

    @Test func aMatchReplacedRatherThanEndedStopsNothing() {
        var follow = watch()
        follow.ended(match, cue: .automatic, isTracking: true, at: now)
        follow.inPlay(other)
        #expect(follow.pending == nil)
        #expect(follow.tick(at: now + WorkoutFollow.grace, isTracking: true) == [], "not even a buzz")
    }

    @Test func theCountdownIsCalledOff() {
        var kept = settled(.automatic)
        kept.keepGoing()
        #expect(kept.pending == nil, "keep going")

        var rematch = settled(.automatic)
        rematch.inPlay(other)
        #expect(rematch.pending == nil, "another match")

        var takenBack = settled(.automatic)
        takenBack.inPlay(UUID())
        #expect(takenBack.pending == nil, "the final point taken back, which reopens under a new id")

        var stoppedByHand = settled(.automatic)
        stoppedByHand.tracking(false)
        #expect(stoppedByHand.pending == nil, "already stopped")
        #expect(stoppedByHand.tick(at: now + WorkoutFollow.grace, isTracking: false) == [])
    }

    @Test func aStopIsAskedAboutWhenThatIsWhatWasChosen() {
        var follow = watch()
        follow.ended(match, cue: .ask, isTracking: true, at: now)
        #expect(follow.tick(at: now + WorkoutFollow.settle, isTracking: true) == [.buzz])
        #expect(follow.isAskingToStop)
        #expect(follow.nextDeadline == nil, "no clock on a question")
        #expect(follow.tick(at: now + 600, isTracking: true) == [], "and nothing happens until it is answered")

        #expect(follow.answerStop(true) == [.stop])
        #expect(follow.pending == nil)

        var kept = settled(.ask)
        #expect(kept.answerStop(false) == [])
        #expect(kept.pending == nil)
    }

    @Test func aWorkoutStoppedWhileTheEndingSettlesIsNotAskedAbout() {
        var follow = watch()
        follow.ended(match, cue: .ask, isTracking: true, at: now)
        #expect(follow.tick(at: now + WorkoutFollow.settle, isTracking: false) == [])
        #expect(follow.pending == nil)
    }

    @Test func aStopStillOwedAfterALateTickIsMadeAtOnce() {
        var follow = watch()
        follow.ended(match, cue: .automatic, isTracking: true, at: now)
        #expect(follow.tick(at: now + 120, isTracking: true) == [.buzz, .stop])
    }

    @Test func aNewMatchBeginningCallsOffTheStop() {
        var follow = settled(.automatic)
        #expect(follow.began(other, cue: .automatic, isTracking: true) == [])
        #expect(follow.pending == nil)
    }
}
