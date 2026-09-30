import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Built the way `BluetoothTransport` is: one object that is a fan-out child and the
/// coordinator's radio at once, as `AppModel` wires it.
nonisolated private final class Radio: PeerTransport, @unchecked Sendable {
    let inbound = AsyncStream<InboundPacket> { _ in }
    var reachability: AsyncStream<Bool> { updates.stream() }
    private let updates = Broadcast<Bool>()
    private let lock = NSLock()
    private var peers = 0

    func present(_ count: Int) {
        lock.withLock { peers = count }
        updates.yield(count > 0)
    }

    var isReachable: Bool { lock.withLock { peers > 0 } }
    var reachableCount: Int { lock.withLock { peers } }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}
    func startHosting(code: SessionCode, share: UUID) {}
    func resumeHosting(code: SessionCode, share: UUID) {}
    func startJoining(code: SessionCode) {}
    func resumeJoining(code: SessionCode) {}
    func stop() {}
}

extension Radio: SharedLink {}

nonisolated private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Suite("One radio, two listeners")
@MainActor
struct OneRadioTests {
    @Test func everyListenerHearsEverything() async {
        let broadcast = Broadcast<Int>()
        let first = Tally(), second = Tally()
        let one = broadcast.stream(), two = broadcast.stream()
        let a = Task { for await _ in one { first.add() } }
        let b = Task { for await _ in two { second.add() } }
        defer { a.cancel(); b.cancel() }

        for value in 0 ..< 20 { broadcast.yield(value) }
        await eventually { first.count == 20 && second.count == 20 }
        #expect(first.count == 20)
        #expect(second.count == 20)
    }

    /// The fan-out's loop and the coordinator's used to share one stream, and each heard about
    /// half of what the radio said: the store missed the reconnects it should have said hello
    /// on, and the coordinator went on counting peers that had gone.
    @Test func theStoreAndTheCoordinatorBothHearTheRadio() async {
        let radio = Radio()
        let links = FanOutTransport()
        links.attach(radio, as: .sharedSession)
        let store = MatchStore(device: DeviceID(), transport: links)
        let sharing = SharedSession(store: store, link: LocalNetworkTransport(), bluetooth: radio)
        defer { sharing.close() }

        let heard = Tally()
        let changes = links.reachability
        let listening = Task { for await _ in changes { heard.add() } }
        defer { listening.cancel() }
        // Attaching says so once.
        await eventually { heard.count == 1 }

        for round in 0 ..< 12 {
            let count = round.isMultiple(of: 2) ? 1 : 0
            radio.present(count)
            await eventually { sharing.reachablePeers == count }
            #expect(sharing.reachablePeers == count)
        }
        await eventually { heard.count == 13 }
        #expect(heard.count == 13)
    }
}
