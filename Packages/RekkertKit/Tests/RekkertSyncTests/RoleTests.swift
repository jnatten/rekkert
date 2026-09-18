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

/// A session that already exists before anybody is connected, so the two devices are not
/// quietly negotiating one into being while the test is still setting up.
private func seeded(
    _ device: DeviceID,
    startedAt: Date,
    points: Int = 0,
    for team: TeamSide = .a
) -> MatchLog {
    var log = MatchLog(createdAt: startedAt)
    log.append(.configure(setup), from: device)
    for _ in 0 ..< points { log.append(.point(round: 0, court: 0, team: team), from: device) }
    return log
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .traditional(let session) = store.state else { return nil }
    return session.score.points
}

@Suite("Who holds the whistle")
@MainActor
struct RoleTests {
    @Test func aGuestScoresButDoesNotEndTheMatch() async throws {
        let device = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let host = MatchStore(
            device: device, transport: one,
            session: ActiveSession(log: seeded(device, startedAt: .now, points: 1), role: .host),
            snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: two, snapshotInterval: 0)
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        // Both run loops have to be consuming before anybody asks anything of the other.
        try await settle()

        guest.beginJoining()
        await eventually { guest.role == .guest }
        #expect(guest.role == .guest, "it was handed the session it asked for")
        #expect(points(guest) == BySide(a: 1, b: 0))

        guest.tap(team: .b)
        await eventually { points(host) == BySide(a: 1, b: 1) }
        #expect(points(host) == BySide(a: 1, b: 1), "scoring is everybody's")

        guest.finish()
        guest.discardSession()
        try await settle()

        #expect(guest.canEndSession == false)
        #expect(host.state != nil, "and ending is not")
        #expect(guest.state != nil)
    }

    @Test func aGuestsWatchDoesNotOfferToEndItEither() async throws {
        let hostDevice = DeviceID()
        let (hostSide, phoneSide) = LoopbackTransport.pair()
        let (phoneToWatch, watchSide) = LoopbackTransport.pair()

        let host = MatchStore(
            device: hostDevice, transport: hostSide,
            session: ActiveSession(log: seeded(hostDevice, startedAt: .now), role: .host),
            snapshotInterval: 0
        )

        // The guest's phone talks to two counterparts at once: the host, and its own watch.
        let phoneLinks = FanOutTransport()
        phoneLinks.attach(phoneSide, as: .sharedSession)
        phoneLinks.attach(phoneToWatch, as: .pairedDevice)
        let phone = MatchStore(device: DeviceID(), transport: phoneLinks, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: watchSide, snapshotInterval: 0)

        let tasks = [host, phone, watch].map { store in Task { await store.run() } }
        defer { tasks.forEach { $0.cancel() } }

        #expect(watch.canEndSession, "a watch holds the whistle until it is told otherwise")

        phone.beginJoining()
        await eventually { phone.role == .guest && !watch.canEndSession }

        #expect(phone.role == .guest)
        #expect(phone.canEndSession == false)
        #expect(watch.canEndSession == false, "and its watch stands down with it")
    }

    @Test func aHostIsNotTakenOverByANewerSession() async throws {
        let hostDevice = DeviceID()
        let otherDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()

        let host = MatchStore(
            device: hostDevice, transport: one,
            session: ActiveSession(
                log: seeded(hostDevice, startedAt: .now.addingTimeInterval(-600), points: 1),
                role: .host
            ),
            snapshotInterval: 0
        )
        // Somebody else's match, started a moment ago, which would win on the clock alone.
        let newcomer = MatchStore(
            device: otherDevice, transport: two,
            session: ActiveSession(log: seeded(otherDevice, startedAt: .now, points: 2, for: .b)),
            snapshotInterval: 0
        )
        let tasks = [Task { await host.run() }, Task { await newcomer.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()
        try await settle()

        #expect(host.role == .host)
        #expect(points(host) == BySide(a: 1, b: 0), "the court's match, untouched")
    }

    @Test func joiningTakesTheSessionItWasOfferedEvenIfOursIsNewer() async throws {
        let hostDevice = DeviceID()
        let joinerDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()

        let host = MatchStore(
            device: hostDevice, transport: one,
            session: ActiveSession(
                log: seeded(hostDevice, startedAt: .now.addingTimeInterval(-600), points: 1),
                role: .host
            ),
            snapshotInterval: 0
        )
        let joiner = MatchStore(
            device: joinerDevice, transport: two,
            session: ActiveSession(log: seeded(joinerDevice, startedAt: .now, points: 2, for: .b)),
            snapshotInterval: 0
        )
        let tasks = [Task { await host.run() }, Task { await joiner.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        joiner.beginJoining()
        await eventually { joiner.role == .guest }

        #expect(joiner.role == .guest)
        #expect(joiner.log.sessionID == host.log.sessionID)
        #expect(points(joiner) == BySide(a: 1, b: 0), "the host's score, not the one it brought")
    }

    /// Leaving must not retire the session id. Retiring is how a device says a match is over,
    /// so a guest that left would refuse it on the way back in — and end it for the host.
    @Test func leavingDoesNotEndTheMatchAndRejoiningWorks() async throws {
        let hostDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let host = MatchStore(
            device: hostDevice, transport: one,
            session: ActiveSession(log: seeded(hostDevice, startedAt: .now, points: 1), role: .host),
            snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: two, snapshotInterval: 0)
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        // Both run loops have to be consuming before anybody asks anything of the other.
        try await settle()

        guest.beginJoining()
        await eventually { guest.role == .guest }
        #expect(guest.role == .guest)

        guest.leaveSharedSession()
        await eventually { guest.state == nil }

        #expect(guest.state == nil, "stepped off")
        #expect(guest.role == .solo)
        #expect(host.state != nil, "and the host is still playing")

        guest.beginJoining()
        await eventually { guest.log.sessionID == host.log.sessionID }
        #expect(guest.log.sessionID == host.log.sessionID, "and can walk back in")
    }

    /// The link is not always cut the moment somebody steps off — the button may not reach the
    /// coordinator, or the cut lands a moment later — and a snapshot arriving in between used
    /// to hand the match straight back, to a phone that now held the whistle.
    @Test func leavingWhileStillConnectedDoesNotHandTheMatchBack() async throws {
        let hostDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let hostFan = FanOutTransport()
        hostFan.attach(one, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(two, as: .sharedSession)
        let host = MatchStore(
            device: hostDevice, transport: hostFan,
            session: ActiveSession(log: seeded(hostDevice, startedAt: .now, points: 1), role: .host),
            snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        guest.beginJoining()
        await eventually { guest.role == .guest }
        #expect(guest.role == .guest)

        guest.leaveSharedSession()
        await eventually { guest.state == nil }

        host.tap(team: .b)
        await eventually { points(host) == BySide(a: 1, b: 1) }
        try await settle()

        #expect(guest.state == nil, "left means left")
        #expect(guest.canEndSession, "with nothing on it, this phone is nobody's guest")
        #expect(points(host) == BySide(a: 1, b: 1), "and the host plays on")
    }

    @Test func theRoleSurvivesARelaunch() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionStore(directory: directory)

        let first = MatchStore(
            device: DeviceID(), transport: LoopbackTransport(),
            store: persistence, snapshotInterval: 0
        )
        first.startSharing()
        first.configure(setup)

        let again = MatchStore(
            device: DeviceID(), transport: LoopbackTransport(),
            store: persistence, session: try persistence.loadActive(), snapshotInterval: 0
        )
        #expect(again.role == .host, "still hosting after being relaunched")
    }

    @Test func aStoredSessionFromBeforeRolesExistedIsNobodysGuest() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacy = #"{"log":{"sessionID":"11111111-0000-0000-0000-000000000000","createdAt":0,"events":[]},"outbox":{"pending":[]}}"#
        try Data(legacy.utf8).write(to: directory.appending(path: "active.json"))

        let session = try #require(try SessionStore(directory: directory).loadActive())
        #expect(session.role == .solo, "which is exactly how it behaved before")
    }

    /// Starting something of your own on a match that belongs to somebody else used to retire
    /// it, and the host's next packet was answered "this ended here" — which ended it for all.
    @Test func aGuestStartingItsOwnMatchDoesNotEndTheHosts() async throws {
        let hostDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let hostFan = FanOutTransport()
        hostFan.attach(one, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(two, as: .sharedSession)
        let host = MatchStore(
            device: hostDevice, transport: hostFan,
            session: ActiveSession(log: seeded(hostDevice, startedAt: .now, points: 1), role: .host),
            snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        var letGo = false
        guest.onLeft = { letGo = true }
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        guest.beginJoining()
        await eventually { guest.role == .guest }
        #expect(guest.role == .guest)

        guest.startNewSession()
        guest.configure(setup)
        host.tap(team: .b)
        await eventually { points(host) == BySide(a: 1, b: 1) }
        try await settle()

        #expect(points(host) == BySide(a: 1, b: 1), "the host plays on")
        #expect(host.lastResult == nil, "and was shown no result")
        #expect(guest.role == .solo)
        #expect(points(guest) == BySide(a: 0, b: 0), "on a match of its own")
        #expect(letGo, "and the link to the host was let go of")
    }

    /// The way back from the result screen makes a fresh session, and used to make whoever took
    /// it solo on it — a guest then held the whistle on a match the host went on to take up.
    @Test func aGuestTakingBackAResultIsStillAGuest() async throws {
        let hostDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let hostFan = FanOutTransport()
        hostFan.attach(one, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(two, as: .sharedSession)
        let host = MatchStore(
            device: hostDevice, transport: hostFan,
            session: ActiveSession(log: seeded(hostDevice, startedAt: .now, points: 1), role: .host),
            snapshotInterval: 0
        )
        let guest = MatchStore(device: DeviceID(), transport: guestFan, snapshotInterval: 0)
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        guest.beginJoining()
        await eventually { guest.role == .guest }

        host.finish()
        await eventually { guest.lastResult != nil && host.state == nil }
        #expect(guest.resultRewind != nil)

        guest.undoResult()
        await eventually { host.state != nil }

        #expect(guest.role == .guest, "still somebody else's match")
        #expect(guest.canEndSession == false)
        #expect(host.role == .host)
        #expect(host.log.sessionID == guest.log.sessionID, "which the host took up again")
    }

    /// A guest out of reach when the host called the match off used to be told only that it
    /// had ended, and filed a result for a match nobody wanted kept.
    @Test func aGuestThatMissedACancelledEndingDoesNotKeepIt() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "rekkert-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = SessionStore(directory: directory)

        let hostDevice = DeviceID()
        let (one, two) = LoopbackTransport.pair()
        let hostFan = FanOutTransport()
        hostFan.attach(one, as: .sharedSession)
        let guestFan = FanOutTransport()
        guestFan.attach(two, as: .sharedSession)
        let host = MatchStore(
            device: hostDevice, transport: hostFan,
            session: ActiveSession(log: seeded(hostDevice, startedAt: .now, points: 1), role: .host),
            snapshotInterval: 0, keepsHistory: false
        )
        let guest = MatchStore(device: DeviceID(), transport: guestFan, store: persistence, snapshotInterval: 0)
        let tasks = [Task { await host.run() }, Task { await guest.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        guest.beginJoining()
        await eventually { guest.role == .guest && points(guest) == BySide(a: 1, b: 0) }

        one.setReachable(false)
        two.setReachable(false)
        host.discardSession()
        await eventually { host.state == nil }
        try await settle()
        #expect(guest.state != nil, "out of reach, the guest heard nothing")

        one.setReachable(true)
        two.setReachable(true)
        await eventually { guest.state == nil }

        #expect(guest.state == nil, "told on reconnect that it ended")
        #expect(guest.lastResult == nil, "and that it was called off")
        let history = try persistence.history()
        #expect(history.isEmpty, "so nothing was filed for it")
    }
}
