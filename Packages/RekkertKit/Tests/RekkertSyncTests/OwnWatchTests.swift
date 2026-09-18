import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

private func seeded(_ device: DeviceID, startedAt: Date = .now, points: Int = 0) -> MatchLog {
    var log = MatchLog(createdAt: startedAt)
    log.append(.configure(counting), from: device)
    for _ in 0 ..< points { log.append(.point(round: 0, court: 0, team: .a), from: device) }
    return log
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .pointCount(let session) = store.state else { return nil }
    return session.score.points
}

/// A phone with its own watch on one side and a shared match on the other. Every packet the
/// store sees looks the same whichever it came from, and that is where these go wrong.
@MainActor
private final class PhoneWithWatch {
    let phone: MatchStore
    let watch: MatchStore
    let host: MatchStore
    /// The phone's end of the link to the other phone.
    let phoneToHost: LoopbackTransport
    /// Everything the phone talks to, so a test can attach a latecomer.
    let phoneFan: FanOutTransport
    private var tasks: [Task<Void, Never>] = []

    init(phoneLog: MatchLog?, hostLog: MatchLog?, retryInterval: Duration = .seconds(4)) {
        let (phoneToWatch, watchToPhone) = LoopbackTransport.pair()
        let (hostToPhone, phoneToHost) = LoopbackTransport.pair()
        self.phoneToHost = phoneToHost

        let phoneFan = FanOutTransport()
        self.phoneFan = phoneFan
        phoneFan.attach(phoneToWatch, as: .pairedDevice)
        phoneFan.attach(phoneToHost, as: .sharedSession)
        phone = MatchStore(
            device: DeviceID(), transport: phoneFan,
            session: phoneLog.map { ActiveSession(log: $0) },
            snapshotInterval: 0, retryInterval: retryInterval
        )
        // Through a fan-out as on the wrist, so the phone's packets arrive marked as the pair's.
        let watchFan = FanOutTransport()
        watchFan.attach(watchToPhone, as: .pairedDevice)
        watch = MatchStore(device: DeviceID(), transport: watchFan, snapshotInterval: 0, keepsHistory: false)

        let hostFan = FanOutTransport()
        hostFan.attach(hostToPhone, as: .sharedSession)
        host = MatchStore(
            device: DeviceID(), transport: hostFan,
            session: hostLog.map { ActiveSession(log: $0, role: .host) },
            snapshotInterval: 0, retryInterval: retryInterval
        )
    }

    func run() -> [Task<Void, Never>] {
        tasks = [Task { [phone] in await phone.run() }, Task { [watch] in await watch.run() }, Task { [host] in await host.run() }]
        return tasks
    }
}

@Suite("A phone's own watch on a shared match")
@MainActor
struct OwnWatchTests {
    /// The first thing to answer a join is the watch on the same wrist, saying the session the
    /// phone already has. That is not the offer that was asked for.
    @Test func joiningFromYourOwnMatchStillTakesTheHosts() async throws {
        let ownDevice = DeviceID()
        let pair = PhoneWithWatch(
            phoneLog: seeded(ownDevice, points: 2),
            // Older than the phone's own, so the clocks alone would not pick it.
            hostLog: seeded(DeviceID(), startedAt: .now.addingTimeInterval(-3600), points: 1)
        )
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await eventually { pair.watch.log.sessionID == pair.phone.log.sessionID && pair.watch.state != nil }
        #expect(pair.watch.log.sessionID == pair.phone.log.sessionID, "the watch mirrors the phone's own match")

        pair.phone.beginJoining()
        await eventually { pair.phone.log.sessionID == pair.host.log.sessionID }

        #expect(pair.phone.log.sessionID == pair.host.log.sessionID, "the match the code was for")
        #expect(pair.phone.role == .guest)
        #expect(points(pair.phone) == BySide(a: 1, b: 0))
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID }
        #expect(pair.watch.log.sessionID == pair.host.log.sessionID, "and the watch follows")
    }

    /// A guest's reply that times out is a guest that did not get the event. The watch answering
    /// on everybody's behalf let the outbox forget it, and nothing ever sent it again.
    @Test func theWatchDoesNotAcknowledgeOnAGuestsBehalf() async throws {
        // The phone with the watch is the one sharing here; the other phone arrives with nothing.
        let pair = PhoneWithWatch(phoneLog: seeded(DeviceID()), hostLog: nil, retryInterval: .milliseconds(100))
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        pair.phone.startSharing()
        // Let the start-up hellos finish first: a reply to a question asked before the cut
        // still gets through it, as it would, and this is not about that. The empty phone is
        // handed the match in the meantime, and the join has to conclude all the same.
        await eventually { pair.watch.log.sessionID == pair.phone.log.sessionID }
        try await Task.sleep(for: .milliseconds(250))

        pair.host.beginJoining()
        await eventually { pair.host.log.sessionID == pair.phone.log.sessionID && pair.host.role == .guest }
        #expect(pair.host.role == .guest, "joined the match it was already holding")
        try await Task.sleep(for: .milliseconds(250))

        // The other phone's app is suspended mid-request: still connected, answering nothing.
        pair.phoneToHost.setSwallowing(true)
        pair.phone.tap(team: .a)
        await eventually { points(pair.watch) == BySide(a: 1, b: 0) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(points(pair.host) == BySide(a: 0, b: 0), "cut off, so far")

        // Back, with nothing on the wire to say so.
        pair.phoneToHost.setSwallowing(false)
        await eventually { points(pair.host) == BySide(a: 1, b: 0) }
        #expect(points(pair.host) == BySide(a: 1, b: 0), "the outbox kept it for the peer that had not answered")
    }

    /// Stepping off is the phone's doing, and the watch on the same wrist has to come with it —
    /// or it goes on showing a match nobody on that wrist is on, and offering it back to a
    /// phone that will not take it.
    @Test func leavingTakesTheWatchOffTheMatchToo() async throws {
        let pair = PhoneWithWatch(phoneLog: nil, hostLog: seeded(DeviceID(), points: 1))
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        pair.phone.beginJoining()
        await eventually { pair.phone.role == .guest && pair.watch.log.sessionID == pair.host.log.sessionID }
        #expect(pair.watch.log.sessionID == pair.host.log.sessionID, "the watch mirrors the joined match")

        pair.phone.leaveSharedSession()
        await eventually { pair.watch.state == nil }
        #expect(pair.watch.state == nil, "the watch stepped off with the phone")

        // The host plays on, still connected, and its snapshot is not taken up.
        pair.host.tap(team: .a)
        await eventually { points(pair.host) == BySide(a: 2, b: 0) }
        try await Task.sleep(for: .milliseconds(250))
        #expect(pair.phone.state == nil, "left means left")
        #expect(pair.watch.state == nil)

        pair.phone.beginJoining()
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID && points(pair.watch) == BySide(a: 2, b: 0) }
        #expect(pair.phone.role == .guest, "having left is no bar to walking back in")
        #expect(points(pair.watch) == BySide(a: 2, b: 0), "and the watch follows")
    }

    /// The watch has a Leave of its own. The phone goes with it — and stays off, though its
    /// link to the host is still up and the host's next snapshot would put the match back.
    @Test func theWatchLeavingTakesThePhoneOffToo() async throws {
        let pair = PhoneWithWatch(phoneLog: nil, hostLog: seeded(DeviceID(), points: 1))
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        pair.phone.beginJoining()
        await eventually { pair.phone.role == .guest && pair.watch.log.sessionID == pair.host.log.sessionID }

        pair.watch.leaveSharedSession()
        await eventually { pair.phone.state == nil }
        #expect(pair.phone.state == nil, "the phone stepped off with the watch")
        #expect(pair.phone.role == .solo)

        pair.host.tap(team: .a)
        await eventually { points(pair.host) == BySide(a: 2, b: 0) }
        await pair.phone.synchronise()
        try await Task.sleep(for: .milliseconds(250))
        #expect(pair.phone.state == nil, "the host's match is not taken back up")
        #expect(pair.watch.state == nil)

        pair.phone.beginJoining()
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID && points(pair.watch) == BySide(a: 2, b: 0) }
        #expect(pair.phone.role == .guest, "the pair walks back in together")
        #expect(points(pair.watch) == BySide(a: 2, b: 0))
    }

    /// A host is not taken off its own match by its watch: leaving is for somebody else's.
    /// The watch has already dropped its copy by the time the phone hears, so it has to be
    /// handed the match back rather than left refusing it for the rest of the evening.
    @Test func aHostIsNotTakenOffItsOwnMatchByItsWatch() async throws {
        let pair = PhoneWithWatch(phoneLog: seeded(DeviceID(), points: 1), hostLog: nil)
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        pair.phone.startSharing()
        await eventually { pair.watch.log.sessionID == pair.phone.log.sessionID }
        let match = pair.phone.log.sessionID

        pair.watch.leaveSharedSession()
        await eventually { pair.watch.log.sessionID == match && pair.watch.state != nil }
        #expect(pair.phone.log.sessionID == match, "the host keeps its match")
        #expect(pair.phone.role == .host)
        #expect(points(pair.watch) == BySide(a: 1, b: 0), "and the watch is handed it back")

        pair.phone.tap(team: .a)
        await eventually { points(pair.watch) == BySide(a: 2, b: 0) }
        #expect(points(pair.watch) == BySide(a: 2, b: 0), "and follows it from there")
    }

    /// A counterpart that was not running when the phone left wakes up to the application
    /// context, and the queued notice has already landed on an empty log and done nothing.
    /// What it is handed must therefore not be the match that was left.
    @Test func aWatchArrivingAfterALeaveIsNotHandedTheMatch() async throws {
        let pair = PhoneWithWatch(phoneLog: nil, hostLog: seeded(DeviceID(), points: 1))
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        pair.phone.beginJoining()
        await eventually { pair.phone.role == .guest && pair.watch.state != nil }

        pair.phone.leaveSharedSession()
        await eventually { pair.watch.state == nil }

        let (phoneToLate, lateToPhone) = LoopbackTransport.pair()
        let late = MatchStore(device: DeviceID(), transport: lateToPhone, snapshotInterval: 0, keepsHistory: false)
        let running = Task { await late.run() }
        defer { running.cancel() }
        pair.phoneFan.attach(phoneToLate, as: .pairedDevice)

        try await Task.sleep(for: .milliseconds(250))
        #expect(late.state == nil, "a match nobody here is on is not handed out")
        #expect(pair.phone.state == nil)
    }
}

/// Records what the store sends and lets the test speak back to it.
private final class RecordingTransport: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability = AsyncStream<Bool> { _ in }
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var _sent: [Wire] = []

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
    }

    var hellos: Int {
        lock.withLock { _sent.count { if case .hello = $0 { true } else { false } } }
    }

    var isReachable: Bool { true }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        if let wire = try? Wire.decode(payload) { lock.withLock { _sent.append(wire) } }
        return nil
    }

    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}

    func deliver(_ wire: Wire) throws {
        packets.yield(InboundPacket(payload: try wire.encoded()))
    }
}

@Suite("Noticing a hole in the log")
@MainActor
struct LogGapTests {
    /// An event that lands on top of a missing one is the only sign the missing one exists.
    /// The device that has it was acknowledged past it, so the only way to get it is to ask.
    @Test func anEventArrivingOverAGapAsksForWhatIsMissing() async throws {
        let hostDevice = DeviceID()
        var full = seeded(hostDevice, points: 4)
        let holey = MatchLog(
            sessionID: full.sessionID, createdAt: full.createdAt,
            events: full.ordered.filter { $0.id.seq != 3 }
        )
        let transport = RecordingTransport()
        let guest = MatchStore(
            device: DeviceID(), transport: transport,
            session: ActiveSession(log: holey, role: .guest),
            snapshotInterval: 0, retryInterval: .seconds(60)
        )
        let task = Task { await guest.run() }
        defer { task.cancel() }
        await eventually { transport.hellos == 1 }
        #expect(transport.hellos == 1, "the hello every start says")

        let next = full.append(.point(round: 0, court: 0, team: .b), from: hostDevice)
        try transport.deliver(.events(sessionID: full.sessionID, events: [next]))

        await eventually { transport.hellos >= 2 }
        #expect(transport.hellos >= 2, "it asked again rather than playing a different match")
        #expect(guest.log.coverage[hostDevice] == 2, "still short of the gap until the answer comes")
    }
}
