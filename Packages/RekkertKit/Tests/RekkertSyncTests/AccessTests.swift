import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let winnerCourt = SessionSetup.winnerCourt(rules: WinnerCourtRules(), teams: BySide(a: .home, b: .away))

private let americano = SessionSetup.tournament(Tournament(
    name: "Thursday", format: .americano,
    players: ["Ada", "Bob", "Cy", "Di"].map { Player(name: $0) },
    config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
))

@MainActor
private final class Court {
    let host: MatchStore
    let phone: MatchStore
    let watch: MatchStore
    private var tasks: [Task<Void, Never>] = []

    init(_ setup: SessionSetup, guestStore: SessionStore? = nil) {
        let hostDevice = DeviceID()
        var log = MatchLog()
        log.append(.configure(setup), from: hostDevice)

        let (hostToPhone, phoneToHost) = LoopbackTransport.pair()
        let (phoneToWatch, watchToPhone) = LoopbackTransport.pair()

        let hostFan = FanOutTransport()
        hostFan.attach(hostToPhone, as: .sharedSession)
        host = MatchStore(device: hostDevice, transport: hostFan, session: ActiveSession(log: log), snapshotInterval: 0)

        let phoneFan = FanOutTransport()
        phoneFan.attach(phoneToWatch, as: .pairedDevice)
        phoneFan.attach(phoneToHost, as: .sharedSession)
        phone = MatchStore(device: DeviceID(), transport: phoneFan, store: guestStore, snapshotInterval: 0)

        let watchFan = FanOutTransport()
        watchFan.attach(watchToPhone, as: .pairedDevice)
        watch = MatchStore(device: DeviceID(), transport: watchFan, snapshotInterval: 0, keepsHistory: false)
    }

    func open(default access: ShareAccess = .full) async {
        tasks = [host, phone, watch].map { store in Task { await store.run() } }
        await quietPeriod()
        host.setDefaultAccess(access)
        host.startSharing()
        phone.beginJoining()
        await eventually { phone.role == .guest && phone.accessTable != nil && !watch.canEndSession }
    }

    func close() {
        tasks.forEach { $0.cancel() }
    }
}

private func games(_ store: MatchStore) -> BySide<Int>? {
    guard case .winnerCourt(let session) = store.state else { return nil }
    return session.score.points
}

@Suite("What a guest may do", .serialized)
@MainActor
struct AccessTests {
    @Test func aGuestJoinsAtTheHostsDefault() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }

        await eventually { court.watch.access == .readOnly }
        #expect(court.phone.access == .readOnly)
        #expect(court.watch.access == .readOnly, "its watch goes by what its phone was told")
        #expect(court.host.access == .full, "the host can do everything on its own match")
    }

    @Test func aReadOnlyGuestScoresNothing() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }
        await eventually { court.watch.access == .readOnly }

        court.host.tap(team: .a)
        await eventually { games(court.phone) == BySide(a: 1, b: 0) }

        court.phone.tap(team: .b)
        court.phone.setScore(court: 0, points: BySide(a: 3, b: 3))
        court.phone.undoLast()
        court.watch.tap(team: .b)
        await quietPeriod()

        #expect(!court.phone.canScore)
        #expect(!court.phone.canUndo)
        #expect(games(court.phone) == BySide(a: 1, b: 0))
        #expect(games(court.host) == BySide(a: 1, b: 0))
    }

    @Test func aScorerScoresButDoesNotBlowTheWhistle() async {
        let court = Court(winnerCourt)
        await court.open(default: .score)
        defer { court.close() }

        court.phone.tap(team: .b)
        await eventually { games(court.host) == BySide(a: 0, b: 1) }
        #expect(games(court.host) == BySide(a: 0, b: 1), "scoring is allowed")
        #expect(court.phone.canUndo, "and so is taking a point back")

        court.phone.endRound()
        await quietPeriod()
        guard case .winnerCourt(let session) = court.host.state else { Issue.record("no match"); return }
        #expect(session.completedRounds.isEmpty, "the whistle is not")

        court.host.endRound()
        await eventually {
            if case .winnerCourt(let session) = court.phone.state { !session.completedRounds.isEmpty } else { false }
        }
        #expect(!court.phone.canUndo, "nor is taking the host's whistle back")
        #expect(court.host.canUndo)
    }

    @Test func theHostChangesItsMindAndTheGuestFollows() async {
        let court = Court(winnerCourt)
        await court.open()
        defer { court.close() }
        #expect(court.phone.access == .full)

        court.host.setAccess(.readOnly, for: court.phone.device)
        await eventually { court.phone.access == .readOnly && court.watch.access == .readOnly }
        #expect(court.phone.access == .readOnly)
        #expect(court.watch.access == .readOnly)

        court.host.setDefaultAccess(.score)
        await quietPeriod()
        #expect(court.phone.access == .readOnly, "its own say beats the default")

        court.host.setAccess(nil, for: court.phone.device)
        await eventually { court.phone.access == .score }
        #expect(court.phone.access == .score, "and back on the default it goes by that")
    }

    @Test func theHostListsTheGuestsByWhoTheySayTheyAre() async {
        let court = Court(americano)
        await court.open()
        defer { court.close() }

        await eventually { court.host.guests.count == 1 }
        #expect(court.host.guests.map(\.device) == [court.phone.device], "the phone, not its watch")
        #expect(court.host.guests.first?.name == nil)

        court.phone.identify(as: "Cy")
        await eventually { court.host.guests.first?.name == "Cy" }
        #expect(court.host.guests.first?.name == "Cy")
        guard case .tournament(let tournament) = court.phone.state else { Issue.record("no tournament"); return }
        #expect(court.phone.me == tournament.players.first { $0.name == "Cy" }?.id, "and plays as them")

        court.phone.setMe(tournament.players.first { $0.name == "Di" }?.id)
        await eventually { court.host.guests.first?.name == "Di" }
        #expect(court.host.guests.count == 1, "the same phone, renamed")
        #expect(court.host.guests.first?.name == "Di")
    }

    @Test func leavingForgetsWhatTheHostSaid() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }
        court.phone.identify(as: "Ada")

        court.phone.leaveSharedSession()
        #expect(court.phone.accessTable == nil)
        #expect(court.phone.identity == nil)
        #expect(court.phone.access == .full)

        court.host.stopSharing()
        #expect(court.host.accessTable == nil)
        #expect(court.host.guests.isEmpty)
    }

    @Test func aGuestRelaunchedKeepsItsRestriction() throws {
        let hostDevice = DeviceID()
        var log = MatchLog()
        log.append(.configure(winnerCourt), from: hostDevice)
        let guest = MatchStore(
            device: DeviceID(), transport: LoopbackTransport.pair().0,
            session: ActiveSession(log: log, role: .guest, access: ShareAccessTable(standard: .readOnly)),
            snapshotInterval: 0
        )

        #expect(guest.access == .readOnly)
        guest.tap(team: .a)
        #expect(games(guest) == BySide(a: 0, b: 0))
    }

    @Test func aRelaunchedHostKeepsWhatItSaid() {
        var log = MatchLog()
        let device = DeviceID()
        log.append(.configure(winnerCourt), from: device)
        let guest = DeviceID()
        let table = ShareAccessTable(standard: .score).setting(.readOnly, for: guest)
        let host = MatchStore(
            device: device, transport: LoopbackTransport.pair().0,
            session: ActiveSession(log: log, role: .host, access: table, guests: [GuestCard(device: guest, name: "Bob")]),
            snapshotInterval: 0
        )

        host.startSharing()
        #expect(host.accessTable == table, "sharing again on a new code is the same phones")
        #expect(host.guests.map(\.name) == ["Bob"])
    }

    @Test func aGuestStartingItsOwnMatchMayDoEverything() async {
        let court = Court(winnerCourt)
        await court.open(default: .readOnly)
        defer { court.close() }

        court.phone.startNewSession()
        court.phone.configure(winnerCourt)
        court.phone.tap(team: .a)

        #expect(court.phone.access == .full)
        #expect(games(court.phone) == BySide(a: 1, b: 0))
    }
}
