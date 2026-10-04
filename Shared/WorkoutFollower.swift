import Foundation
import Observation
import RekkertCore
#if os(watchOS)
import WatchKit
#endif

@MainActor
@Observable
final class WorkoutFollower {
    private(set) var follow: WorkoutFollow
    @ObservationIgnored private let workout: WorkoutController
    @ObservationIgnored private let cues: () -> HapticPreferences
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(workout: WorkoutController, cues: @escaping () -> HapticPreferences) {
        self.workout = workout
        self.cues = cues
        #if os(watchOS)
        follow = WorkoutFollow(handlesEndings: true)
        #else
        follow = WorkoutFollow(handlesEndings: false)
        #endif
    }

    var isAskingToStart: Bool { follow.isAskingToStart }
    var isAskingToStop: Bool { follow.isAskingToStop }
    var stopsAt: Date? { follow.stopsAt }

    func heard(_ moment: MatchMoment) {
        guard workout.isAvailable else { return }
        switch moment {
        case .began(let session):
            perform(follow.began(session, cue: cues().workoutOnMatchStart, isTracking: workout.isTracking))
        case .inPlay(let session):
            follow.inPlay(session)
        case .ended(let session):
            follow.ended(session, cue: cues().workoutOnMatchEnd, isTracking: workout.isTracking, at: .now)
        }
        schedule()
    }

    func heard(_ signal: WorkoutSignal) {
        switch signal {
        case .running, .paused: follow.tracking(true)
        case .idle: follow.tracking(false)
        case .stop, .pause, .resume, .finished, .series: return
        }
        schedule()
    }

    func keepGoing() {
        follow.keepGoing()
        schedule()
    }

    func answerStart(_ yes: Bool) {
        perform(follow.answerStart(yes))
    }

    func answerStop(_ yes: Bool) {
        perform(follow.answerStop(yes))
        schedule()
    }

    func tick() {
        perform(follow.tick(at: .now, isTracking: workout.isTracking))
        schedule()
    }

    private func schedule() {
        timer?.cancel()
        timer = nil
        guard let deadline = follow.nextDeadline else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    private func perform(_ effects: [WorkoutFollow.Effect]) {
        for effect in effects {
            switch effect {
            case .start: workout.start()
            case .stop: workout.stop()
            case .buzz:
                #if os(watchOS)
                WKInterfaceDevice.current().play(.notification)
                #endif
            }
        }
    }
}
