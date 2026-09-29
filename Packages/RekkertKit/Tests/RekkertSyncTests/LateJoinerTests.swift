import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

@Suite("Turning up late")
@MainActor
struct LateJoinerTests {
    /// The fan-out keeps the last snapshot so a phone joining mid-match sees the score at
    /// once. What is cached when a match ends is the farewell, and handing that to somebody
    /// who arrives afterwards would file a result for a game they never played.
    @Test func aPhoneArrivingAfterTheMatchEndedIsNotHandedIt() async throws {
        let links = FanOutTransport()
        let host = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let running = Task { await host.run() }
        defer { running.cancel() }

        let (firstHostSide, firstGuestSide) = LoopbackTransport.pair()
        links.attach(firstHostSide, as: .sharedSession)
        let early = MatchStore(device: DeviceID(), transport: firstGuestSide, snapshotInterval: 0)
        let earlyTask = Task { await early.run() }
        defer { earlyTask.cancel() }
        await quietPeriod()

        host.configure(setup)
        host.tap(team: .a)
        await eventually { inStep(early, host) }
        #expect(early.state != nil, "the one who was here got the match")

        host.finish()
        await eventually { host.state == nil && early.state == nil }
        #expect(host.state == nil, "and it is over")

        // Somebody wanders up afterwards.
        let (lateHostSide, lateGuestSide) = LoopbackTransport.pair()
        links.attach(lateHostSide, as: .sharedSession)
        let latecomer = MatchStore(device: DeviceID(), transport: lateGuestSide, snapshotInterval: 0)
        let lateTask = Task { await latecomer.run() }
        defer { lateTask.cancel() }
        await quietPeriod()

        #expect(latecomer.state == nil, "handed nothing, because there is nothing to play")
        #expect(latecomer.lastResult == nil, "and no result for a match they never played")
    }

    /// The same, the way it happens in the app: nobody attaches a child after launch. A phone
    /// that dials in arrives as a link inside the network's child or the radio's, and each of
    /// those hands every new link the snapshot it kept for them.
    @Test func aPhoneDiallingInAfterTheMatchEndedIsNotHandedIt() async throws {
        let links = FanOutTransport()
        let network = Hub()
        links.attach(network, as: .sharedSession)
        let host = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let running = Task { await host.run() }
        defer { running.cancel() }

        let early = MatchStore(device: DeviceID(), transport: network.dialIn(), snapshotInterval: 0)
        let earlyTask = Task { await early.run() }
        defer { earlyTask.cancel() }
        await quietPeriod()

        host.configure(setup)
        host.tap(team: .a)
        await eventually { inStep(early, host) }
        host.finish()
        await eventually { host.state == nil && early.state == nil }
        #expect(early.lastResult != nil, "the one who was here saw it end")

        let latecomer = MatchStore(device: DeviceID(), transport: network.dialIn(), snapshotInterval: 0)
        latecomer.beginJoining()
        let lateTask = Task { await latecomer.run() }
        defer { lateTask.cancel() }
        await quietPeriod()

        #expect(latecomer.state == nil, "handed nothing, because there is nothing to play")
        #expect(latecomer.lastResult == nil, "and no result for a match they never played")
        #expect(latecomer.isJoining, "still waiting for the host's next one")
    }

    @Test func aPhoneArrivingMidMatchIsHandedTheScore() async throws {
        let links = FanOutTransport()
        let host = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let running = Task { await host.run() }
        defer { running.cancel() }
        await quietPeriod()

        host.configure(setup)
        host.tap(team: .b)
        await quietPeriod()

        let (hostSide, guestSide) = LoopbackTransport.pair()
        links.attach(hostSide, as: .sharedSession)
        let latecomer = MatchStore(device: DeviceID(), transport: guestSide, snapshotInterval: 0)
        let joining = Task { await latecomer.run() }
        defer { joining.cancel() }
        await eventually { inStep(latecomer, host) }

        guard case .traditional(let session)? = latecomer.state else {
            Issue.record("the latecomer should have been handed the match")
            return
        }
        #expect(session.score.points == BySide(a: 0, b: 1), "without waiting for a round trip")
    }
}

/// One child with several phones on it, the way the local network and the radio each hold
/// every guest that dialled in. It keeps the last snapshot and hands it to each new link.
private final class Hub: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability: AsyncStream<Bool>
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let updates: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var links: [LoopbackTransport] = []
    private var cached: Data?

    init() {
        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation
        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        updates = reachabilityContinuation
    }

    /// A phone dialling in. Returns its end of the link.
    func dialIn() -> LoopbackTransport {
        let (ours, theirs) = LoopbackTransport.pair()
        let snapshot = lock.withLock { () -> Data? in
            links.append(ours)
            return cached
        }
        Task { [packets] in
            for await packet in ours.inbound { packets.yield(packet) }
        }
        if let snapshot { ours.publishSnapshot(snapshot) }
        updates.yield(true)
        return theirs
    }

    var isReachable: Bool { lock.withLock { !links.isEmpty } }
    var reachableCount: Int { lock.withLock { links.count } }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        let ready = lock.withLock { links }
        guard !ready.isEmpty else { return nil }
        let replies = await withTaskGroup(of: Data?.self) { group in
            for link in ready { group.addTask { await link.sendLive(payload) } }
            var collected: [Data?] = []
            for await reply in group { collected.append(reply) }
            return collected
        }
        let folded = ReplyFold.fold(replies, expected: ready.count)
        for extra in folded.unsolicited { packets.yield(InboundPacket(payload: extra)) }
        return folded.acknowledgement
    }

    func publishSnapshot(_ payload: Data) {
        let ready = lock.withLock { () -> [LoopbackTransport] in
            cached = payload
            return links
        }
        for link in ready { link.publishSnapshot(payload) }
    }

    func queue(_ payload: Data) {
        for link in lock.withLock({ links }) { link.queue(payload) }
    }

    func forgetSnapshot() {
        lock.withLock { cached = nil }
    }
}
