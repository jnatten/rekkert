import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

private struct Pair {
    let phone: MatchStore
    let watch: MatchStore
    let phoneLink: LoopbackTransport
    let watchLink: LoopbackTransport

    init() {
        let (one, two) = LoopbackTransport.pair()
        phoneLink = one
        watchLink = two
        let session = ActiveSession(log: MatchLog(sessionID: UUID(uuidString: "33333333-0000-0000-0000-000000000000")!))
        phone = MatchStore(device: DeviceID(), transport: one, session: session, snapshotInterval: 0)
        watch = MatchStore(device: DeviceID(), transport: two, session: session, snapshotInterval: 0)
    }

    func run() -> [Task<Void, Never>] {
        [Task { await phone.run() }, Task { await watch.run() }]
    }
}

private func settle() async throws {
    try await Task.sleep(for: .milliseconds(250))
}

private func points(_ store: MatchStore) -> BySide<Int>? {
    guard case .traditional(let session) = store.state else { return nil }
    return session.score.points
}

@Suite("Watch and phone sync", .serialized)
@MainActor
struct SyncTests {
    @Test func aTapOnThePhoneReachesTheWatch() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        // Both ends have to be consuming before either says anything. In the app the run
        // loops start at launch; here they start a microsecond before the first tap.
        try await settle()

        pair.phone.configure(setup)
        pair.phone.tap(team: .a)
        try await settle()

        #expect(points(pair.watch) == BySide(a: 1, b: 0))
        #expect(pair.watch.state == pair.phone.state)
    }

    @Test func aTapOnTheWatchReachesThePhone() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        try await settle()
        pair.watch.tap(team: .b)
        try await settle()

        #expect(points(pair.phone) == BySide(a: 0, b: 1))
    }

    @Test func simultaneousTapsOnBothDevicesBothCount() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        try await settle()

        pair.phoneLink.setDroppingOutgoing(true)
        pair.watchLink.setDroppingOutgoing(true)
        pair.phone.tap(team: .a)
        pair.watch.tap(team: .a)
        try await settle()

        pair.phoneLink.setDroppingOutgoing(false)
        pair.watchLink.setDroppingOutgoing(false)
        try await settle()

        #expect(points(pair.phone) == BySide(a: 2, b: 0), "neither tap was lost")
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func tapsMadeWhileDisconnectedArriveOnReconnect() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        try await settle()

        pair.phoneLink.setDroppingOutgoing(true)
        for _ in 0 ..< 3 { pair.phone.tap(team: .a) }
        try await settle()
        #expect(points(pair.watch) == BySide(a: 0, b: 0), "watch is still in the dark")

        pair.phoneLink.setDroppingOutgoing(false)
        try await settle()
        #expect(points(pair.watch) == BySide(a: 3, b: 0))
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func undoOnTheWatchReachesThePhone() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(setup)
        pair.phone.tap(team: .a)
        pair.phone.tap(team: .a)
        try await settle()

        pair.watch.undoLast()
        try await settle()

        #expect(points(pair.phone) == BySide(a: 1, b: 0))
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func aColdWatchPicksUpTheSessionFromASnapshot() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(setup)
        phone.tap(team: .b)
        phone.tap(team: .b)
        try await settle()

        #expect(watch.log.sessionID == phone.log.sessionID, "the empty watch adopted the phone's session")
        #expect(points(watch) == BySide(a: 0, b: 2))
    }

    @Test func anEmptyPeerIsNotAConflict() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: watchLink, snapshotInterval: 0)

        phone.configure(setup)
        phone.tap(team: .a)

        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(phone.replacedSessionTitle == nil, "a watch with no session displaces nothing")
        #expect(watch.replacedSessionTitle == nil)
        #expect(watch.log.sessionID == phone.log.sessionID)
        #expect(points(watch) == BySide(a: 1, b: 0))
    }

    @Test func theMoreRecentlyStartedSessionWins() async throws {
        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let old = ActiveSession(log: MatchLog(createdAt: .now.addingTimeInterval(-3600)))
        let watch = MatchStore(device: DeviceID(), transport: watchLink, session: old, snapshotInterval: 0)
        watch.configure(setup)
        watch.tap(team: .a)

        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        phone.configure(setup)
        phone.tap(team: .b)
        phone.tap(team: .b)

        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(watch.log.sessionID == phone.log.sessionID, "the stale watch session gives way")
        #expect(points(watch) == BySide(a: 0, b: 2))
        #expect(points(phone) == BySide(a: 0, b: 2))
    }

    @Test func aReplacedSessionIsArchivedNotLost() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionStore = SessionStore(directory: directory)

        let (phoneLink, watchLink) = LoopbackTransport.pair()
        let old = ActiveSession(log: MatchLog(createdAt: .now.addingTimeInterval(-3600)))
        let watch = MatchStore(device: DeviceID(), transport: watchLink, store: sessionStore, session: old, snapshotInterval: 0)
        watch.configure(setup)
        watch.tap(team: .a)

        let phone = MatchStore(device: DeviceID(), transport: phoneLink, snapshotInterval: 0)
        phone.configure(setup)
        phone.tap(team: .b)

        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(watch.replacedSessionTitle == "Us vs Them")
        #expect(try sessionStore.history().count == 1, "the discarded match went to history")
    }

    @Test func tournamentCourtsSyncIndependently() async throws {
        let tournament = Tournament(
            name: "Thursday",
            format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 2)
        )
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(.tournament(tournament))
        pair.phone.nextRound()
        try await settle()

        pair.watch.tap(court: 1, team: .a)
        pair.phone.setScore(court: 0, points: BySide(a: 9, b: 7))
        try await settle()

        guard case .tournament(let synced) = pair.watch.state else {
            Issue.record("watch has no tournament")
            return
        }
        #expect(synced.rounds[0].matches[0].state.points == BySide(a: 9, b: 7))
        #expect(synced.rounds[0].matches[1].state.points == BySide(a: 1, b: 0))
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func aSessionFromAnOlderBuildIsSetAsideRatherThanCrashing() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The shape events had before rounds were addressed explicitly.
        let legacy = #"{"log":{"sessionID":"x","events":[{"kind":{"point":{"court":0}}}]},"outbox":{"pending":[]}}"#
        try Data(legacy.utf8).write(to: directory.appending(path: "active.json"))

        let store = SessionStore(directory: directory)
        #expect(try store.loadActive() == nil)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "active-unreadable.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "active.json").path))
        #expect(try store.loadActive() == nil, "and the next launch is clean")
    }

    @Test func correctingAnOldRoundOnThePhoneDoesNotDisturbTheWatchsCurrentRound() async throws {
        let tournament = Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 2)
        )
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        pair.phone.configure(.tournament(tournament))
        pair.phone.nextRound()
        pair.phone.setScore(round: 0, court: 0, points: BySide(a: 9, b: 7))
        pair.phone.setRoundConfirmed(0, true)
        pair.phone.nextRound()
        try await settle()

        // The watch scores the live round while the phone fixes a typo in the old one.
        pair.watch.tap(round: 1, court: 0, team: .a)
        pair.phone.setRoundConfirmed(0, false)
        pair.phone.setScore(round: 0, court: 0, points: BySide(a: 12, b: 4))
        try await settle()

        guard case .tournament(let synced) = pair.watch.state else {
            Issue.record("watch has no tournament")
            return
        }
        #expect(synced.rounds[0].matches[0].state.points == BySide(a: 12, b: 4), "correction landed")
        #expect(synced.rounds[1].matches[0].state.points == BySide(a: 1, b: 0), "live round intact")
        #expect(pair.phone.state == pair.watch.state)
    }

    @Test func presetsSavedOnThePhoneReachTheWatch() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        let preset = Preset(name: "Thursday", configuration: .winnerCourt(
            rules: WinnerCourtRules(deuceRule: .goldenPoint),
            teams: BySide(a: TeamInfo(name: "Us"), b: TeamInfo(name: "Them"))
        ))
        pair.phone.savePreset(preset)
        try await settle()

        #expect(pair.watch.presets.presets.map(\.name) == ["Thursday"])

        pair.phone.removePreset(preset.id)
        try await settle()
        #expect(pair.watch.presets.isEmpty, "and a deletion travels too")
    }

    @Test func editsAndReordersOnThePhoneReachTheWatch() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        let teams = BySide(a: TeamInfo(name: "Us"), b: TeamInfo(name: "Them"))
        let thursday = Preset(name: "Thursday", configuration: .winnerCourt(rules: WinnerCourtRules(), teams: teams))
        pair.phone.savePreset(thursday)
        pair.phone.savePreset(Preset(name: "Friday", configuration: .traditional(rules: TraditionalRules(), teams: teams)))
        try await settle()
        #expect(pair.watch.presets.presets.map(\.name) == ["Friday", "Thursday"])

        pair.phone.updatePreset(thursday.id) {
            $0.name = "Torsdag"
            $0.configuration = .pointCount(rules: PointCountRules(target: 21), teams: teams)
        }
        pair.phone.movePresets(fromOffsets: [1], toOffset: 0)
        try await settle()

        #expect(pair.watch.presets.presets.map(\.name) == ["Torsdag", "Friday"], "renamed and moved up")
        #expect(pair.watch.presets.presets.first?.configuration == .pointCount(rules: PointCountRules(target: 21), teams: teams))
        #expect(pair.watch.presets == pair.phone.presets)
    }

    @Test func aSessionStartedFromAPresetOnTheWatchShowsOnThePhone() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }

        let preset = Preset(name: "Thursday", configuration: .tournament(
            format: .americano,
            name: "Thursday",
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 1)
        ))
        pair.phone.savePreset(preset)
        try await settle()

        let onTheWatch = try #require(pair.watch.presets.presets.first)
        pair.watch.start(onTheWatch)
        try await settle()

        guard case .tournament(let tournament)? = pair.phone.state else {
            Issue.record("the phone did not pick up the session")
            return
        }
        #expect(tournament.rounds.count == 1, "the first round was drawn without touching the phone")
        #expect(pair.phone.state == pair.watch.state)
        #expect(pair.phone.presets.presets.first?.useCount == 1, "and the phone sees it was used")
    }

    @Test func theWatchFlipsThePhonesScoreboard() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        #expect(pair.phone.display.isMirrored == false)

        pair.watch.toggleScoreboardMirrored()
        try await settle()

        #expect(pair.phone.display.isMirrored, "pressed on the wrist, applied on the phone")

        // And from the phone itself.
        pair.phone.toggleScoreboardMirrored()
        try await settle()
        #expect(pair.phone.display.isMirrored == false)
        #expect(pair.watch.display.isMirrored == false, "the watch follows so its next press is right")
    }

    @Test func swappingTheColoursReachesBothDevices() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.watch.toggleTeamColors()
        try await settle()

        #expect(pair.phone.display.areColorsSwapped, "which side is blue is not about where you stand")
        #expect(pair.watch.display.areColorsSwapped, "so unlike mirroring, the watch follows it too")

        pair.phone.toggleTeamColors()
        try await settle()
        #expect(pair.phone.display.areColorsSwapped == false)
        #expect(pair.watch.display.areColorsSwapped == false)
    }

    @Test func aNewMatchStartsUsBlueOnTheLeftAgain() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup)
        pair.phone.toggleScoreboardMirrored()
        try await settle()
        pair.watch.toggleTeamColors()
        try await settle()
        #expect(pair.phone.display.isMirrored)
        #expect(pair.phone.display.areColorsSwapped)

        pair.phone.startNewSession()
        pair.phone.configure(setup)
        try await settle()

        #expect(pair.phone.display.isDefault, "the flips belonged to the match that is over")
        #expect(pair.watch.display.isDefault, "and the watch reads the new one the same way")
    }

    // MARK: - Buzzing

    @Test func howTheWatchBuzzesCanBeSetFromEitherDevice() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.setHaptics(mode: .byTeam, strength: .strong)
        try await settle()
        #expect(pair.watch.haptics.mode == .byTeam, "the phone sets the wrist's buzz")
        #expect(pair.watch.haptics.strength == .strong)

        pair.watch.setHaptics(onlyWhenSomeoneElseScores: false)
        try await settle()
        #expect(pair.phone.haptics.onlyWhenSomeoneElseScores == false, "and the wrist answers back")
        #expect(pair.phone.haptics.mode == .byTeam, "without losing what the phone said")
    }

    /// How hard somebody likes their wrist tapped is not a thing about today's match, so a
    /// new one leaves it exactly where it was. The deliberate opposite of the flips above.
    @Test func theBuzzOutlivesTheMatchItWasSetIn() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup)
        pair.phone.setHaptics(mode: .byTeam, strength: .light)
        try await settle()

        pair.phone.startNewSession()
        pair.phone.configure(setup)
        try await settle()

        #expect(pair.phone.haptics.mode == .byTeam, "still set for the next match")
        #expect(pair.phone.haptics.strength == .light)
        #expect(pair.watch.haptics.mode == .byTeam, "and the watch still agrees")
    }

    @Test func aRepeatedBuzzInstructionDoesNotUndoItself() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.setHaptics(mode: .everyPoint)
        try await settle()
        #expect(pair.watch.haptics.mode == .everyPoint)

        // The durable queue can deliver the same payload again; an absolute value survives
        // that where a step would walk past it.
        pair.phone.setHaptics(mode: .everyPoint)
        await pair.phone.synchronise()
        await pair.watch.synchronise()
        try await settle()

        #expect(pair.watch.haptics.mode == .everyPoint, "still on rather than back off")
    }

    /// The store says a point was played only when one really was. Everything below is a way
    /// the board can change without that being true.
    @Test func onlyAPointThatMovedTheBoardIsAnnounced() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        var announced: [ScoredPoint] = []
        pair.watch.onPoint = { announced.append($0) }

        pair.phone.configure(setup)
        try await settle()
        #expect(announced.isEmpty, "setting a match up is not a point")

        pair.phone.tap(team: .a)
        try await settle()
        #expect(announced.count == 1, "a point is")
        #expect(announced.last?.team == .a)

        pair.phone.undoLast()
        try await settle()
        #expect(announced.count == 1, "and taking it back is not another one")

        pair.phone.setScore(round: 0, court: 0, points: BySide(a: 3, b: 1))
        try await settle()
        #expect(announced.count == 1, "nor is putting the score right by hand")

        pair.phone.swapServingTeam()
        try await settle()
        #expect(announced.count == 1, "nor is correcting the serve")
    }

    /// A watch that has been away is handed everything it missed at once. Those points are
    /// old news, and counting them out on somebody's wrist would be an alarm.
    @Test func aCatchUpOfSeveralPointsIsNotAnnouncedAtAll() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup)
        try await settle()

        var announced: [ScoredPoint] = []
        pair.watch.onPoint = { announced.append($0) }

        // Scored while nothing is carrying them across, then delivered in one go.
        pair.phoneLink.setReachable(false)
        for _ in 0 ..< 5 { pair.phone.tap(team: .b) }
        try await settle()
        #expect(announced.isEmpty, "nothing arrived yet")

        pair.phoneLink.setReachable(true)
        await pair.phone.synchronise()
        await pair.watch.synchronise()
        try await settle()

        #expect(pair.watch.state != nil, "the points did arrive")
        #expect(announced.isEmpty, "but five at once is a catch-up, not five points")
    }

    @Test func aPointCarriesWhoEnteredIt() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.configure(setup)
        try await settle()

        var announced: [ScoredPoint] = []
        pair.watch.onPoint = { announced.append($0) }

        pair.phone.tap(team: .a)
        try await settle()
        #expect(announced.last?.scoredBy == pair.phone.device, "and it is the phone's, not the watch's")
        #expect(pair.watch.isOurs(pair.watch.device), "its own work is always its own")
    }

    /// Across days, not just across matches: `Pair()` keeps nothing on disk, so surviving a
    /// new session in memory says nothing about surviving the app being closed.
    @Test func theBuzzIsStillSetAfterARelaunch() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let device = DeviceID()

        let first = MatchStore(device: device, transport: LoopbackTransport(), store: store)
        first.setHaptics(mode: .byTeam, onlyWhenSomeoneElseScores: false, strength: .strong)
        #expect(first.haptics.mode == .byTeam)

        // A fresh store over the same directory, the way a relaunch reads what was left.
        let second = MatchStore(device: device, transport: LoopbackTransport(), store: store)
        #expect(second.haptics.mode == .byTeam, "still set a day later")
        #expect(second.haptics.strength == .strong)
        #expect(second.haptics.onlyWhenSomeoneElseScores == false)
        #expect(second.haptics.hasBeenSet, "and worth telling the watch about again")
    }

    @Test func theTwoDisplayPreferencesDoNotDisturbEachOther() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.phone.toggleScoreboardMirrored()
        try await settle()
        pair.watch.toggleTeamColors()
        try await settle()

        #expect(pair.phone.display.isMirrored, "still flipped")
        #expect(pair.phone.display.areColorsSwapped, "and swapped")
    }

    @Test func aRepeatedFlipInstructionDoesNotUndoItself() async throws {
        let pair = Pair()
        let tasks = pair.run()
        defer { tasks.forEach { $0.cancel() } }
        try await settle()

        pair.watch.setScoreboardMirrored(true)
        try await settle()
        #expect(pair.phone.display.isMirrored)

        // The durable queue can deliver the same payload again; an absolute value survives
        // that where a toggle would cancel itself out.
        pair.watch.setScoreboardMirrored(true)
        await pair.watch.synchronise()
        await pair.phone.synchronise()
        try await settle()

        #expect(pair.phone.display.isMirrored, "still mirrored, not flipped back")
    }

    @Test func aFlipIsNotLostToATrailingClock() async throws {
        // The phone flips, then the watch flips a moment later with a clock that reads
        // slightly earlier. Ordering by revision rather than by the clock keeps the second
        // press from being discarded as stale.
        let phone = DisplayPreferences().setting(mirrored: true, at: Date(timeIntervalSince1970: 1_000))
        let watch = phone.setting(mirrored: false, at: Date(timeIntervalSince1970: 995))

        #expect(phone.adopting(watch).isMirrored == false, "the later press wins despite the earlier stamp")
        #expect(phone.adopting(watch).revision == 2)
    }

    @Test func stateSurvivesARestartFromDisk() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)

        let device = DeviceID()
        let first = MatchStore(device: device, transport: LoopbackTransport(reachable: false), store: store)
        first.configure(setup)
        first.tap(team: .a)
        first.tap(team: .b)
        first.tap(team: .a)

        let reloaded = try #require(try store.loadActive())
        let second = MatchStore(device: device, transport: LoopbackTransport(reachable: false), session: reloaded)

        #expect(points(second) == BySide(a: 2, b: 1))
        #expect(second.log.ordered == first.log.ordered)
        #expect(reloaded.outbox.pending.count == 4, "nothing was acknowledged while offline")
    }
}
