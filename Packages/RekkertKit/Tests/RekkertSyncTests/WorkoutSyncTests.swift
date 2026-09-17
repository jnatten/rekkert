import Foundation
import RekkertCore
import Testing

@testable import RekkertSync

/// A child that records what it was asked to carry, so a test can assert on what a scope
/// lets through rather than on what a real device would have done with it.
private final class RecordingTransport: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability: AsyncStream<Bool>
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var sent: [Wire] = []

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
        reachability = AsyncStream { _ in }
    }

    var carried: [Wire] { lock.withLock { sent } }

    var workouts: [WorkoutSignal] {
        carried.compactMap { if case .workout(let signal) = $0 { signal } else { nil } }
    }

    /// Puts a packet in as though the peer had sent it, which is how a reconnect gets staged.
    func deliver(_ wire: Wire) {
        guard let payload = try? wire.encoded() else { return }
        packets.yield(InboundPacket(payload: payload))
    }

    var isReachable: Bool { true }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        record(payload)
        return nil
    }

    func queue(_ payload: Data) { record(payload) }
    func publishSnapshot(_ payload: Data) { record(payload) }

    private func record(_ payload: Data) {
        guard let wire = try? Wire.decode(payload) else { return }
        lock.withLock { sent.append(wire) }
    }
}

@Suite("Workouts over the wire")
@MainActor
struct WorkoutSyncTests {
    private let record = WorkoutRecord(
        id: UUID(),
        startedAt: Date(timeIntervalSince1970: 768_000_000),
        endedAt: Date(timeIntervalSince1970: 768_003_600),
        duration: 3_600,
        activeEnergyKilocalories: 420,
        heartRateAverage: 128,
        heartRateMaximum: 171,
        // In the fixture so every assertion about this record covers the breakdown too — it
        // is the most personal thing on this channel and the one with furthest to travel.
        heartRateZoneTimes: [
            HeartRateZoneTime(zone: 1, lowerBound: nil, upperBound: 133, duration: 1_284),
            HeartRateZoneTime(zone: 2, lowerBound: 134, upperBound: nil, duration: 2_316),
        ]
    )

    /// The guard that matters. `LocalNetworkTransport` reaches the other people at the
    /// court, and what somebody's heart was doing is not theirs to receive.
    @Test func aWorkoutIsNeverOfferedToSomebodyElsesPhone() {
        for signal in Self.everySignal {
            #expect(
                !FanOutTransport.Scope.sharedSession.carries(.workout(signal)),
                "a shared session must not carry \(signal)"
            )
        }
    }

    /// Every case, so a new one cannot be added without deciding what it does here. There is
    /// no compiler help for this list — it is a literal, and a missing case is a leak that
    /// builds.
    private static let everySignal: [WorkoutSignal] = [
        .stop,
        .pause,
        .resume,
        .running(since: Date(timeIntervalSince1970: 768_000_000)),
        .paused(since: Date(timeIntervalSince1970: 768_000_000), elapsed: 1_284),
        .idle,
        .finished(
            WorkoutRecord(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 768_000_000),
                endedAt: Date(timeIntervalSince1970: 768_003_600),
                duration: 3_600
            )
        ),
    ]

    /// What a version skew rests on: a signal the counterpart has never heard of throws on
    /// decode and is dropped whole, rather than arriving half-read. Nothing here may lose a
    /// field on the way through.
    @Test func everySignalSurvivesTheRoundTrip() throws {
        for signal in Self.everySignal {
            let payload = try Wire.workout(signal).encoded()
            #expect(try Wire.decode(payload) == .workout(signal), "\(signal) did not come back")
        }
    }

    @Test func aPairedWatchDoesCarryIt() {
        #expect(FanOutTransport.Scope.pairedDevice.carries(.workout(.finished(record))))
    }

    @Test func theFanOutSendsItToThePairedDeviceAlone() async {
        let links = FanOutTransport()
        let paired = RecordingTransport()
        let stranger = RecordingTransport()
        links.attach(paired, as: .pairedDevice)
        links.attach(stranger, as: .sharedSession)
        let store = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)

        store.send(.finished(record))
        await eventually { !paired.carried.isEmpty }

        #expect(paired.carried.contains(.workout(.finished(record))))
        #expect(
            stranger.carried.allSatisfy { if case .workout = $0 { false } else { true } },
            "the stranger's phone was handed a workout"
        )
    }

    /// A workout ends whether or not the phone is there to hear it, so it goes on the
    /// durable queue as well as the live channel. `sendLive` gives up before its own
    /// fallback runs when nothing is reachable, which is exactly this case.
    @Test func aFinishedWorkoutIsQueuedAsWellAsSent() async throws {
        let (watch, phone) = LoopbackTransport.pair()
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = SessionStore(directory: directory)
        let receiving = MatchStore(
            device: DeviceID(), transport: phone, store: store, snapshotInterval: 0
        )
        let task = Task { await receiving.run() }
        defer { task.cancel() }

        watch.setReachable(false)
        MatchStore(device: DeviceID(), transport: watch, snapshotInterval: 0)
            .send(.finished(record))

        await eventually { (try? store.workouts())?.isEmpty == false }
        #expect(try store.workouts() == [record])
    }

    @Test func aWatchIsHandedTheSignalRatherThanFilingIt() async throws {
        let (watch, phone) = LoopbackTransport.pair()
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = SessionStore(directory: directory)
        // `keepsHistory: false` is what the watch runs as: it has nowhere to put this.
        let receiving = MatchStore(
            device: DeviceID(), transport: watch, store: store,
            snapshotInterval: 0, keepsHistory: false
        )
        var seen: [WorkoutSignal] = []
        receiving.onWorkout = { seen.append($0) }
        let task = Task { await receiving.run() }
        defer { task.cancel() }

        MatchStore(device: DeviceID(), transport: phone, snapshotInterval: 0).send(.stop)

        await eventually { !seen.isEmpty }
        #expect(seen == [.stop])
        #expect(try store.workouts().isEmpty)
    }

    /// A phone coming back mid-pause has to be told it is a pause. It may never have heard
    /// the start, and the one thing it must not be handed is the "running" that came before.
    @Test func aReconnectIsToldTheLastThingSaidRatherThanTheFirst() async {
        let links = FanOutTransport()
        let paired = RecordingTransport()
        links.attach(paired, as: .pairedDevice)
        let store = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let task = Task { await store.run() }
        defer { task.cancel() }

        let since = Date(timeIntervalSince1970: 768_000_000)
        let held = WorkoutSignal.paused(since: since, elapsed: 1_284)
        store.send(.running(since: since))
        store.send(held)
        await eventually { paired.workouts.contains(held) }

        let announced = paired.workouts.count
        paired.deliver(.hello(sessionID: UUID(), vector: VersionVector()))
        await eventually { paired.workouts.count > announced }

        #expect(paired.workouts.last == held)
    }
}
