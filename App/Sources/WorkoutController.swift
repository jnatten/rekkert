import Foundation
import HealthKit
import Observation
import RekkertCore
import UIKit
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
    /// Only put while the phone is in hand: a summary that reaches a phone in a pocket, or
    /// one queued from a session long since played, is no moment to ask.
    private(set) var askingForEffort: EffortQuestion?
    /// What waits on Rekkert's own explanation, the first time Health would ask.
    private(set) var explaining: PendingAsk?

    enum PendingAsk {
        case start
        case prepare(onGo: @MainActor () -> Void)
    }

    @ObservationIgnored var publish: ((WorkoutSignal) -> Void)?

    @ObservationIgnored private let health = HKHealthStore()
    /// A summary arrives live and again off the queue, and the second must not ask again.
    @ObservationIgnored private var asked: Set<UUID> = []

    /// There has to be a wrist for any of this to mean anything. Without one the control is
    /// not shown at all, rather than shown and then doing nothing when pressed.
    var isAvailable: Bool { reach == .canRecord }

    var reach: HealthReach {
        #if DEBUG
        if pretendsAvailable { return .canRecord }
        #endif
        let canPairWatch = WCSession.isSupported()
        return HealthReach(
            healthAvailable: HKHealthStore.isHealthDataAvailable(),
            canPairWatch: canPairWatch,
            isPaired: canPairWatch && WCSession.default.isPaired,
            watchAppInstalled: canPairWatch && WCSession.default.isWatchAppInstalled
        )
    }

    /// `onGo` is what the caller holds back until Health may be asked: a setting chosen in
    /// Settings is only stored once the explanation in front of the request is past.
    func prepare(onGo: @escaping @MainActor () -> Void) {
        guard isAvailable else { return onGo() }
        ask(.prepare(onGo: onGo))
    }

    func start() {
        guard isAvailable, !isTracking, explaining == nil else { return }
        failure = nil
        ask(.start)
    }

    func answerExplainer(_ go: Bool) {
        guard let pending = explaining else { return }
        explaining = nil
        if go { carryOn(pending) }
    }

    private func ask(_ pending: PendingAsk) {
        Task {
            if HealthAsk.explainFirst(await health.askStatus(on: .phone)) {
                explaining = pending
            } else {
                carryOn(pending)
            }
        }
    }

    private func carryOn(_ pending: PendingAsk) {
        switch pending {
        case .prepare(let onGo):
            onGo()
            Task {
                try? await health.requestAuthorization(
                    toShare: HealthDisclosure.toShare(on: .phone), read: HealthDisclosure.toRead(on: .phone)
                )
            }
        case .start:
            launch()
        }
    }

    private func launch() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor
        Task {
            do {
                // Sharing only. The phone never reads a workout back out of Health: it keeps
                // its own copy of the summary, so a refused read cannot empty a list of
                // workouts that plainly exist.
                try await health.requestAuthorization(
                    toShare: HealthDisclosure.toShare(on: .phone), read: HealthDisclosure.toRead(on: .phone)
                )
                try await health.startWatchApp(toHandle: configuration)
            } catch let error as HKError
                where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
                failure = "Turn on Apple Health access for Rekkert in Settings."
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
            askingForEffort = nil
        case .paused(let since, _):
            isTracking = true
            isPaused = true
            startedAt = since
            failure = nil
            askingForEffort = nil
        case .idle:
            isTracking = false
            isPaused = false
            startedAt = nil
        case .finished(let record):
            isTracking = false
            isPaused = false
            startedAt = nil
            if record.effort == nil,
               UIApplication.shared.applicationState == .active,
               record.endedAt.timeIntervalSinceNow > -Self.askingWindow,
               asked.insert(record.id).inserted {
                askingForEffort = EffortQuestion(id: record.id, startedAt: record.startedAt)
            }
        case .rated(let id, _), .skipped(let id):
            asked.insert(id)
            if askingForEffort?.id == id { askingForEffort = nil }
        // Arrives after `finished`, and may land after the next workout has started: it
        // says nothing about whether one is running now.
        case .stop, .pause, .resume, .series:
            break
        }
    }

    private static let askingWindow: TimeInterval = 15 * 60

    func rate(_ effort: Int, for id: UUID) {
        asked.insert(id)
        if askingForEffort?.id == id { askingForEffort = nil }
        publish?(.rated(workoutID: id, effort: effort))
    }

    func skipEffort() {
        guard let question = askingForEffort else { return }
        askingForEffort = nil
        publish?(.skipped(workoutID: question.id))
    }

    func acknowledgeFailure() { failure = nil }

    #if DEBUG
    @ObservationIgnored var pretendsAvailable = false

    /// `-rekkert-demo-workout` dresses the screen as though the watch had one running. This
    /// end of it is only ever told by a real watch, so without this the badge and the row are
    /// unreachable from `simctl`.
    func pretendRunning(paused: Bool = false) {
        isTracking = true
        isPaused = paused
        startedAt = Date().addingTimeInterval(-1_847)
    }

    func pretendFinished(_ question: EffortQuestion) {
        askingForEffort = question
    }

    func pretendExplaining() {
        explaining = .start
    }
    #endif
}
