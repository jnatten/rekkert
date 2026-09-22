import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

/// Plain counting, for the tests that care how many taps landed rather than how they scored:
/// four points wins a game in traditional scoring and the count starts over.
private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(400))
}

/// One host and several guests, wired the way the local network will wire them: every guest
/// has exactly one link, to the host, and the host holds all of them behind a fan-out. Both
/// ends scope the link the way a stranger's phone is scoped in production.
@MainActor
private final class Star {
    let host: MatchStore
    private(set) var guests: [MatchStore] = []
    /// The host's end of each link, which is the end that decides whether the guest hears
    /// anything: dropping the guest's own end would only stop it talking, not listening.
    private(set) var links: [LoopbackTransport] = []
    private let fanOut = FanOutTransport()
    private var tasks: [Task<Void, Never>] = []

    init(guests count: Int) {
        host = MatchStore(device: DeviceID(), transport: fanOut, snapshotInterval: 0)
        for _ in 0 ..< count { addGuest() }
    }

    @discardableResult
    func addGuest() -> MatchStore {
        let (hostSide, guestSide) = LoopbackTransport.pair()
        fanOut.attach(hostSide, as: .sharedSession)

        let guestFanOut = FanOutTransport()
        guestFanOut.attach(guestSide, as: .sharedSession)
        let guest = MatchStore(device: DeviceID(), transport: guestFanOut, snapshotInterval: 0)

        links.append(hostSide)
        guests.append(guest)
        tasks.append(Task { await guest.run() })
        return guest
    }

    func run() -> [Task<Void, Never>] {
        tasks.append(Task { [host] in await host.run() })
        return tasks
    }

    var everyone: [MatchStore] { [host] + guests }

    /// Everyone is holding the host's session. The tests that go on to score need this to
    /// have happened first, and a fixed sleep only guesses that it has — under a loaded
    /// machine the guess is wrong and the failure looks like a lost point.
    func ready() async {
        await eventually { everyone.allSatisfy { points($0) != nil } }
    }
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    switch store.state {
    case .traditional(let session): session.score.points
    case .pointCount(let session): session.score.points
    default: nil
    }
}

@Suite("Several phones on one match")
@MainActor
struct StarTests {
    @Test func everyGuestTakesUpTheHostsSession() async throws {
        let star = Star(guests: 2)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(setup)
        star.host.tap(team: .a)
        await eventually { star.guests.allSatisfy { points($0) == BySide(a: 1, b: 0) } }

        for guest in star.guests {
            #expect(guest.log.sessionID == star.host.log.sessionID)
            #expect(points(guest) == BySide(a: 1, b: 0))
        }
    }

    /// The host is the only road between two guests, so a point scored on one has to be
    /// passed on rather than merged and forgotten.
    @Test func aPointOnOneGuestReachesTheOther() async throws {
        let star = Star(guests: 2)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(setup)
        await star.ready()

        star.guests[0].tap(team: .b)
        await eventually { points(star.guests[1]) == BySide(a: 0, b: 1) }

        #expect(points(star.host) == BySide(a: 0, b: 1), "the host saw it")
        #expect(points(star.guests[1]) == BySide(a: 0, b: 1), "and so did the other guest")
        #expect(star.guests[0].state == star.guests[1].state)
    }

    @Test func everybodyScoringAtOnceLosesNothing() async throws {
        let star = Star(guests: 3)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(counting)
        await star.ready()

        star.host.tap(team: .a)
        for guest in star.guests { guest.tap(team: .a) }
        await eventually { star.everyone.allSatisfy { points($0) == BySide(a: 4, b: 0) } }

        for store in star.everyone {
            #expect(points(store) == BySide(a: 4, b: 0), "four taps, four points, everywhere")
        }
    }

    @Test func aGuestThatDropsOutCatchesUpWhenItComesBack() async throws {
        let star = Star(guests: 2)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(counting)
        await star.ready()

        star.links[1].setReachable(false)
        for _ in 0 ..< 3 { star.guests[0].tap(team: .a) }
        // Anchored on the points reaching the host rather than on a stretch of time: it says
        // the three taps have been everywhere they can go while guest 1 is cut off.
        await eventually { points(star.host) == BySide(a: 3, b: 0) }
        #expect(points(star.guests[1]) == BySide(a: 0, b: 0), "still in the dark")

        star.links[1].setReachable(true)
        await eventually { points(star.guests[1]) == BySide(a: 3, b: 0) }
        #expect(points(star.guests[1]) == BySide(a: 3, b: 0), "and caught up on its own")
    }

    @Test func aPhoneJoiningLateSeesTheScoreAlready() async throws {
        let star = Star(guests: 1)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(counting)
        for _ in 0 ..< 5 { star.host.tap(team: .b) }
        await eventually { points(star.guests[0]) == BySide(a: 0, b: 5) }

        // A second phone arrives after the match has been going a while.
        let latecomer = star.addGuest()
        star.host.tap(team: .b)
        await eventually { points(latecomer) == BySide(a: 0, b: 6) }

        #expect(points(latecomer) == BySide(a: 0, b: 6), "the whole match, not just what came after")
    }

    /// Saved setups are last-writer-wins over the whole library, so letting a stranger's
    /// phone push one would delete the other's.
    @Test func savedSetupsNeverReachAnotherPersonsPhone() async throws {
        let star = Star(guests: 1)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.savePreset(Preset(name: "Thursday", configuration: .traditional(
            rules: TraditionalRules(), teams: BySide(a: .home, b: .away)
        )))
        star.guests[0].savePreset(Preset(name: "Mine", configuration: .winnerCourt(
            rules: WinnerCourtRules(), teams: BySide(a: .home, b: .away)
        )))
        // Nothing to wait *for* here — the point is that nothing arrives — so this one
        // genuinely has to sit out a stretch of time.
        try await settle()

        #expect(star.host.presets.presets.map(\.name) == ["Thursday"], "kept its own")
        #expect(star.guests[0].presets.presets.map(\.name) == ["Mine"], "and so did the guest")
    }

    /// Somebody else's phone has no business telling this wrist how hard to tap.
    @Test func howTheWatchBuzzesStaysPersonal() async throws {
        let star = Star(guests: 1)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(setup)
        await star.ready()

        star.host.setHaptics(mode: .byTeam, strength: .strong)
        // Nothing to wait for on the guest — the point is that it stays put — so the only
        // honest way to say "it did not travel" is to give it time to.
        try await settle()

        #expect(star.host.haptics.mode == .byTeam)
        #expect(star.guests[0].haptics.mode == .off, "the guest's wrist is its own business")
    }

    @Test func whichSideIsBlueStaysPersonal() async throws {
        let star = Star(guests: 1)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(setup)
        await star.ready()

        star.host.toggleTeamColors()
        // Nothing to wait for on the guest — the point is that the swap stays put — so the
        // only honest way to say "it did not travel" is to give it time to.
        try await settle()

        #expect(star.host.display.areColorsSwapped)
        #expect(star.guests[0].display.areColorsSwapped == false, "the guest draws it their own way")
    }
}

/// What survives a phone going into a pocket and coming back out of it.
///
/// `setReachable(false)` is a true blackout for a shared-session link rather than a pause:
/// that scope is not durable, so `queue` is filtered out by the fan-out and the snapshot
/// channel checks reachability before it publishes. Nothing is being held for later.
@Suite("Apart, and back together")
@MainActor
struct SplitBrainTests {
    @Test func bothSidesKeepWhatTheyScoredWhileApart() async throws {
        let star = Star(guests: 1)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(counting)
        await star.ready()

        star.links[0].setReachable(false)
        for _ in 0 ..< 2 { star.host.tap(team: .a) }
        for _ in 0 ..< 2 { star.guests[0].tap(team: .a) }
        await eventually {
            points(star.host) == BySide(a: 2, b: 0) && points(star.guests[0]) == BySide(a: 2, b: 0)
        }
        #expect(points(star.host) == BySide(a: 2, b: 0), "each of them scoring alone")
        #expect(points(star.guests[0]) == BySide(a: 2, b: 0))

        star.links[0].setReachable(true)
        // Both ends, not just the host: the guest needs the host's two taps back as much as
        // the host needs the guest's, and anchoring on one of them only asks half the question.
        await eventually {
            points(star.host) == BySide(a: 4, b: 0) && points(star.guests[0]) == BySide(a: 4, b: 0)
        }

        // Four taps happened and four points survive. Neither log is the authority, and
        // neither needs to be: the union is what both of them come to.
        #expect(points(star.host) == BySide(a: 4, b: 0), "nobody's points were thrown away")
        #expect(points(star.guests[0]) == BySide(a: 4, b: 0))
        #expect(star.host.state == star.guests[0].state)
    }

    /// A guest coming back is not a guest arriving. If the reconnect were read as a fresh
    /// join, the match on screen would be filed away to History and handed back as somebody
    /// else's — which is the loud version of losing the score.
    @Test func aReconnectingGuestIsNotHandedTheMatchAsANewOne() async throws {
        let star = Star(guests: 1)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(counting)
        await star.ready()
        let session = star.guests[0].log.sessionID

        star.links[0].setReachable(false)
        star.guests[0].tap(team: .b)
        star.host.tap(team: .a)
        try await settle()
        star.links[0].setReachable(true)
        await eventually { points(star.guests[0]) == BySide(a: 1, b: 1) }

        #expect(star.guests[0].log.sessionID == session, "the same match it was already on")
        #expect(star.guests[0].replacedSessionTitle == nil, "nothing was archived behind them")
    }

    @Test func aGuestThatComesBackDoesNotEndTheMatchForAnybody() async throws {
        let star = Star(guests: 2)
        let tasks = star.run()
        defer { tasks.forEach { $0.cancel() } }

        star.host.configure(counting)
        await star.ready()

        star.links[0].setReachable(false)
        star.guests[0].tap(team: .a)
        star.host.tap(team: .b)
        try await settle()
        star.links[0].setReachable(true)
        await eventually { points(star.guests[0]) == BySide(a: 1, b: 1) }

        for store in star.everyone {
            #expect(store.state != nil, "still in play")
            #expect(store.lastResult == nil, "nobody was shown a result")
        }
    }
}
