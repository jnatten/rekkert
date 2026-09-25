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
    /// Held where it is. Health has stopped collecting and the clock has stopped counting,
    /// but the session is still this app's and stopping it still saves what was played.
    private(set) var isPaused = false
    private(set) var startedAt: Date?
    /// What the workout page counts, which is not the wall clock since `startedAt`: a held
    /// stretch is no part of the workout, and Health leaves it out of the duration it saves.
    private(set) var clock: WorkoutClock?
    /// The live reading, for the glyph on the scoreboard and the workout page. It stays on
    /// this wrist: nothing puts it on the wire.
    private(set) var heartRate: Double?
    /// What the workout has come to so far, refreshed as Health collects it. The same
    /// figures the finished record carries, available while it is still being earned.
    private(set) var heartRateAverage: Double?
    private(set) var heartRateMaximum: Double?
    private(set) var activeEnergyKilocalories: Double?
    /// The resting burn underneath the active one, which is what total calories adds on.
    private(set) var basalEnergyKilocalories: Double?
    /// Where to place the reading, once Health has said whose heart it is. Nil until then,
    /// and nil for good where the birthday was never entered — a zone off a guessed age
    /// would be a made-up number wearing a real one's clothes.
    private(set) var zones: HeartRateZones?
    /// How long has gone into each zone so far, lowest first. Health keeps the tally itself
    /// once heart rate is being collected — there is no stopwatch here — and it is empty on
    /// a watch too old to be asked for it.
    private(set) var zoneTimes: [HeartRateZoneTime] = []
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

    /// Nil until both halves have arrived, the same rule `WorkoutRecord` keeps.
    var totalEnergyKilocalories: Double? {
        guard let activeEnergyKilocalories, let basalEnergyKilocalories else { return nil }
        return activeEnergyKilocalories + basalEnergyKilocalories
    }

    private static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor
        return configuration
    }

    /// Basal alongside active, because total calories is the two of them added up. Sharing
    /// it is not what gets it into the workout, though — see `read`.
    private static var shared: Set<HKSampleType> {
        [
            HKQuantityType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
        ]
    }

    /// The samples a workout is made of are the watch's own, written by the system, and the
    /// data source can only attach the ones this app is allowed to read. Basal was shared and
    /// never read, so the resting burn never reached the workout and Health showed the active
    /// figure under both headings.
    ///
    /// The last two are for the zones rather than the workout: an age to estimate the
    /// maximum from, and a resting rate to measure the reserve up from. Health never says
    /// whether a read was granted, so both are asked for and neither is relied on.
    private static var read: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKCharacteristicType(.dateOfBirth),
        ]
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

    /// Both of these are fire and forget. Nothing on screen moves until Health says the
    /// session has changed, which is also what makes a pause the system or another app
    /// caused look exactly like one of ours.
    func pause() {
        guard let session, isTracking, !isPaused else { return }
        session.pause()
    }

    func resume() {
        guard let session, isTracking, isPaused else { return }
        session.resume()
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
            let startedAt = recovered.startDate ?? .now
            // Health's own count rather than the wall clock: a session picked back up may
            // have spent some of its life held, and that is the part that does not count.
            adopted(
                startedAt: startedAt,
                elapsed: builder?.elapsedTime ?? Date().timeIntervalSince(startedAt),
                paused: recovered.state == .paused
            )
        }
    }

    /// The phone asked for one, by launching this app with a configuration. Same path as the
    /// button here, so there is one way in — and the configuration it sends is the one this
    /// would have built anyway.
    func handle(_ configuration: HKWorkoutConfiguration) {
        start()
    }

    /// What the phone has to say. It has no session of its own, so everything it can send is
    /// a request rather than a statement — and everything else on this channel is this
    /// watch's own voice coming back.
    func heard(_ signal: WorkoutSignal) {
        switch signal {
        case .stop: stop()
        case .pause: pause()
        case .resume: resume()
        case .running, .paused, .idle, .finished, .series: break
        }
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
        let dataSource = HKLiveWorkoutDataSource(
            healthStore: health, workoutConfiguration: Self.configuration
        )
        // Tennis collects the resting burn by default, but the defaults move with the
        // person's settings and total calories is nothing without it.
        dataSource.enableCollection(for: HKQuantityType(.basalEnergyBurned), predicate: nil)
        builder.dataSource = dataSource

        let now = Date()
        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.stopped(with: error) }
        }
        adopted(startedAt: now, elapsed: 0, paused: false)
    }

    private func attach(_ session: HKWorkoutSession) {
        let relay = Relay(
            onState: { [weak self] state, elapsed in
                Task { @MainActor in self?.changed(to: state, elapsed: elapsed) }
            },
            onFailure: { [weak self] error in Task { @MainActor in self?.failed(error) } },
            onReading: { [weak self] reading in Task { @MainActor in self?.collected(reading) } },
            onElapsed: { [weak self] elapsed in Task { @MainActor in self?.measured(elapsed) } }
        )
        self.relay = relay
        session.delegate = relay
        self.session = session
        let builder = session.associatedWorkoutBuilder()
        builder.delegate = relay
        self.builder = builder
    }

    // MARK: - What the relay reports back

    /// Every change Health reports, rather than only the ending: a pause is a state the
    /// session is put into, and it arrives here whether this app asked for it or something
    /// else on the watch did.
    fileprivate func changed(to state: HKWorkoutSessionState, elapsed: TimeInterval) {
        switch state {
        case .ended:
            sessionEnded()
        case .running, .paused:
            guard isTracking, let startedAt else { return }
            let paused = state == .paused
            isPaused = paused
            clock = .at(elapsed, paused: paused)
            // Collection stops with the session, so the live reading would sit there at
            // whatever the heart was doing when it did. The tallies under it are totals and
            // stay true; this is the one figure that would quietly go stale.
            if paused { heartRate = nil }
            publish?(paused ? .paused(since: startedAt, elapsed: elapsed) : .running(since: startedAt))
        // A session passes through `.stopped` on its way to `.ended`, and `.prepared` before
        // it has ever run. Neither is anything the screen has to say.
        default:
            break
        }
    }

    /// Health has settled its elapsed count, which it warns can move either way while a
    /// session is live. Only the clock comes off this — nothing else on screen does.
    fileprivate func measured(_ elapsed: TimeInterval) {
        guard isTracking else { return }
        clock = .at(elapsed, paused: isPaused)
    }

    fileprivate func sessionEnded() {
        guard let builder else { return finished(nil) }
        builder.addMetadata([
            HKMetadataKeyIndoorWorkout: true,
            // The nearest thing to a name. Health titles a workout from its activity type
            // and there is no padel to pick, so the word goes where Health does let an app
            // put one of its own.
            HKMetadataKeyWorkoutBrandName: "Padel",
        ]) { [weak self] _, _ in
            builder.endCollection(withEnd: Date()) { [weak self] _, _ in
                builder.finishWorkout { [weak self] workout, _ in
                    Task { @MainActor in self?.finished(workout) }
                }
            }
        }
    }

    /// Each figure kept only while it has something to say. Health hands over whatever it
    /// has collected so far, and a statistic that is not there yet must not blank one that
    /// arrived a moment ago.
    fileprivate func collected(_ reading: Reading) {
        heartRate = reading.heartRate ?? heartRate
        heartRateAverage = reading.heartRateAverage ?? heartRateAverage
        heartRateMaximum = reading.heartRateMaximum ?? heartRateMaximum
        activeEnergyKilocalories = reading.activeEnergyKilocalories ?? activeEnergyKilocalories
        basalEnergyKilocalories = reading.basalEnergyKilocalories ?? basalEnergyKilocalories
        // The bands come with the tally once it starts arriving, and they are the ones this
        // workout is actually being scored against — so they replace whatever was asked for
        // before it began, and the bar cannot disagree with the times drawn under it.
        if let zones = reading.zones { self.zones = zones }
        if !reading.zoneTimes.isEmpty { zoneTimes = reading.zoneTimes }
    }

    /// An error that stops a session is always reported before the state change that follows
    /// it, so a workout already under way is left alone here and finished by that change —
    /// which saves what was recorded before it went wrong. Apple's Workout app taking the
    /// session over mid-match arrives this way, and the half you played is worth keeping.
    fileprivate func failed(_ error: any Error) {
        guard !isTracking else { return }
        stopped(with: error)
    }

    private func adopted(startedAt: Date, elapsed: TimeInterval, paused: Bool) {
        isTracking = true
        isPaused = paused
        self.startedAt = startedAt
        clock = .at(elapsed, paused: paused)
        publish?(paused ? .paused(since: startedAt, elapsed: elapsed) : .running(since: startedAt))
        Task { await loadZones() }
    }

    /// Asked for once a workout is actually under way rather than at launch, and allowed to
    /// come back with nothing at all.
    ///
    /// The person's own bands where the system will give them up, which is watchOS 27 and
    /// later. Those are the ones the Workout app draws: generated from their health metrics,
    /// or set by hand in Health Settings, and there is no arithmetic here that could disagree
    /// with what they see everywhere else.
    private func loadZones() async {
        if #available(watchOS 27.0, *), let preferred = await preferredZones() {
            zones = preferred
            return
        }
        zones = await estimatedZones()
    }

    @available(watchOS 27.0, *)
    private func preferredZones() async -> HeartRateZones? {
        guard let configuration = try? await health.preferredWorkoutZoneConfiguration(
            for: HKQuantityType(.heartRate)
        ) else { return nil }
        // Ordered lowest to highest, and the lowest has no minimum — a heart cannot be under
        // zone 1 — so what is left is exactly the boundaries between them.
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        return HeartRateZones(
            boundaries: configuration.zones.compactMap {
                $0.minimum?.doubleValue(for: beatsPerMinute)
            }
        )
    }

    /// watchOS 26, where the bands cannot be asked for. Everything it reads is optional to
    /// the app: without an age there are no zones at all, and without a resting rate they
    /// are percentages of the maximum rather than of the reserve.
    private func estimatedZones() async -> HeartRateZones? {
        guard let components = try? health.dateOfBirthComponents(),
              let born = Calendar.current.date(from: components),
              let age = Calendar.current.dateComponents([.year], from: born, to: .now).year,
              let maximum = HeartRateZones.estimatedMaximum(forAge: age)
        else { return nil }
        return .estimated(maximum: maximum, resting: await restingHeartRate())
    }

    private func restingHeartRate() async -> Double? {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.restingHeartRate)),
            options: .mostRecent
        )
        guard let statistics = try? await descriptor.result(for: health) else { return nil }
        return statistics.mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
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
        isPaused = false
        startedAt = nil
        clock = nil
        heartRate = nil
        heartRateAverage = nil
        heartRateMaximum = nil
        activeEnergyKilocalories = nil
        basalEnergyKilocalories = nil
        zones = nil
        zoneTimes = []
    }

    func acknowledgeFailure() { failure = nil }

    #if DEBUG
    /// `-rekkert-demo-workout` dresses the screen as though one were running. The simulator
    /// has no wrist to read and Health will not start a session on it, so this is the only
    /// way the badge and the workout page get in front of `simctl`.
    func pretendRunning(paused: Bool = false) {
        isTracking = true
        isPaused = paused
        startedAt = Date().addingTimeInterval(-1_847)
        clock = .at(1_847, paused: paused)
        // Nil while held for the same reason the real thing is: there is no current reading
        // when nothing is being collected.
        heartRate = paused ? nil : 148
        heartRateAverage = 134
        heartRateMaximum = 171
        activeEnergyKilocalories = 386
        basalEnergyKilocalories = 38
        zones = .estimated(maximum: 182, resting: 62)
        zoneTimes = [
            HeartRateZoneTime(zone: 1, lowerBound: nil, upperBound: 133, duration: 384),
            HeartRateZoneTime(zone: 2, lowerBound: 134, upperBound: 145, duration: 612),
            HeartRateZoneTime(zone: 3, lowerBound: 146, upperBound: 157, duration: 731),
            HeartRateZoneTime(zone: 4, lowerBound: 158, upperBound: 169, duration: 108),
            HeartRateZoneTime(zone: 5, lowerBound: 170, upperBound: nil, duration: 12),
        ]
    }
    #endif

    /// The breakdown as Health finally scored it, which is not necessarily the last live
    /// tally: the workout goes on being added to until it is saved.
    private static func zoneTimes(of workout: HKWorkout) -> [HeartRateZoneTime] {
        guard #available(watchOS 27.0, *) else { return [] }
        return workout.zoneGroup(for: HKQuantityType(.heartRate)).map(HeartRateZoneTime.list) ?? []
    }

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
            basalEnergyKilocalories: workout.statistics(for: HKQuantityType(.basalEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()),
            heartRateAverage: heart?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            heartRateMaximum: heart?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
            heartRateZoneTimes: zoneTimes(of: workout)
        )
    }
}

/// What the clock on the workout page reads. Running, it is an anchor for the system to
/// count up from without the view being redrawn; held, it is the reading it stopped at,
/// because `Text(timerInterval:)` counts and cannot be told to stop.
///
/// Both come from the same number — Health's own elapsed time, which leaves the held
/// stretches out — so the clock and the duration Health finally saves cannot disagree.
enum WorkoutClock: Sendable, Hashable {
    case running(from: Date)
    case paused(at: TimeInterval)

    static func at(_ elapsed: TimeInterval, paused: Bool) -> WorkoutClock {
        paused ? .paused(at: elapsed) : .running(from: Date().addingTimeInterval(-elapsed))
    }
}

/// Everything the workout page and the scoreboard glyph draw, taken off the builder in one
/// go. A plain value, so it can cross from HealthKit's queue to the main actor whole.
struct Reading: Sendable {
    var heartRate: Double?
    var heartRateAverage: Double?
    var heartRateMaximum: Double?
    var activeEnergyKilocalories: Double?
    var basalEnergyKilocalories: Double?
    /// The bands this workout is being scored against, and the tally so far. Both come off
    /// the same group, and both are empty below watchOS 27.
    var zones: HeartRateZones?
    var zoneTimes: [HeartRateZoneTime] = []
}

/// Health's own tally, turned into plain numbers. Done wherever a zone group is in hand —
/// the live builder or a finished workout — so the rest of the app never has to know that
/// `HKWorkoutZoneGroup` is watchOS 27 and up.
@available(watchOS 27.0, *)
nonisolated extension HeartRateZoneTime {
    static func list(of group: HKWorkoutZoneGroup) -> [HeartRateZoneTime] {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        return group.zoneDurations
            .sorted { $0.zone.index < $1.zone.index }
            .enumerated()
            .map { position, entry in
                HeartRateZoneTime(
                    // Numbered from 1 by where it sits rather than by the index Health
                    // gives it, which is nothing this app should be repeating back.
                    zone: position + 1,
                    lowerBound: entry.zone.minimum?.doubleValue(for: beatsPerMinute),
                    upperBound: entry.zone.maximum?.doubleValue(for: beatsPerMinute),
                    duration: entry.duration
                )
            }
    }

    /// The edges of the same group, in the shape the bar draws from.
    static func zones(of group: HKWorkoutZoneGroup) -> HeartRateZones? {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        return HeartRateZones(
            boundaries: group.configuration.zones.compactMap {
                $0.minimum?.doubleValue(for: beatsPerMinute)
            }
        )
    }
}

/// The second nonisolated type in the app, for the same reason as `WCShim`: HealthKit's
/// delegates are ObjC protocols wanting an `NSObject`, and it calls them on its own queue
/// handing over a builder that is not `Sendable`. The reading is taken here, where the
/// builder is legitimately in hand, and only the `Double`s cross.
nonisolated private final class Relay: NSObject,
    HKWorkoutSessionDelegate,
    HKLiveWorkoutBuilderDelegate,
    @unchecked Sendable
{
    private let onState: @Sendable (HKWorkoutSessionState, TimeInterval) -> Void
    private let onFailure: @Sendable (any Error) -> Void
    private let onReading: @Sendable (Reading) -> Void
    private let onElapsed: @Sendable (TimeInterval) -> Void

    init(
        onState: @escaping @Sendable (HKWorkoutSessionState, TimeInterval) -> Void,
        onFailure: @escaping @Sendable (any Error) -> Void,
        onReading: @escaping @Sendable (Reading) -> Void,
        onElapsed: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.onState = onState
        self.onFailure = onFailure
        self.onReading = onReading
        self.onElapsed = onElapsed
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // The builder's count at the moment of the change, read here where the builder is
        // legitimately in hand. `date` is when it happened rather than when this arrived,
        // which Health warns can be much later if the app was suspended in between.
        onState(toState, workoutSession.associatedWorkoutBuilder().elapsedTime(at: date))
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        onFailure(error)
    }

    /// Everything is read on every collection rather than only what was named: the
    /// statistics are cheap, they are only in reach here, and the alternative is four
    /// branches that all have to be right.
    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
        // Health keeps the tally; this only picks it up, and only where there is one to pick
        // up. The group is left behind here — it is a watchOS 27 type, and what crosses is
        // plain numbers as everything else on this path does.
        var zones: HeartRateZones?
        var zoneTimes: [HeartRateZoneTime] = []
        if #available(watchOS 27.0, *),
           let group = workoutBuilder.zoneGroup(for: HKQuantityType(.heartRate)) {
            zones = HeartRateZoneTime.zones(of: group)
            zoneTimes = HeartRateZoneTime.list(of: group)
        }
        onReading(Reading(
            heartRate: heart?.mostRecentQuantity()?.doubleValue(for: beatsPerMinute),
            heartRateAverage: heart?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            heartRateMaximum: heart?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
            activeEnergyKilocalories: workoutBuilder
                .statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()),
            basalEnergyKilocalories: workoutBuilder
                .statistics(for: HKQuantityType(.basalEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()),
            zones: zones,
            zoneTimes: zoneTimes
        ))
    }

    /// A pause or a resume being recorded, which is when Health says the elapsed count has
    /// settled — it warns that until then the number can move either way.
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        onElapsed(workoutBuilder.elapsedTime)
    }
}
