import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Phones each on a link of their own, holding what they are sent and answering for themselves.
nonisolated private final class LinkedGuests: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability: AsyncStream<Bool>
    let owners: [LinkID: DeviceID]
    let all: [LinkID]
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let reachabilityUpdates: AsyncStream<Bool>.Continuation
    private let changes = Broadcast<LinkChange>()
    private let lock = NSLock()
    private var up: [LinkID]
    private var held: [LinkID: VersionVector] = [:]
    private var deaf: Set<LinkID> = []
    private var sent: [LinkID: [[EventID]]] = [:]

    init(count: Int) {
        var packetContinuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { packetContinuation = $0 }
        packets = packetContinuation
        var reachabilityContinuation: AsyncStream<Bool>.Continuation!
        reachability = AsyncStream { reachabilityContinuation = $0 }
        reachabilityUpdates = reachabilityContinuation
        all = (0 ..< count).map { _ in LinkID() }
        up = all
        owners = Dictionary(uniqueKeysWithValues: all.map { ($0, DeviceID()) })
    }

    var links: [LinkID] { lock.withLock { up } }
    var isReachable: Bool { lock.withLock { !up.isEmpty } }
    var linkChanges: AsyncStream<LinkChange> { changes.stream() }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}

    func sendLive(_ payload: Data, on link: LinkID) async -> Data? {
        guard case .events(let session, let events)? = try? Wire.decode(payload) else { return nil }
        let vector = lock.withLock { () -> VersionVector? in
            guard up.contains(link) else { return nil }
            sent[link, default: []].append(events.map(\.id))
            guard !deaf.contains(link) else { return nil }
            hold(events, on: link)
            return held[link, default: VersionVector()]
        }
        guard let vector else { return nil }
        return try? Wire.hello(sessionID: session, vector: vector, from: owners[link]).encoded()
    }

    /// Under `lock`.
    private func hold(_ events: [MatchEvent], on link: LinkID) {
        held[link] = held[link, default: VersionVector()].extended(by: events.map(\.id))
    }

    func say(_ wire: Wire, on link: LinkID) throws {
        packets.yield(InboundPacket(payload: try wire.encoded(), reply: { [weak self] data in
            guard let self, case .events(_, let events)? = try? Wire.decode(data) else { return }
            self.lock.withLock { self.hold(events, on: link) }
        }, link: link))
    }

    func sayHello(on link: LinkID, in session: UUID) throws {
        let vector = lock.withLock { held[link, default: VersionVector()] }
        try say(.hello(sessionID: session, vector: vector, from: owners[link]), on: link)
    }

    func setDeaf(_ link: LinkID, _ isDeaf: Bool) {
        lock.withLock {
            if isDeaf { deaf.insert(link) } else { deaf.remove(link) }
        }
    }

    func drop(_ link: LinkID) {
        lock.withLock { up.removeAll { $0 == link } }
        changes.yield(.down(link, .timeout))
        reachabilityUpdates.yield(isReachable)
    }

    func sends(to link: LinkID) -> [[EventID]] { lock.withLock { sent[link] ?? [] } }
    func forgetSends() { lock.withLock { sent = [:] } }
    func holds(_ id: EventID, on link: LinkID) -> Bool { lock.withLock { held[link, default: VersionVector()][id.device] >= id.seq } }
}

@Suite("Each guest is sent what it lacks", .serialized)
@MainActor
struct PerParticipantDeliveryTests {
    private struct Host {
        let store: MatchStore
        let persistence: SessionStore
        let run: Task<Void, Never>

        var outbox: [MatchEvent] { (try? persistence.loadActive())??.outbox.pending ?? [] }
    }

    private func host(over guests: LinkedGuests, pair: LoopbackTransport? = nil) async throws -> Host {
        let links = FanOutTransport()
        if let pair { links.attach(pair, as: .pairedDevice) }
        links.attach(guests, as: .sharedSession)
        let persistence = SessionStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("delivery-\(UUID().uuidString)", isDirectory: true))
        let store = MatchStore(
            device: DeviceID(), transport: links, store: persistence, snapshotInterval: 0,
            sendTimeout: .seconds(1), retryInterval: .milliseconds(50), keepsHistory: false
        )
        store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        store.startSharing()
        let run = Task { await store.run() }
        for link in guests.all { try guests.sayHello(on: link, in: store.log.sessionID) }
        await eventually { guests.all.allSatisfy { guests.holds(store.log.ordered[0].id, on: $0) } }
        for link in guests.all { try guests.sayHello(on: link, in: store.log.sessionID) }
        await eventually { store.participants.all.count == guests.all.count }
        await quietPeriod()
        guests.forgetSends()
        return Host(store: store, persistence: persistence, run: run)
    }

    private func newest(_ store: MatchStore) -> EventID { store.log.ordered.last!.id }

    @Test func eachGuestIsSentOnlyWhatItLacks() async throws {
        let guests = LinkedGuests(count: 2)
        let host = try await host(over: guests)
        defer { host.run.cancel() }
        let (heard, deaf) = (guests.all[0], guests.all[1])
        let configure = host.store.log.ordered[0].id

        guests.setDeaf(deaf, true)
        host.store.tap(team: .a)
        let first = newest(host.store)
        host.store.tap(team: .a)
        let second = newest(host.store)
        await eventually { guests.sends(to: deaf).count >= 2 }
        guests.setDeaf(deaf, false)
        await eventually { guests.holds(second, on: deaf) }

        #expect(Set(guests.sends(to: heard)) == [[first], [second]])
        #expect(Set(guests.sends(to: deaf).prefix(2)) == [[first], [second]])
        #expect(guests.sends(to: deaf).last == [first, second], "the two it missed, together")
        #expect(!guests.sends(to: deaf).joined().contains(configure), "never what it already had")
    }

    @Test func aGuestThereAndBehindHoldsTheOutboxAndOneGoneDoesNot() async throws {
        let guests = LinkedGuests(count: 2)
        let host = try await host(over: guests)
        defer { host.run.cancel() }
        await eventually { host.outbox.isEmpty }
        #expect(host.outbox.isEmpty)

        let gone = guests.all[1]
        guests.setDeaf(gone, true)
        host.store.tap(team: .a)
        await quietPeriod()
        #expect(host.outbox.count == 1, "kept while a guest that is there lacks it")

        guests.drop(gone)
        await eventually { host.outbox.isEmpty }
        #expect(host.outbox.isEmpty, "caught up from the log if it comes back, not from the outbox")
    }

    @Test func aPointIsNeverSentBackOnTheLinkItCameIn() async throws {
        let guests = LinkedGuests(count: 2)
        let host = try await host(over: guests)
        defer { host.run.cancel() }
        let (scorer, other) = (guests.all[0], guests.all[1])

        var theirs = host.store.log
        let point = theirs.append(.point(round: 0, court: 0, team: .b), from: guests.owners[scorer]!, at: MatchEvent.stamp())
        try guests.say(.events(sessionID: host.store.log.sessionID, events: [point]), on: scorer)
        await eventually { guests.holds(point.id, on: other) }

        #expect(guests.sends(to: other).contains([point.id]))
        #expect(!guests.sends(to: scorer).joined().contains(point.id))
    }

    @Test func theWatchStillAcknowledgesForItself() async throws {
        let guests = LinkedGuests(count: 1)
        let (phoneSide, watchSide) = LoopbackTransport.pair()
        let watch = MatchStore(device: DeviceID(), transport: watchSide, snapshotInterval: 0, keepsHistory: false)
        let watchRun = Task { await watch.run() }
        defer { watchRun.cancel() }
        let host = try await host(over: guests, pair: phoneSide)
        defer { host.run.cancel() }
        await eventually { host.outbox.isEmpty }

        phoneSide.setSwallowing(true)
        host.store.tap(team: .a)
        let point = newest(host.store)
        await eventually { guests.holds(point, on: guests.all[0]) }
        await quietPeriod()
        #expect(host.outbox.map(\.id) == [point], "the guest has it, the watch has not said so")

        phoneSide.setSwallowing(false)
        await eventually { host.outbox.isEmpty }
        #expect(host.outbox.isEmpty)
        #expect(watch.log.events[point] != nil)
    }

    @Test func aGuestAwayTenMinutesIsCaughtUpWithNothingLostOrDoubled() async {
        var timing = CourtHarness.Timing()
        timing.step = .milliseconds(200)
        let court = CourtHarness(guests: 2, withWatches: false, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())

        let away = court.guests.first!.phone
        let stayed = court.guests.last!.phone
        court.outOfRange(away)
        for point in 0 ..< 30 {
            court.score(on: point.isMultiple(of: 2) ? court.host.phone : stayed)
            await court.run(for: .seconds(20))
        }
        court.backInRange(away)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
        #expect(away.store.log.events.count == court.host.phone.store.log.events.count)
    }
}
