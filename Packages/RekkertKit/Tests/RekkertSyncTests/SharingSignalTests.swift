import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let code = SessionCode("482915")!

@Suite("Joining from the wrist", .serialized)
@MainActor
struct SharingSignalTests {
    /// A phone and the watch in the same pocket, joined the way `AppModel` joins them: over a
    /// fan-out on the paired scope, which is what stamps a packet as coming from your own
    /// device rather than from somebody at the next court.
    private func pocket() -> (phone: MatchStore, watch: MatchStore) {
        let (one, two) = LoopbackTransport.pair()
        let phoneLinks = FanOutTransport()
        phoneLinks.attach(one, as: .pairedDevice)
        let watchLinks = FanOutTransport()
        watchLinks.attach(two, as: .pairedDevice)
        return (
            MatchStore(device: DeviceID(), transport: phoneLinks, snapshotInterval: 0),
            MatchStore(device: DeviceID(), transport: watchLinks, snapshotInterval: 0, keepsHistory: false)
        )
    }

    @Test func theCodeTypedOnTheWatchReachesThePhone() async throws {
        let (phone, watch) = pocket()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        let heard = Heard()
        phone.onSharing = { heard.append($0) }

        await watch.send(.join(code))
        await eventually { !heard.all.isEmpty }

        #expect(heard.all == [.join(code)])
    }

    @Test func thePhoneSaysHowItIsGoing() async throws {
        let (phone, watch) = pocket()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        let heard = Heard()
        watch.onSharing = { heard.append($0) }

        await phone.send(.state(.searching))
        await eventually { !heard.all.isEmpty }
        await phone.send(.state(.failed(.notFound)))
        await eventually { heard.all.count == 2 }

        #expect(heard.all == [.state(.searching), .state(.failed(.notFound))])
    }

    @Test func givingUpTravelsTooSoThePhoneStopsLooking() async throws {
        let (phone, watch) = pocket()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        let heard = Heard()
        phone.onSharing = { heard.append($0) }

        await watch.send(.cancel)
        await eventually { !heard.all.isEmpty }

        #expect(heard.all == [.cancel])
    }

    // MARK: - Where it must not go

    /// The load-bearing one. The code is the key to the match: a peer handed it could let
    /// anybody else in, and could rejoin an evening it was thrown out of.
    @Test func theCodeIsNeverCarriedToSomebodyElsesPhone() {
        #expect(!FanOutTransport.Scope.sharedSession.carries(.sharing(.join(code))))
        #expect(!FanOutTransport.Scope.sharedSession.carries(.sharing(.cancel)))
        #expect(!FanOutTransport.Scope.sharedSession.carries(.sharing(.state(.searching))))
        #expect(FanOutTransport.Scope.pairedDevice.carries(.sharing(.join(code))), "but to your own phone, yes")
    }

    /// The same thing again through a real pair, because the scope is only half of it: a
    /// stranger's store refuses to act on one even if a packet somehow arrives.
    @Test func aStrangersStoreNeitherHearsNorActsOnAJoin() async throws {
        let (one, two) = LoopbackTransport.pair()
        let mineLinks = FanOutTransport()
        mineLinks.attach(one, as: .sharedSession)
        let theirsLinks = FanOutTransport()
        theirsLinks.attach(two, as: .sharedSession)
        let mine = MatchStore(device: DeviceID(), transport: mineLinks, snapshotInterval: 0)
        let theirs = MatchStore(device: DeviceID(), transport: theirsLinks, snapshotInterval: 0)
        let tasks = [Task { await mine.run() }, Task { await theirs.run() }]
        defer { tasks.forEach { $0.cancel() } }

        let heard = Heard()
        theirs.onSharing = { heard.append($0) }

        mine.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        theirs.beginJoining()
        await mine.send(.join(code))

        // The match itself gets all the way across, so this is not a test of nothing moving.
        await eventually { theirs.role == .guest }
        #expect(theirs.state != nil, "the match travelled")
        #expect(heard.all.isEmpty, "the code did not")
    }

    // MARK: - Not worth saying late

    /// A request is not a state. Queued, a join would be handed over twenty minutes later and
    /// go looking for a match that finished — so it is live or it is nothing.
    @Test func aJoinIsNeverQueuedForLater() async throws {
        let transport = CountingTransport()
        let watch = MatchStore(device: DeviceID(), transport: transport, snapshotInterval: 0)
        let task = Task { await watch.run() }
        defer { task.cancel() }

        await watch.send(.join(code))
        await eventually { transport.live > 0 }

        #expect(transport.queued == 0, "nothing durable")
    }

    /// The one the watch's spinner hangs on. A join that did not land is not a slow join —
    /// nothing was queued and nobody is looking — so the wrist has to be able to tell.
    @Test func aJoinThatDidNotLandSaysSo() async throws {
        let watch = MatchStore(
            device: DeviceID(), transport: LoopbackTransport(reachable: false), snapshotInterval: 0
        )
        let task = Task { await watch.run() }
        defer { task.cancel() }

        #expect(await watch.send(.join(code)) == false)
        #expect(await watch.send(.cancel) == false)
    }

    @Test func aJoinThatLandedSaysThatToo() async throws {
        let (phone, watch) = pocket()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        phone.onSharing = { _ in }

        #expect(await watch.send(.join(code)))
    }
}

/// Signals as they arrive, on the main actor where the store hands them over.
@MainActor
private final class Heard {
    private(set) var all: [SharingSignal] = []
    func append(_ signal: SharingSignal) { all.append(signal) }
}

/// Counts which way a payload went out, which is the whole question for a request that must
/// not outlive the moment it was made.
private final class CountingTransport: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { $0.finish() }
    let reachability = AsyncStream<Bool> { $0.finish() }
    private let lock = NSLock()
    private var liveCount = 0
    private var queuedCount = 0

    var live: Int { lock.withLock { liveCount } }
    var queued: Int { lock.withLock { queuedCount } }

    var isReachable: Bool { true }
    func activate() {}
    func forgetSnapshot() {}
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) { lock.withLock { queuedCount += 1 } }

    func sendLive(_ payload: Data) async -> Data? {
        lock.withLock { liveCount += 1 }
        return nil
    }
}
