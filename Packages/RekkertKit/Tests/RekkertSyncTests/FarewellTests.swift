import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
}

/// Two straight sets on the default rules, which is where a match ends itself.
private let tapsToWin = 48

private func winner(_ state: SessionState?) -> TeamSide? {
    guard case .traditional(let session)? = state else { return nil }
    return session.score.winner
}

private func isStopped(_ state: SessionState?) -> Bool {
    guard case .traditional(let session)? = state else { return false }
    return session.isStopped
}

private func points(_ state: SessionState?) -> BySide<Int>? {
    guard case .traditional(let session)? = state else { return nil }
    return session.score.points
}

/// A host and a guest, one link between them, wired the way the local network wires them.
@MainActor
private final class HostAndGuest {
    let host: MatchStore
    let guest: MatchStore
    let hostSide: LoopbackTransport
    let guestSide: LoopbackTransport
    private var tasks: [Task<Void, Never>] = []

    init(hostStore: SessionStore? = nil, guestStore: SessionStore? = nil) {
        (hostSide, guestSide) = LoopbackTransport.pair()
        let hostFan = FanOutTransport()
        hostFan.attach(hostSide, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(guestSide, as: .sharedSession)
        host = MatchStore(device: DeviceID(), transport: hostFan, store: hostStore, snapshotInterval: 0)
        guest = MatchStore(device: DeviceID(), transport: guestFan, store: guestStore, snapshotInterval: 0)
        host.startSharing()
    }

    func run() -> [Task<Void, Never>] {
        tasks = [Task { [host] in await host.run() }, Task { [guest] in await guest.run() }]
        return tasks
    }

    /// Everybody on the match, one point short of the end.
    func playToTheBrink() async {
        host.configure(setup)
        guest.beginJoining()
        await eventually { guest.role == .guest }
        for _ in 0 ..< (tapsToWin - 1) { host.tap(team: .a) }
        await eventually { guest.log.events.count == host.log.events.count }
    }

    func cut() {
        hostSide.setReachable(false)
        guestSide.setReachable(false)
    }

    func reconnect() {
        hostSide.setReachable(true)
        guestSide.setReachable(true)
    }
}

/// The point that ends a match is in the log the match ended on, and nowhere else once the
/// outbox has been cleared with the session. A counterpart that was out of reach for exactly
/// that point used to be told only that the match had ended, and filed it a point short.
@Suite("Ending out of earshot", .serialized)
@MainActor
struct FarewellTests {
    @Test func aGuestThatMissedTheWinningPointStillFilesTheWin() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionStore(directory: directory)
        let pair = HostAndGuest(guestStore: persistence)
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await pair.playToTheBrink()

        pair.cut()
        pair.host.tap(team: .a)
        await eventually { pair.host.state == nil }
        #expect(winner(pair.host.lastResult) == .a, "won on the host")
        #expect(pair.guest.state != nil, "while the guest heard nothing")

        pair.reconnect()
        await eventually { pair.guest.state == nil }

        #expect(winner(pair.guest.lastResult) == .a, "and the guest is shown the same win")
        #expect(isStopped(pair.guest.lastResult) == false, "not a match stopped a point short")
        let filed = try #require(try persistence.history().first)
        #expect(filed.state == pair.host.lastResult, "filed exactly as the host has it")
    }

    /// The other way round: the guest scored the point that won it while cut off. Its copy
    /// ended and retired the session, and the host — which alone could still be told — was
    /// never given the point, so the two disagreed for good.
    @Test func aWinningPointScoredOnAGuestOutOfReachStillEndsTheMatchOnTheHost() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionStore(directory: directory)
        let pair = HostAndGuest(hostStore: persistence)
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await pair.playToTheBrink()

        pair.cut()
        pair.guest.tap(team: .a)
        await eventually { pair.guest.state == nil }
        #expect(winner(pair.guest.lastResult) == .a, "won on the guest")
        #expect(pair.host.state != nil, "while the host heard nothing")

        pair.reconnect()
        await eventually { pair.host.state == nil }

        #expect(winner(pair.host.lastResult) == .a, "the host is handed the point and the match ends")
        let filed = try #require(try persistence.history().first)
        #expect(winner(filed.state) == .a, "and files the win")
        #expect(try persistence.history().count == 1)
    }

    /// A guest that merely retired its copy — its watch called off a match on a role it had
    /// wrong, say — is still saying something about its own phone, not the match.
    @Test func aGuestsRetirementWithoutAnEndingDoesNotEndTheHostsMatch() async throws {
        let pair = HostAndGuest()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        pair.host.configure(setup)
        pair.guest.beginJoining()
        await eventually { pair.guest.role == .guest }
        pair.host.tap(team: .a)
        await eventually { pair.guest.log.events.count == pair.host.log.events.count }

        // Bare, the way an older build says it, and the way a device that no longer has the
        // log says it.
        pair.guestSide.queue(try Wire.retired(sessionID: pair.host.log.sessionID, archive: true).encoded())
        try await settle()

        #expect(pair.host.state != nil, "the host plays on")
        #expect(pair.host.lastResult == nil)
    }

    /// The notice is decoded by builds that have never heard of a farewell, and this build
    /// decodes theirs.
    @Test func theNoticeStillReadsWithoutAFarewell() throws {
        let id = UUID()
        let bare = Data(#"{"retired":{"archive":false,"sessionID":"\#(id.uuidString)"}}"#.utf8)
        guard case .retired(let session, let archive, let farewell) = try Wire.decode(bare) else {
            Issue.record("a retirement notice")
            return
        }
        #expect(session == id)
        #expect(archive == false)
        #expect(farewell == nil)
    }

    @Test func theFarewellSurvivesARelaunchAndOnlyTheLastFewAreKept() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionStore(directory: directory)
        let store = MatchStore(device: DeviceID(), transport: LoopbackTransport(reachable: false), store: persistence)

        var ended: [UUID] = []
        // The last match as a counterpart that missed its ending would hold it: configured,
        // and a point short.
        var behind: MatchLog?
        for _ in 0 ..< (SessionStore.farewellsKept + 1) {
            store.startNewSession()
            store.configure(setup)
            behind = store.log
            store.tap(team: .a)
            ended.append(store.log.sessionID)
            store.finish()
            #expect(store.state == nil)
        }

        let kept = persistence.farewells().map(\.sessionID)
        #expect(kept.count == SessionStore.farewellsKept, "bounded, the way the retired list is")
        #expect(Set(kept) == Set(ended.dropFirst()), "the oldest is the one let go of")

        // Back from a relaunch, a stale counterpart's question about the last match is still
        // answered with the log it ended on — the point it missed included.
        let (one, two) = LoopbackTransport.pair()
        let relaunched = MatchStore(
            device: DeviceID(), transport: one, store: persistence,
            session: try persistence.loadActive(), snapshotInterval: 0
        )
        let stale = MatchStore(
            device: DeviceID(), transport: two,
            session: ActiveSession(log: try #require(behind), role: .guest),
            snapshotInterval: 0, keepsHistory: false
        )
        let tasks = [Task { await relaunched.run() }, Task { await stale.run() }]
        defer { tasks.forEach { $0.cancel() } }
        await eventually { stale.state == nil }

        #expect(stale.state == nil, "told it ended")
        #expect(points(stale.lastResult) == BySide(a: 1, b: 0), "with the point it was short of")
    }
}

/// A link that carries deltas and answers, and nothing else: what Bluetooth is, where the
/// whole-log snapshot is only ever handed to a peer as it arrives.
nonisolated private final class DeltaOnlyLink: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability = AsyncStream<Bool> { _ in }
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var peer: DeltaOnlyLink?

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
    }

    static func pair() -> (DeltaOnlyLink, DeltaOnlyLink) {
        let one = DeltaOnlyLink(), two = DeltaOnlyLink()
        one.peer = two
        two.peer = one
        return (one, two)
    }

    var isReachable: Bool { lock.withLock { peer != nil } }
    func activate() {}

    func sendLive(_ payload: Data) async -> Data? {
        guard let peer = lock.withLock({ self.peer }) else { return nil }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            peer.packets.yield(InboundPacket(payload: payload) { once.resume($0) })
        }
    }

    func queue(_ payload: Data) {
        lock.withLock { peer }?.packets.yield(InboundPacket(payload: payload))
    }

    func publishSnapshot(_ payload: Data) {}
}

@Suite("Handing over the match with no snapshot channel")
@MainActor
struct LiveOfferTests {
    /// A guest with nothing on it answers the host's events with an empty snapshot, which is
    /// its way of asking. The host used to answer on the durable queue alone — which reaches
    /// its own watch and nobody else — so a guest on Bluetooth only got the match on its
    /// next hello, which is its next unlock.
    @Test func anEmptyPhoneIsHandedTheMatchOverALinkThatCarriesNoSnapshots() async throws {
        let (hostSide, guestSide) = DeltaOnlyLink.pair()
        let hostFan = FanOutTransport()
        hostFan.attach(hostSide, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(guestSide, as: .sharedSession)
        let host = MatchStore(
            device: DeviceID(), transport: hostFan, snapshotInterval: 0, retryInterval: .milliseconds(100)
        )
        let guest = MatchStore(
            device: DeviceID(), transport: guestFan, snapshotInterval: 0, retryInterval: .milliseconds(100)
        )
        host.startSharing()
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        // The hellos both say on starting up are done with; from here the guest asks nothing.
        try await settle()

        host.configure(setup)
        host.tap(team: .a)
        await eventually { guest.state != nil }

        #expect(guest.log.sessionID == host.log.sessionID, "handed the match on the strength of saying it had nothing")
        #expect(points(guest.state) == BySide(a: 1, b: 0))
    }
}
