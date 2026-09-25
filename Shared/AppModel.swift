import Foundation
import Observation
import RekkertCore
import RekkertSync

@Observable
final class AppModel {
    let store: MatchStore
    /// Hosting and joining. Inert on the watch, which reaches a shared match through its own
    /// phone and never talks to a stranger's.
    let sharing: SharedSession
    #if !os(watchOS)
    /// The phone does the talking. The watch is on a wrist, not propped at the side of
    /// the court, so it has no announcer at all.
    let announcer = ScoreAnnouncer()
    /// The full-screen board is the phone's too.
    let fullscreen = FullscreenPreferences()
    #endif
    #if os(watchOS)
    /// Which way this wrist reads the court. Device-local, like the phone's full-screen
    /// preferences — two people on one match read their own the way they are facing.
    let sides = WatchSidePreferences()
    /// The wrist itself. Only the watch has one, so only the watch buzzes — but what it does
    /// is set from either device and travels with the match.
    let haptics = WatchHaptics()
    #endif
    /// The workout, which only the watch can actually hold — the phone's counterpart is a
    /// remote control with the same shape, so the scoreboards can be written once.
    let workout = WorkoutController()
    /// Driven from the match menu and presented at the root, so every scoreboard has it.
    var showingShareCode = false
    /// Joining is reachable from the start screen and from a match already in progress —
    /// somebody inviting you does not wait for you to have nothing on.
    var showingJoin = false
    private let sessionStore: SessionStore?
    private var runTask: Task<Void, Never>?

    init() {
        let persistence = try? SessionStore.applicationSupport()
        sessionStore = persistence

        // One peer as far as the store is concerned; a watch and some other people's phones
        // as far as anybody else is.
        let links = FanOutTransport()
        links.attach(AppModel.makePairedTransport(), as: .pairedDevice)
        let localNetwork = LocalNetworkTransport()
        links.attach(localNetwork, as: .sharedSession)
        // The same phones again, over the radio that goes on working with the screen off. A
        // peer on both hears everything twice, which the log does not mind: merging is a union
        // by event id, so a duplicate costs bytes and nothing else.
        let bluetooth = BluetoothTransport()
        links.attach(bluetooth, as: .sharedSession)

        let store = MatchStore(
            device: DeviceIdentity.current(),
            transport: links,
            store: persistence,
            session: try? persistence?.loadActive(),
            keepsHistory: AppModel.keepsHistory
        )
        self.store = store
        sharing = SharedSession(store: store, link: localNetwork, bluetooth: bluetooth)
        roster = persistence?.loadRoster() ?? PlayerRoster()
    }

    /// Whether a finished session is filed away on this device, which is what the result
    /// screen tells the user.
    var keepsFinishedSessions: Bool { AppModel.keepsHistory }

    /// Only the phone keeps a history; the watch has nowhere to show it and less room to
    /// store it.
    private static var keepsHistory: Bool {
        #if os(watchOS)
        false
        #else
        true
        #endif
    }

    private static func makePairedTransport() -> any PeerTransport {
        #if canImport(WatchConnectivity)
        WatchConnectivityTransport()
        #else
        LoopbackTransport(reachable: false)
        #endif
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [store] in await store.run() }
        // A workout is between this device and the one in the same pocket. `MatchStore`
        // carries the messages and holds no opinion about them; the controller has the
        // opinions and cannot reach a transport.
        workout.publish = { [store] signal in store.send(signal) }
        store.onWorkout = { [workout] signal in workout.heard(signal) }
        // Joining, which only the phone can actually do. The wrist asks and is told how it
        // went; the same two ends as the workout, the other way round.
        #if os(watchOS)
        store.onSharing = { [weak self] signal in
            guard case .state(let state) = signal else { return }
            self?.joining = state
        }
        #else
        sharing.publish = { [store] state in Task { await store.send(.state(state)) } }
        store.onSharing = { [weak self] signal in self?.joinFromWatch(signal) }
        #endif
        #if os(watchOS)
        // The store carries the points and holds no opinion about them; the wrist has the
        // opinions and cannot reach a transport. Exactly the shape the workout uses.
        haptics.sides = sides
        haptics.preferences = { [store] in store.haptics }
        haptics.display = { [store] in store.display }
        haptics.state = { [store] in store.state }
        haptics.me = { [store] in store.me }
        haptics.isOurs = { [store] author in store.isOurs(author) }
        store.onPoint = { [haptics] point in haptics.heard(point) }
        #endif
        #if os(watchOS)
        // A session outlives the process that started it, so coming back to a stopped-looking
        // button while Health is still recording would be a lie.
        workout.recover()
        #endif
        #if DEBUG
        seedDemoIfRequested()
        #endif
    }

    #if os(watchOS)
    /// How the join this watch asked its phone for is getting on. The watch has no transport
    /// that reaches a stranger, so this is hearsay from the phone rather than anything it can
    /// see for itself — which is exactly why it is worth showing.
    var joining: SharingState = .off

    /// Hands a code to the phone and starts watching for what it makes of it.
    ///
    /// A join is never queued — one handed over twenty minutes late would go looking for a
    /// match that finished — so if it did not land there is nothing to wait for, and saying so
    /// beats a spinner that never resolves.
    func join(_ code: SessionCode) {
        joining = .searching
        Task { [store] in
            let landed = await store.send(.join(code))
            if !landed, case .searching = joining { joining = .failed(.unreachable) }
        }
    }

    func stopJoining() {
        joining = .off
        Task { [store] in await store.send(.cancel) }
    }
    #else
    /// The wrist has typed a code, or given up on one. Doing the thing is this end's job.
    private func joinFromWatch(_ signal: SharingSignal) {
        switch signal {
        case .join(let code): sharing.join(code)
        case .cancel: sharing.cancelJoining()
        // Said by this end, not heard by it.
        case .state: break
        }
    }
    #endif

    #if DEBUG
    /// `-rekkert-demo traditional|americano|mexicano` seeds a session at launch. simctl
    /// cannot tap, so this is how the watch/phone sync path gets verified headlessly.
    private func seedDemoIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-rekkert-demo-presets") {
            store.savePreset(Preset(name: "Vinnerbane", configuration: .winnerCourt(
                rules: WinnerCourtRules(deuceRule: .goldenPoint),
                teams: BySide(a: TeamInfo(name: "Us"), b: TeamInfo(name: "Them"))
            )))
            store.savePreset(Preset(name: "Thursday americano", configuration: .tournament(
                format: .americano, name: "Thursday",
                players: ["Jonas", "Ada", "Kim", "Sam", "Ola", "Siri", "Tor", "Bjørn"].map { Player(name: $0) },
                config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
            )))
            store.savePreset(Preset(name: "Fredagsmiks", configuration: .friendly(
                name: "Fredagsmiks",
                players: ["Jonas", "Ola", "Kari", "Trond", "Siri"].map { Player(name: $0) },
                rules: TraditionalRules(setsToWin: 1, deuceRule: .goldenPoint)
            )))
            store.savePreset(Preset(name: "Best of 3", configuration: .traditional(
                rules: TraditionalRules(deuceRule: .starPoint),
                teams: BySide(a: TeamInfo(name: "Us"), b: TeamInfo(name: "Them"))
            )))
        }
        if arguments.contains("-rekkert-demo-workouts") {
            let start = Date().addingTimeInterval(-7_200)
            try? sessionStore?.archive(WorkoutRecord(
                id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(5_400),
                duration: 5_400, activeEnergyKilocalories: 612, basalEnergyKilocalories: 118,
                heartRateAverage: 131, heartRateMaximum: 174,
                heartRateZoneTimes: [
                    HeartRateZoneTime(zone: 1, lowerBound: nil, upperBound: 133, duration: 1_284),
                    HeartRateZoneTime(zone: 2, lowerBound: 134, upperBound: 145, duration: 1_902),
                    HeartRateZoneTime(zone: 3, lowerBound: 146, upperBound: 157, duration: 1_734),
                    HeartRateZoneTime(zone: 4, lowerBound: 158, upperBound: 169, duration: 438),
                    HeartRateZoneTime(zone: 5, lowerBound: 170, upperBound: nil, duration: 42),
                ]
            ))
            let earlier = start.addingTimeInterval(-259_200)
            try? sessionStore?.archive(WorkoutRecord(
                id: UUID(), startedAt: earlier, endedAt: earlier.addingTimeInterval(3_900),
                duration: 3_900, activeEnergyKilocalories: 428, basalEnergyKilocalories: 85,
                heartRateAverage: 126, heartRateMaximum: 166
            ))
        }
        // Not behind `#if os(watchOS)`: the phone is only ever told about a workout by a real
        // watch, so without this its badge and its rows cannot be put in front of `simctl`.
        if arguments.contains("-rekkert-demo-workout") { workout.pretendRunning() }
        if arguments.contains("-rekkert-demo-workout-paused") { workout.pretendRunning(paused: true) }
        // `-rekkert-demo-buzz [everyPoint|byTeam]` turns the wrist on, which is the only way
        // to photograph the rows that come with it — simctl cannot work a picker. Out here
        // with the other standalone flags, since the settings screen needs no match behind it.
        if let index = arguments.firstIndex(of: "-rekkert-demo-buzz") {
            let named = index + 1 < arguments.count ? HapticMode(rawValue: arguments[index + 1]) : nil
            store.setHaptics(mode: named ?? .byTeam)
        }
        if arguments.contains("-rekkert-demo-roster") {
            remember(players: ["Jonas", "Ada", "Kim", "Sam", "Bjørn", "Ola", "Siri", "Tor", "Håkon"])
            remember(players: ["Jonas", "Ada", "Kim"])
        }
        // `-rekkert-demo-late-tap 8` scores a point after eight seconds, which is how a live
        // update gets verified between two simulators that nothing can tap.
        if let index = arguments.firstIndex(of: "-rekkert-demo-late-tap"),
           index + 1 < arguments.count,
           let delay = Int(arguments[index + 1]) {
            Task { [store] in
                try? await Task.sleep(for: .seconds(delay))
                store.tap(team: .b)
            }
        }

        guard let flag = arguments.firstIndex(of: "-rekkert-demo"), flag + 1 < arguments.count else { return }
        store.startNewSession()

        switch arguments[flag + 1] {
        case "winnercourt":
            store.configure(.winnerCourt(
                rules: WinnerCourtRules(deuceRule: .goldenPoint),
                teams: BySide(
                    a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]),
                    b: TeamInfo(name: "Them", players: ["Kim", "Sam"])
                )
            ))
            // Two finished rounds and a third under way.
            for _ in 0 ..< 2 { store.tap(team: .a) ; store.tap(team: .a); store.tap(team: .a); store.tap(team: .a) }
            store.tap(team: .b); store.tap(team: .b); store.tap(team: .b); store.tap(team: .b)
            store.endRound()
            for _ in 0 ..< 3 { store.tap(team: .b); store.tap(team: .b); store.tap(team: .b); store.tap(team: .b) }
            store.endRound()
            store.tap(team: .a); store.tap(team: .a); store.tap(team: .a); store.tap(team: .a)
            store.tap(team: .a); store.tap(team: .b)

        case "points":
            store.configure(.pointCount(
                rules: PointCountRules(target: 16),
                teams: BySide(
                    a: TeamInfo(name: "Blues", players: ["Jonas", "Ada"]),
                    b: TeamInfo(name: "Oranges", players: ["Kim", "Sam"])
                )
            ))

        case "traditional":
            store.configure(.traditional(
                rules: TraditionalRules(deuceRule: .starPoint, changeEnds: demoChangeEnds(arguments)),
                teams: BySide(
                    a: TeamInfo(name: "Blues", players: ["Jonas", "Ada"]),
                    b: TeamInfo(name: "Oranges", players: ["Kim", "Sam"])
                )
            ))
        case "friendly":
            store.configure(.friendly(FriendlySession(
                // Pinned, so a screenshot draws the same partnerships every time.
                id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!),
                name: "Thursday",
                rules: TraditionalRules(
                    setsToWin: 1,
                    deuceRule: .goldenPoint,
                    changeEnds: demoChangeEnds(arguments)
                ),
                // `-rekkert-demo-friendly-players 3` cuts the group down, which is how the
                // singles and the bench get onto a screenshot.
                players: Array(
                    ["Jonas", "Ola", "Kari", "Trond", "Siri"].map { Player(name: $0) }
                        .prefix(friendlyPlayerCount(arguments))
                )
            )))
            store.nextRound()
            // `-rekkert-demo-friendly-rounds 3` plays three of them out, which is the only
            // way to photograph the summary and the history screens.
            if let index = arguments.firstIndex(of: "-rekkert-demo-friendly-rounds"),
               index + 1 < arguments.count, let rounds = Int(arguments[index + 1]) {
                for round in 0 ..< rounds {
                    // Drawn between rounds rather than after the last, so it finishes on the
                    // screen offering the next partnership rather than on a blank board.
                    if round > 0 { store.nextRound() }
                    // Alternating every third game, so a round has a shape to it rather
                    // than being a whitewash.
                    for game in 0 ..< 9 {
                        let winner: TeamSide = game.isMultiple(of: 3) ? .b : .a
                        for _ in 0 ..< 4 { store.tap(round: round, court: 0, team: winner) }
                    }
                }
            }

        case let format:
            store.configure(.tournament(Tournament(
                name: "Thursday",
                format: format == "mexicano" ? .mexicano : .americano,
                players: ["Jonas", "Ada", "Kim", "Sam", "No", "Ola", "Siri", "Tor"].map { Player(name: $0) },
                config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
            )))
            store.nextRound()
        }

        if let points = arguments.firstIndex(of: "-rekkert-demo-points"),
           points + 1 < arguments.count, let count = Int(arguments[points + 1]) {
            for index in 0 ..< count {
                store.tap(court: 0, team: index.isMultiple(of: 3) ? .b : .a)
            }
        }
        if arguments.contains("-rekkert-demo-rounds") {
            for round in 0 ..< 2 {
                store.setScore(round: round, court: 0, points: BySide(a: 9, b: 7))
                store.setScore(round: round, court: 1, points: BySide(a: 11, b: 5))
                store.setRoundConfirmed(round, true)
                store.nextRound()
            }
        }
        if arguments.contains("-rekkert-demo-swap-colours") {
            store.toggleTeamColors()
        }
        if arguments.contains("-rekkert-demo-swap-player") {
            store.swapServingPlayer()
        }
        #if os(iOS)
        // `-rekkert-share-host 482915` starts sharing on a pinned code, so two simulators can
        // be pointed at each other from a script.
        if let index = arguments.firstIndex(of: "-rekkert-share-host"),
           index + 1 < arguments.count,
           let code = SessionCode(arguments[index + 1]) {
            sharing.host(code: code)
        }
        if arguments.contains("-rekkert-demo-blackout") {
            fullscreen.isBlackout = true
        }
        #endif
        if arguments.contains("-rekkert-demo-finished") {
            store.finish()
        }
        if arguments.contains("-rekkert-demo-undo-draw") {
            store.undoLast()
        }
        if arguments.contains("-rekkert-demo-deuce") {
            // Five exchanges reaches the third 40-40, which is where star point decides.
            for _ in 0 ..< 5 {
                store.tap(court: 0, team: .a)
                store.tap(court: 0, team: .b)
            }
        }
    }
    #endif

    #if DEBUG
    /// `-rekkert-demo-swap-sides [oddGames|everySet]` starts the match with a changeover rule
    /// on, so the board turning over can be photographed by a script that cannot tap anything.
    private func demoChangeEnds(_ arguments: [String]) -> ChangeEndsRule {
        guard let index = arguments.firstIndex(of: "-rekkert-demo-swap-sides") else { return .off }
        guard index + 1 < arguments.count else { return .oddGames }
        return ChangeEndsRule(rawValue: arguments[index + 1]) ?? .oddGames
    }

    private func friendlyPlayerCount(_ arguments: [String]) -> Int {
        guard let index = arguments.firstIndex(of: "-rekkert-demo-friendly-players"),
              index + 1 < arguments.count,
              let count = Int(arguments[index + 1]) else { return 5 }
        return min(max(count, 2), 5)
    }
    #endif

    func becameActive() {
        // Sharing does not survive being put down: the system takes the listener away with
        // the app, so coming back to the front is when it has to be stood up again.
        sharing.resume()
        Task { [store] in await store.synchronise() }
        #if os(watchOS)
        workout.recover()
        #endif
        #if !os(watchOS)
        // Coming back to the front is when somebody has just been off downloading a voice.
        announcer.refreshVoices()
        #endif
    }

    /// Everyone who has played before, for name suggestions.
    private(set) var roster = PlayerRoster()

    func remember(players names: [String]) {
        var updated = roster
        updated.remember(names)
        roster = updated
        try? sessionStore?.save(updated)
    }

    func forgetPlayer(_ name: String) {
        var updated = roster
        updated.forget(name)
        roster = updated
        try? sessionStore?.save(updated)
    }

    /// The shelves live on disk, where `@Observable` has nothing to watch. Reading this in
    /// the getters and bumping it on every change is what redraws a list once a record has
    /// been edited or deleted.
    private var revision = 0

    var history: [HistoryRecord] {
        _ = revision
        return (try? sessionStore?.history()) ?? []
    }

    var workouts: [WorkoutRecord] {
        _ = revision
        return (try? sessionStore?.workouts()) ?? []
    }

    /// One record, read on its own rather than off the back of the whole shelf — a screen
    /// showing a single match asks on every redraw.
    func record(_ id: UUID) -> HistoryRecord? {
        _ = revision
        return sessionStore?.historyRecord(id)
    }

    /// Asked on every redraw of the start screen purely to decide whether a row is there, so
    /// it lists the directory rather than decoding everything in it.
    var hasWorkouts: Bool {
        _ = revision
        return sessionStore?.hasWorkouts() ?? false
    }

    func deleteWorkout(_ id: UUID) {
        try? sessionStore?.deleteWorkout(id)
        revision += 1
    }

    /// The matches scored while a workout was running, worked out from the clock. A match
    /// that spanned two workouts appears under both, which is the answer rather than a bug.
    func matches(during workout: WorkoutRecord) -> [HistoryRecord] {
        history.filter(workout.covers)
    }

    /// Ends the session everywhere. The store archives it if it is worth keeping and
    /// clears both devices, so there is a single path rather than one per device.
    func finishSession() {
        store.finish()
    }

    /// Calls the session off without keeping a record of how far it got.
    func discard() {
        store.discardSession()
    }

    func deleteHistory(_ id: UUID) {
        try? sessionStore?.deleteHistory(id)
        revision += 1
    }

    /// Files an edited record back over the original. Archiving is keyed on the record's id,
    /// so this replaces rather than adds.
    func update(_ record: HistoryRecord) {
        try? sessionStore?.archive(record)
        revision += 1
    }
}
