import Foundation
import HealthKit
import Observation
import RekkertCore
import WatchConnectivity

/// The phone's end of the workout. It cannot hold one — the sensors and the single session
/// the system allows are both on the wrist — so this is a remote control and nothing more.
///
/// Starting goes through Health's own way of asking a watch app to begin a workout, which
/// launches it if it is asleep. Stopping is a message on the link the score already uses,
/// and needs no launch: a running workout keeps the watch app alive to hear it.
///
/// No heart rate here, by construction. The live reading stays on the wrist it was read
/// from, and what crosses is only whether something is running.
@MainActor
@Observable
final class WorkoutController {
    private(set) var isTracking = false
    /// Running but held. A separate flag rather than a third state, because everything that
    /// asks whether a workout is on still wants the answer yes.
    private(set) var isPaused = false
    private(set) var startedAt: Date?
    /// Always nil on the phone. The property exists so the scoreboard can be written once
    /// for both devices rather than twice around an `#if`.
    let heartRate: Double? = nil
    private(set) var failure: String?

    @ObservationIgnored var publish: ((WorkoutSignal) -> Void)?

    @ObservationIgnored private let health = HKHealthStore()

    /// There has to be a wrist for any of this to mean anything. Without one the control is
    /// not shown at all, rather than shown and then doing nothing when pressed.
    var isAvailable: Bool {
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported() else { return false }
        return WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    func start() {
        guard isAvailable, !isTracking else { return }
        failure = nil
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor
        Task {
            do {
                // Sharing only. The phone never reads a workout back out of Health: it keeps
                // its own copy of the summary, so a refused read cannot empty a list of
                // workouts that plainly exist.
                try await health.requestAuthorization(
                    toShare: [HKQuantityType.workoutType()], read: []
                )
                try await health.startWatchApp(toHandle: configuration)
            } catch {
                failure = "Couldn't start on your watch"
            }
        }
    }

    func stop() {
        guard isTracking else { return }
        publish?(.stop)
    }

    /// Asked for rather than done. Nothing here changes until the watch says it has —
    /// flipping the button's own state would show a pause over a wrist still counting, which
    /// is exactly the lie this end of it cannot afford to tell.
    func pause() {
        guard isTracking, !isPaused else { return }
        publish?(.pause)
    }

    func resume() {
        guard isTracking, isPaused else { return }
        publish?(.resume)
    }

    /// What the watch says it is doing. The phone holds no opinion of its own — if the watch
    /// is out of range and stops saying anything, the last thing it said stands, and the
    /// glyph goes out when it next speaks.
    func heard(_ signal: WorkoutSignal) {
        switch signal {
        case .running(let since):
            isTracking = true
            isPaused = false
            startedAt = since
            failure = nil
        case .paused(let since, _):
            isTracking = true
            isPaused = true
            startedAt = since
            failure = nil
        case .idle, .finished:
            isTracking = false
            isPaused = false
            startedAt = nil
        // Arrives after `finished`, and may land after the next workout has started: it
        // says nothing about whether one is running now.
        case .stop, .pause, .resume, .series:
            break
        }
    }

    func acknowledgeFailure() { failure = nil }

    #if DEBUG
    /// `-rekkert-demo-workout` dresses the screen as though the watch had one running. This
    /// end of it is only ever told by a real watch, so without this the badge and the row are
    /// unreachable from `simctl`.
    func pretendRunning(paused: Bool = false) {
        isTracking = true
        isPaused = paused
        startedAt = Date().addingTimeInterval(-1_847)
    }
    #endif
}
