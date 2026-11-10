import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// One phone on the far end of a link, saying what a test needs and keeping what it is told.
nonisolated private final class ScriptedGuest: PeerTransport, @unchecked Sendable {
    let inbound: AsyncStream<InboundPacket>
    let reachability = AsyncStream<Bool> { _ in }
    private let packets: AsyncStream<InboundPacket>.Continuation
    private let lock = NSLock()
    private var answers: [Wire] = []
    private var refused: Set<LinkID> = []
    let links: [LinkID]

    init(links: Int) {
        var continuation: AsyncStream<InboundPacket>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        packets = continuation
        self.links = (0 ..< links).map { _ in LinkID() }
    }

    var isReachable: Bool { true }
    func activate() {}
    func sendLive(_ payload: Data) async -> Data? { nil }
    func publishSnapshot(_ payload: Data) {}
    func queue(_ payload: Data) {}
    func refuse(_ link: LinkID) { lock.withLock { _ = refused.insert(link) } }

    var told: [Wire] { lock.withLock { answers } }
    func wasRefused(_ link: LinkID) -> Bool { lock.withLock { refused.contains(link) } }

    func say(_ wire: Wire, on link: LinkID) throws {
        packets.yield(InboundPacket(payload: try wire.encoded(), reply: { [weak self] data in
            guard let self, let answer = try? Wire.decode(data) else { return }
            self.lock.withLock { self.answers.append(answer) }
        }, link: link))
    }
}

@Suite("How many guests a match takes", .serialized)
@MainActor
struct CapacityTests {
    private let limit = Participants.limit

    private func hostingStore(over guests: ScriptedGuest) -> MatchStore {
        let links = FanOutTransport()
        links.attach(guests, as: .sharedSession)
        let store = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0, keepsHistory: false)
        store.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        store.startSharing()
        return store
    }

    @Test func aFullMatchTellsTheNextGuestThereIsNoRoom() async throws {
        let guests = ScriptedGuest(links: limit + 1)
        let store = hostingStore(over: guests)
        let run = Task { await store.run() }
        defer { run.cancel() }

        for link in guests.links {
            try guests.say(.hello(sessionID: store.log.sessionID, vector: VersionVector(), from: DeviceID()), on: link)
        }
        await eventually { guests.told.contains { if case .noRoom = $0 { true } else { false } } }
        let turnedAway = guests.told.count { if case .noRoom = $0 { true } else { false } }
        #expect(store.participants.all.count == limit)
        #expect(turnedAway == 1)
        #expect(guests.wasRefused(guests.links[limit]))
        #expect(!guests.wasRefused(guests.links[0]))
    }

    @Test func olderBuildsCountOneEachTowardsTheLimit() async throws {
        let guests = ScriptedGuest(links: limit + 1)
        let store = hostingStore(over: guests)
        let run = Task { await store.run() }
        defer { run.cancel() }

        for link in guests.links {
            try guests.say(.hello(sessionID: store.log.sessionID, vector: VersionVector()), on: link)
        }
        await eventually { guests.wasRefused(guests.links[limit]) }
        let allOlder = store.participants.all.allSatisfy(\.isOlderBuild)
        #expect(store.participants.all.count == limit)
        #expect(allOlder)
    }

    @Test func aWatchStandingInForAGuestAlreadyOnIsNotTurnedAway() async throws {
        let guests = ScriptedGuest(links: limit + 1)
        let store = hostingStore(over: guests)
        let run = Task { await store.run() }
        defer { run.cancel() }

        var phones: [DeviceID] = []
        for link in guests.links.prefix(limit) {
            let phone = DeviceID()
            phones.append(phone)
            try guests.say(.hello(sessionID: store.log.sessionID, vector: VersionVector(), from: phone), on: link)
        }
        let watch = DeviceID()
        try guests.say(.guestCard(GuestCard(device: watch, name: nil, pairedTo: phones[0])), on: guests.links[limit])
        try guests.say(.hello(sessionID: store.log.sessionID, vector: VersionVector(), from: watch), on: guests.links[limit])
        // Every one is answered, the watch's two included, whether or not there is room.
        await eventually { guests.told.count == limit + 2 }
        #expect(guests.told.count == limit + 2)
        #expect(store.participants.all.count == limit)
        #expect(!guests.wasRefused(guests.links[limit]))
    }

    @Test func oneGuestTooManyOverTheRadioIsToldWithinFifteenSecondsAndTheOthersCarryOn() async {
        let court = CourtHarness(guests: limit + 1, withWatches: false)
        court.startMatch()
        court.share()
        for guest in court.guests.dropLast() { court.join(guest) }
        await court.until(within: .seconds(120)) {
            court.guests.dropLast().allSatisfy { court.inStep($0.phone, with: court.host.phone) }
        }
        let oneTooMany = court.guests.last!
        court.join(oneTooMany)
        #expect(await court.until(within: .seconds(15)) { oneTooMany.phone.sharing.phase == .failed(.noRoom) })

        court.score(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) {
            court.guests.dropLast().allSatisfy { court.inStep($0.phone, with: court.host.phone) }
        })
    }
}
