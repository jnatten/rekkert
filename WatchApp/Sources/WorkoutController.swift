import Foundation
import HealthKit
import Observation
import RekkertCore

/// The workout, which only the watch can hold: it is the device with the sensors, and the
/// system allows exactly one session across every app on the wrist.
///
/// Deliberately knows nothing about matches. It is started and stopped by hand, survives a
/// match ending, and a match neither starts nor stops it. What it gives back in exchange for
/// running is the thing the scoreboard actually wants: the watch stays frontmost, so a
/// lowered wrist comes back to the score rather than to the clock.
///
/// Recorded as tennis, indoors. Health has no padel and tennis is the nearest thing with a
/// calibrated energy model; indoors is chosen rather than offered, because an outdoor
/// workout turns on GPS and not asking for location at all is worth more than a route map of
/// a padel court.
@MainActor
@Observable
final class WorkoutController {
    private(set) var isTracking = false
    private(set) var startedAt: Date?
    /// The live reading, for the glyph on the scoreboard. It stays on this wrist: nothing
    /// puts it on the wire.
    private(set) var heartRate: Double?
    /// Set when a start went nowhere, so the button that was pressed can say so and then
    /// forget about it. Never a dialog, and never anything at all when no workout is running.
    private(set) var failure: String?

    /// Hands a finished workout, or a change of state, to the phone. Set by `AppModel`.
    @ObservationIgnored var publish: ((WorkoutSignal) -> Void)?

    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    /// Held strongly: HealthKit's delegate references are weak, and a relay that is only a
    /// local would be collected and the workout would run blind.
    @ObservationIgnored private var relay: Relay?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor
        return configuration
    }

    private static var shared: Set<HKSampleType> {
        [HKQuantityType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    private static var read: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    // MARK: - Starting and stopping

    /// Asks for Health access on the first press rather than at launch. Somebody who never
    /// touches the button is never asked, which is what makes the feature optional in the
    /// only sense that counts.
    func start() {
        guard isAvailable, !isTracking else { return }
        failure = nil
        Task {
            do {
                try await health.requestAuthorization(toShare: Self.shared, read: Self.read)
                try begin()
            } catch {
                stopped(with: error)
            }
        }
    }

    func stop() {
        guard let session, isTracking else { return }
        session.end()
    }

    /// Picks a workout back up after the app was killed mid-match — the session outlives the
    /// process, and coming back to a stopped-looking button while Health is still recording
    /// would be a lie.
    func recover() {
        guard isAvailable else { return }
        Task {
            guard let recovered = try? await health.recoverActiveWorkoutSession(),
                  recovered.state == .running || recovered.state == .paused
            else { return }
            // Collection has been going the whole time — beginning it again here would start
            // a second one over the top of it.
            attach(recovered)
            running(since: recovered.startDate ?? .now)
        }
    }

    /// The phone asked for one, by launching this app with a configuration. Same path as the
    /// button here, so there is one way in — and the configuration it sends is the one this
    /// would have built anyway.
    func handle(_ configuration: HKWorkoutConfiguration) {
        start()
    }

    /// What the phone has to say. The only thing it can ask for is a stop: it has no session
    /// of its own, and everything else on this channel is this watch's own voice coming back.
    func heard(_ signal: WorkoutSignal) {
        guard case .stop = signal else { return }
        stop()
    }

    private func begin() throws {
        // Health never says whether a read was refused, by design. Sharing does say, and
        // without it there is nowhere to put the workout — so that is the only check worth
        // making, and a refused heart rate simply leaves the glyph without a number.
        guard health.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            throw HKError(.errorAuthorizationDenied)
        }
        let session = try HKWorkoutSession(healthStore: health, configuration: Self.configuration)
        attach(session)
        guard let builder else { return }
        // Apple's own defaults for tennis, rather than a hand-picked list: this is what
        // makes the calories and the heart rate the same numbers the Workout app would have
        // recorded for the same hour.
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: health, workoutConfiguration: Self.configuration
        )

        let now = Date()
        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.stopped(with: error) }
        }
        running(since: now)
    }

    private func attach(_ session: HKWorkoutSession) {
        let relay = Relay(
            onEnded: { [weak self] in Task { @MainActor in self?.sessionEnded() } },
            onFailure: { [weak self] error in Task { @MainActor in self?.failed(error) } },
            onHeartRate: { [weak self] beats in Task { @MainActor in self?.collected(beats) } }
        )
        self.relay = relay
        session.delegate = relay
        self.session = session
        let builder = session.associatedWorkoutBuilder()
        builder.delegate = relay
        self.builder = builder
    }

    // MARK: - What the relay reports back

    fileprivate func sessionEnded() {
        guard let builder else { return finished(nil) }
        builder.addMetadata([HKMetadataKeyIndoorWorkout: true]) { [weak self] _, _ in
            builder.endCollection(withEnd: Date()) { [weak self] _, _ in
                builder.finishWorkout { [weak self] workout, _ in
                    Task { @MainActor in self?.finished(workout) }
                }
            }
        }
    }

    fileprivate func collected(_ beatsPerMinute: Double?) {
        guard let beatsPerMinute else { return }
        heartRate = beatsPerMinute
    }

    /// An error that stops a session is always reported before the state change that follows
    /// it, so a workout already under way is left alone here and finished by that change —
    /// which saves what was recorded before it went wrong. Apple's Workout app taking the
    /// session over mid-match arrives this way, and the half you played is worth keeping.
    fileprivate func failed(_ error: any Error) {
        guard !isTracking else { return }
        stopped(with: error)
    }

    private func running(since date: Date) {
        isTracking = true
        startedAt = date
        publish?(.running(since: date))
    }

    private func finished(_ workout: HKWorkout?) {
        if let workout { publish?(.finished(Self.record(from: workout))) }
        clear()
        publish?(.idle)
    }

    /// Everything that can go wrong lands here and leaves no trace on screen beyond the
    /// button that was just pressed: Health switched off, permission never granted or
    /// refused, or — the common one — Apple's own Workout app already holding the single
    /// session the watch allows.
    private func stopped(with error: any Error) {
        clear()
        publish?(.idle)
        switch (error as? HKError)?.code {
        case .errorAnotherWorkoutSessionStarted: failure = "Another workout is running"
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
            failure = "Health access is off for Rekkert"
        default: failure = "Couldn't start"
        }
    }

    private func clear() {
        session = nil
        builder = nil
        relay = nil
        isTracking = false
        startedAt = nil
        heartRate = nil
    }

    func acknowledgeFailure() { failure = nil }

    private static func record(from workout: HKWorkout) -> WorkoutRecord {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let heart = workout.statistics(for: HKQuantityType(.heartRate))
        return WorkoutRecord(
            id: workout.uuid,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            duration: workout.duration,
            activeEnergyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()),
            heartRateAverage: heart?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            heartRateMaximum: heart?.maximumQuantity()?.doubleValue(for: beatsPerMinute)
        )
    }
}

/// The second nonisolated type in the app, for the same reason as `WCShim`: HealthKit's
/// delegates are ObjC protocols wanting an `NSObject`, and it calls them on its own queue
/// handing over a builder that is not `Sendable`. The reading is taken here, where the
/// builder is legitimately in hand, and only a `Double` crosses.
nonisolated private final class Relay: NSObject,
    HKWorkoutSessionDelegate,
    HKLiveWorkoutBuilderDelegate,
    @unchecked Sendable
{
    private let onEnded: @Sendable () -> Void
    private let onFailure: @Sendable (any Error) -> Void
    private let onHeartRate: @Sendable (Double?) -> Void

    init(
        onEnded: @escaping @Sendable () -> Void,
        onFailure: @escaping @Sendable (any Error) -> Void,
        onHeartRate: @escaping @Sendable (Double?) -> Void
    ) {
        self.onEnded = onEnded
        self.onFailure = onFailure
        self.onHeartRate = onHeartRate
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        onEnded()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        onFailure(error)
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        onHeartRate(
            workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
                .mostRecentQuantity()?
                .doubleValue(for: beatsPerMinute)
        )
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
