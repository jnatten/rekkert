import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// A phone on the other end of one link, made to say whatever a test needs.
nonisolated private final class ScriptedPhone: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability = AsyncStream<Bool> { _ in }
    private let packets: AsyncStream<InboundPacket>.Continuation
    let link = LinkID()

    init() {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
    }

    var isReachable: Bool { true }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}

    func say(_ wire: Wire) throws {
        packets.yield(InboundPacket(payload: try wire.encoded(), link: link))
    }
}

@Suite("Link identity")
@MainActor
struct LinkIdentityTests {
    private func hostingStore(over phone: ScriptedPhone) -> MatchStore {
        let links = FanOutTransport()
        links.attach(phone, as: .sharedSession)
        let store = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0, keepsHistory: false)
        store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        store.startSharing()
        return store
    }

    @Test func aHelloThatNamesNobodyIsOneGuestOnAnOlderBuild() async throws {
        let phone = ScriptedPhone()
        let store = hostingStore(over: phone)
        let run = Task { await store.run() }
        defer { run.cancel() }

        try phone.say(.hello(sessionID: store.log.sessionID, vector: VersionVector()))
        try phone.say(.hello(sessionID: store.log.sessionID, vector: VersionVector()))
        await eventually { store.participants.all.count == 1 }
        #expect(store.participants.all.count == 1)
        #expect(store.participants.all.first?.isOlderBuild == true)
    }

    @Test func whatFollowsAHelloOnTheSameLinkIsPutDownToTheSameGuest() async throws {
        let phone = ScriptedPhone()
        let store = hostingStore(over: phone)
        let run = Task { await store.run() }
        defer { run.cancel() }

        let guest = DeviceID()
        try phone.say(.hello(sessionID: store.log.sessionID, vector: VersionVector(), from: guest))
        try phone.say(.guestCard(GuestCard(device: guest, name: "Ada")))
        await eventually { store.participants.all.first?.name == "Ada" }
        #expect(store.participants.all.map(\.id) == [guest])
        #expect(store.participants.all.first?.isOlderBuild == false)
    }
}
