import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let traditional = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

/// Won on the second point, so a test can get to the end of a match in two taps.
private let shortMatch = SessionSetup.pointCount(
    rules: PointCountRules(target: 2),
    teams: BySide(a: .home, b: .away)
)

private func seeded(_ device: DeviceID, _ setup: SessionSetup = traditional) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(setup), from: device)
    return log
}

/// Everything a store said about matches, in the order it said it.
@MainActor
private final class Moments {
    private(set) var said: [MatchMoment] = []

    init(_ store: MatchStore) {
        store.onMatch = { [weak self] in self?.said.append($0) }
    }

    var began: [UUID] { said.compactMap { if case .began(let id) = $0 { id } else { nil } } }
    var inPlay: [UUID] { said.compactMap { if case .inPlay(let id) = $0 { id } else { nil } } }
    var ended: [UUID] { said.compactMap { if case .ended(let id) = $0 { id } else { nil } } }
}

/// A phone and its watch.
@MainActor
private struct Pair {
    let phone: MatchStore
    let watch: MatchStore
    let phoneLink: LoopbackTransport
    let watchLink: LoopbackTransport
    let onPhone: Moments
    let onWatch: Moments

    init() {
        (phoneLink, watchLink) = LoopbackTransport.pair()
        phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0, keepsHistory: false)
        onPhone = Moments(phone)
        onWatch = Moments(watch)
    }

    func run() -> [Task<Void, Never>] {
        [Task { [phone] in await phone.run() }, Task { [watch] in await watch.run() }]
    }

    func apart() {
        phoneLink.setReachable(false)
        watchLink.setReachable(false)
    }

    func together() {
        phoneLink.setReachable(true)
        watchLink.setReachable(true)
    }
}

/// A host, and a guest's phone with its watch on it.
@MainActor
private struct Court {
    let host: MatchStore
    let phone: MatchStore
    let watch: MatchStore
    let onHost: Moments
    let onPhone: Moments
    let onWatch: Moments

    init() {
        let hostDevice = DeviceID()
        let (hostSide, phoneSide) = LoopbackTransport.pair()
        let (phoneToWatch, watchSide) = LoopbackTransport.pair()
        host = MatchStore(
            device: hostDevice, transport: hostSide,
            session: ActiveSession(log: seeded(hostDevice), role: .host),
            snapshotInterval: 0
        )
        let phoneLinks = FanOutTransport()
        phoneLinks.attach(phoneSide, as: .sharedSession)
        phoneLinks.attach(phoneToWatch, as: .pairedDevice)
        phone = MatchStore(device: DeviceID(), transport: phoneLinks, snapshotInterval: 0)
        watch = MatchStore(device: DeviceID(), transport: watchSide, snapshotInterval: 0, keepsHistory: false)
        onHost = Moments(host)
        onPhone = Moments(phone)
        onWatch = Moments(watch)
    }

    func run() -> [Task<Void, Never>] {
        [host, phone, watch].map { store in Task { await store.run() } }
    }

    func joined() -> Bool {
        phone.role == .guest && watch.log.sessionID == host.log.sessionID && !watch.canEndSession
    }
}

@Suite("A match beginning and ending", .serialized)
@MainActor
struct MatchMomentTests {
    @Test func aMatchStartedHereBeganHereAndIsOnlyInPlayOnThePair() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(traditional)
        let match = pair.phone.log.sessionID
        await eventually { inStep(pair.phone, pair.watch) }
        await quietPeriod()

        #expect(pair.onPhone.said == [.inPlay(match), .began(match)])
        #expect(pair.onWatch.said == [.inPlay(match)], "the watch did not start it")
    }

    @Test func pointsAndRoundsBeginAndEndNothing() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(.friendly(FriendlySession(
            name: "Thursday",
            rules: TraditionalRules(setsToWin: 1, gamesPerSet: 6),
            players: (0 ..< 4).map { Player(name: "P\($0)") }
        )))
        pair.phone.nextRound()
        for _ in 0 ..< 3 { pair.phone.tap(team: .a) }
        pair.phone.endRound()
        pair.phone.nextRound()
        await eventually { inStep(pair.phone, pair.watch) }
        pair.watch.tap(round: 1, court: 0, team: .b)
        await eventually { inStep(pair.phone, pair.watch) }
        await quietPeriod()

        #expect(pair.onPhone.began.count == 1)
        #expect(pair.onPhone.ended.isEmpty)
        #expect(pair.onWatch.began.isEmpty)
        #expect(pair.onWatch.ended.isEmpty)
        #expect(pair.onWatch.inPlay.count == 1)
    }

    @Test func aMatchStartedOverAnotherIsNoEnding() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(traditional)
        let first = pair.phone.log.sessionID
        pair.phone.tap(team: .a)
        await eventually { inStep(pair.phone, pair.watch) }

        pair.phone.start(Preset(name: "Best of 3", configuration: .traditional(
            rules: TraditionalRules(), teams: BySide(a: .home, b: .away)
        )))
        let second = pair.phone.log.sessionID
        await eventually { inStep(pair.phone, pair.watch) }

        #expect(pair.onPhone.ended.isEmpty, "the phone moved on rather than finishing anything")
        #expect(pair.onPhone.began == [first, second])
        #expect(pair.onWatch.inPlay.last == second)
    }

    @Test func winningFinishingAndCallingOffEachEndTheMatchOnBothDevices() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(shortMatch)
        let won = pair.phone.log.sessionID
        pair.phone.tap(team: .a)
        await eventually { inStep(pair.phone, pair.watch) }
        pair.watch.tap(team: .a)
        await eventually { pair.onPhone.ended == [won] && pair.onWatch.ended == [won] }
        #expect(pair.onPhone.ended == [won])
        #expect(pair.onWatch.ended == [won])

        pair.phone.startNewSession()
        pair.phone.configure(traditional)
        let finished = pair.phone.log.sessionID
        pair.phone.tap(team: .b)
        await eventually { inStep(pair.phone, pair.watch) }
        pair.watch.finish()
        await eventually { pair.onPhone.ended.last == finished && pair.onWatch.ended.last == finished }
        #expect(pair.onPhone.ended == [won, finished])
        #expect(pair.onWatch.ended == [won, finished])

        pair.phone.startNewSession()
        pair.phone.configure(traditional)
        let calledOff = pair.phone.log.sessionID
        await eventually { inStep(pair.phone, pair.watch) }
        pair.phone.discardSession()
        await eventually { pair.onPhone.ended.last == calledOff && pair.onWatch.ended.last == calledOff }
        #expect(pair.onPhone.ended == [won, finished, calledOff])
        #expect(pair.onWatch.ended == [won, finished, calledOff])
    }

    /// Out of reach the ending goes by the durable queue, which is how a watch with a workout
    /// running hears a match finished on a phone left at the side of the court.
    @Test func anEndingMadeWhileApartStillEndsTheMatchOnTheWatch() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(traditional)
        let match = pair.phone.log.sessionID
        await eventually { inStep(pair.phone, pair.watch) }
        await drain(pair.phone, pair.watch)
        pair.apart()

        pair.phone.finish()
        #expect(pair.onPhone.ended == [match])

        await eventually { pair.onWatch.ended == [match] }
        #expect(pair.onWatch.ended == [match])
    }

    @Test func aFarewellLandingOnNothingEndsNothing() async throws {
        let pair = Pair()
        pair.apart()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(shortMatch)
        pair.phone.tap(team: .a)
        pair.phone.tap(team: .a)
        #expect(pair.onPhone.ended.count == 1)

        pair.together()
        await pair.watch.synchronise()
        await quietPeriod()
        #expect(pair.onWatch.ended.isEmpty, "the watch never had it on")
    }

    @Test func aResumedMatchBeganAndATakenBackOneDidNot() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        pair.phone.configure(shortMatch)
        let won = pair.phone.log.sessionID
        pair.phone.tap(team: .a)
        pair.phone.tap(team: .a)
        #expect(pair.phone.resultRewind != nil)

        pair.phone.undoResult()
        let reopened = pair.phone.log.sessionID
        #expect(reopened != won)
        #expect(pair.onPhone.said == [.inPlay(won), .began(won), .ended(won), .inPlay(reopened)], "back to it, not a new match")

        pair.phone.finish()
        let result = try #require(pair.phone.lastResult)
        pair.phone.resume(result)
        let resumed = pair.phone.log.sessionID
        #expect(pair.onPhone.began == [won, resumed], "picking it back up from History is starting it again")
    }

    @Test func aJoinBeganOnTheDeviceThatJoinedAndLeavingEndsItForThePair() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        court.phone.beginJoining()
        await eventually { court.joined() }
        let match = court.host.log.sessionID
        await quietPeriod()

        #expect(court.onPhone.began == [match], "once")
        #expect(court.onWatch.began.isEmpty)
        #expect(court.onWatch.inPlay == [match])

        court.phone.leaveSharedSession()
        await eventually { court.onWatch.ended == [match] }
        #expect(court.onPhone.ended == [match])
        #expect(court.onWatch.ended == [match], "the watch stepped off with it")
        #expect(court.onHost.ended.isEmpty, "and the host plays on")
    }

    @Test func aJoinCarriedOutForTheWatchIsNotBegunOnThePhone() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        court.phone.beginJoining(forThePair: true)
        await eventually { court.joined() }
        await quietPeriod()

        #expect(court.onPhone.began.isEmpty)
        #expect(court.onPhone.inPlay == [court.host.log.sessionID])
    }

    @Test func theHostsNextMatchBeginsForItsGuest() async throws {
        let court = Court()
        let tasks = court.run()
        defer { tasks.forEach { $0.cancel() } }
        await quietPeriod()

        court.phone.beginJoining()
        await eventually { court.joined() }
        let first = court.host.log.sessionID

        court.host.finish()
        await eventually { court.onPhone.ended == [first] && court.onWatch.ended == [first] }
        #expect(court.onWatch.ended == [first], "the guest's watch hears the host end it")

        court.host.startNewSession()
        court.host.configure(traditional)
        let next = court.host.log.sessionID
        await eventually { court.phone.log.sessionID == next && court.watch.log.sessionID == next }
        await quietPeriod()

        #expect(court.onPhone.began == [first, next], "the code lasts the evening")
        #expect(court.onWatch.began.isEmpty, "and the phone is the one that joined")
    }
}
