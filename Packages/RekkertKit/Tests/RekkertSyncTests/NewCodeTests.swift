import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

/// The guest's link to whichever host it dials: up between a join and a stop, as a dialled
/// central or a Bonjour connection is. Both a fan-out child and the coordinator's radio, like
/// `BluetoothTransport`.
nonisolated private final class DialledLink: PeerTransport, @unchecked Sendable {
    let end: LoopbackTransport
    private let updates = Broadcast<Bool>()
    private let lock = NSLock()
    private var up = false
    private var sharing: SessionCode?

    init(_ end: LoopbackTransport) {
        self.end = end
        end.setReachable(false)
    }

    /// Which code the host at the other end shares on. A dial for any other finds nothing.
    func host(on code: SessionCode?) { lock.withLock { sharing = code } }

    var inbound: AsyncStream<InboundPacket> { end.inbound }
    var reachability: AsyncStream<Bool> { updates.stream() }
    var isReachable: Bool { lock.withLock { up } && end.isReachable }
    var reachableCount: Int { isReachable ? 1 : 0 }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { isReachable ? await end.sendLive(payload) : nil }
    func publishSnapshot(_ payload: Data) { if isReachable { end.publishSnapshot(payload) } }
    func queue(_ payload: Data) {}

    func startHosting(code: SessionCode, share: UUID) {}
    func resumeHosting(code: SessionCode, share: UUID) {}
    func resumeJoining(code: SessionCode) {}
    func startJoining(code: SessionCode) {
        let reaches = lock.withLock { () -> Bool in
            up = code == sharing
            return up
        }
        end.setReachable(reaches)
        updates.yield(reaches)
    }

    func stop() {
        lock.withLock { up = false }
        end.setReachable(false)
        updates.yield(false)
    }

    /// The host's app went, and the code with it.
    func hostWent() {
        lock.withLock { up = false; sharing = nil }
        end.setReachable(false)
        updates.yield(false)
    }
}

extension DialledLink: SharedLink {}

@Suite("A match shared again on a new code", .serialized)
@MainActor
struct NewCodeTests {
    private struct Court {
        let host: MatchStore
        let guest: MatchStore
        let hostEnd: LoopbackTransport
        let radio: DialledLink
        let sharing: SharedSession
        let tasks: [Task<Void, Never>]
    }

    private func court(on code: SessionCode) async -> Court {
        let (hostEnd, guestEnd) = LoopbackTransport.pair()
        hostEnd.setReachable(false)
        let hostFan = FanOutTransport()
        hostFan.attach(hostEnd, as: .sharedSession)
        let radio = DialledLink(guestEnd)
        let guestFan = FanOutTransport()
        guestFan.attach(radio, as: .sharedSession)

        var log = MatchLog()
        let hostDevice = DeviceID()
        log.append(.configure(counting), from: hostDevice)
        log.append(.point(round: 0, court: 0, team: .a), from: hostDevice)
        let host = MatchStore(
            device: hostDevice, transport: hostFan, session: ActiveSession(log: log, role: .host), snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        let sharing = SharedSession(store: guest, link: LocalNetworkTransport(), bluetooth: radio)
        let tasks = [Task { await host.run() }, Task { await guest.run() }]

        radio.host(on: code)
        hostEnd.setReachable(true)
        sharing.join(code)
        await eventually { guest.role == .guest && !guest.isJoining && inStep(host, guest) }
        return Court(host: host, guest: guest, hostEnd: hostEnd, radio: radio, sharing: sharing, tasks: tasks)
    }

    /// The host's app was relaunched, and the match shared again on a code of its own. The guest,
    /// still looking for the old one, typed the new code — and the join waited for ever on the
    /// match already on screen, refused as the one being walked away from. Leaving to get in
    /// threw away what it had scored meanwhile.
    @Test func aGuestTypesTheNewCodeAndKeepsWhatItScoredMeanwhile() async throws {
        let first = try #require(SessionCode("482915"))
        let court = await court(on: first)
        defer { court.sharing.close(); court.tasks.forEach { $0.cancel() } }
        #expect(court.guest.role == .guest)

        court.radio.hostWent()
        court.hostEnd.setReachable(false)
        await quietPeriod()
        court.guest.tap(team: .b)
        court.guest.tap(team: .b)
        let scoredMeanwhile = Set(court.guest.log.events.keys.filter { $0.device == court.guest.device })

        let second = try #require(SessionCode("730264"))
        court.radio.host(on: second)
        court.hostEnd.setReachable(true)
        court.sharing.join(second)
        await eventually { !court.guest.isJoining && inStep(court.host, court.guest) }

        #expect(!court.guest.isJoining, "the join lands")
        #expect(inStep(court.host, court.guest))
        #expect(court.guest.role == .guest)
        #expect(scoredMeanwhile.isSubset(of: Set(court.host.log.events.keys)), "with what the guest scored while apart")
    }

    /// Still in reach of its host and given a different code, a guest is walking away from that
    /// match: whatever its host still sends is not the answer to the new join.
    @Test func aGuestStillInReachOfItsHostWalksAwayFromThatMatch() async throws {
        let first = try #require(SessionCode("482915"))
        let court = await court(on: first)
        defer { court.sharing.close(); court.tasks.forEach { $0.cancel() } }
        #expect(court.sharing.reachablePeers == 1)

        court.sharing.join(try #require(SessionCode("730264")))
        court.hostEnd.queue(try Wire.snapshot(court.host.log).encoded())
        await quietPeriod()

        #expect(court.guest.isJoining, "the old host's match, still in flight, is not what was asked for")
    }
}
