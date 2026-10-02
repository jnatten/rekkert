import Foundation
import Observation
import RekkertCore
import RekkertSync

@Observable
final class AppModel {
    let store: MatchStore
    /// Hosting and joining. On the watch only joining, and only while its phone cannot.
    let sharing: SharedSession
    #if !os(watchOS)
    /// The phone does the talking. The watch is on a wrist, not propped at the side of
    /// the court, so it has no announcer at all.
    let announcer = ScoreAnnouncer()
    /// The full-screen board is the phone's too.
    let fullscreen = FullscreenPreferences()
    let liveScore = LiveScoreActivity()
    var isBoardOnTV = false
    var showingBoard = false
    var showingTVGuide = false
    #endif
    #if os(watchOS)
    /// Which way this wrist reads the court. Device-local, like the phone's full-screen
    /// preferences — two people on one match read their own the way they are facing.
    let sides = WatchSidePreferences()
    /// The wrist itself. Only the watch has one, so only the watch buzzes — but what it does
    /// is set from either device and travels with the match.
    let haptics = WatchHaptics()
    let standIn: WatchStandIn
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
        let sharing = SharedSession(store: store, link: localNetwork, bluetooth: bluetooth)
        self.sharing = sharing
        #if os(watchOS)
        standIn = WatchStandIn(store: store, sharing: sharing)
        #endif
        roster = persistence?.loadRoster() ?? PlayerRoster()
        if AppModel.keepsHistory, let persistence {
            playerLinks = persistence.loadLinks()
        }
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
        store.onWorkout = { [weak self] signal in
            self?.workout.heard(signal)
            // What the phone has filed changed, and the lists showing it read through this.
            switch signal {
            case .finished, .series: self?.revision += 1
            case .stop, .pause, .resume, .running, .paused, .idle: break
            }
        }
        // Joining, which the phone does whenever it can. The wrist asks and is told how it
        // went; the same two ends as the workout, the other way round.
        #if os(watchOS)
        store.onSharing = { [standIn] signal in standIn.heard(signal) }
        Task { [standIn] in await standIn.run() }
        #else
        sharing.publish = { [store] state in Task { await store.send(.state(state)) } }
        sharing.onStandby = { [store] standby in Task { await store.send(.standby(standby)) } }
        store.onSharing = { [weak self] signal in self?.joinFromWatch(signal) }
        liveScore.follow(store)
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

    #if DEBUG
    /// A heart that warms up, works through the rallies and is held for a coffee near the end.
    private static func demoSeries(of workoutID: UUID, from start: Date, lasting span: TimeInterval) -> WorkoutSeries {
        let interval = WorkoutSeries.interval(forSpan: span)
        let steps = Int(span / interval)
        let held = DateInterval(start: start.addingTimeInterval(4_200), duration: 300)
        var rates: [Int?] = []
        var energy: [Double] = []
        for step in 0 ..< steps {
            let at = start.addingTimeInterval(Double(step) * interval)
            if held.contains(at) {
                rates.append(nil)
                energy.append(0)
                continue
            }
            let minutes = Double(step) * interval / 60
            let warmth = min(1, minutes / 8)
            let rally = sin(minutes * 1.7) * 9 + sin(minutes * 0.31) * 6
            rates.append(Int(98 + warmth * 42 + rally))
            energy.append(0.6 + warmth * 1.0 + max(0, rally) / 15)
        }
        return WorkoutSeries(
            workoutID: workoutID, start: start, interval: interval,
            heartRate: rates, heartRateMax: rates.map { $0.map { $0 + 6 } }, activeEnergy: energy,
            pauses: [held]
        )
    }

    /// Two sets on golden point, the Blues just the stronger, a point every twenty-odd seconds.
    private static func demoMatch(from start: Date) -> (HistoryRecord, MatchTimeline)? {
        let device = DeviceID()
        var log = MatchLog(createdAt: start)
        var clock = start
        log.append(.configure(.traditional(
            rules: TraditionalRules(deuceRule: .goldenPoint),
            teams: BySide(a: TeamInfo(name: "Blues", players: ["Jonas", "Ada"]), b: TeamInfo(name: "Oranges", players: ["Kim", "Sam"]))
        ), at: start), from: device, at: start)
        var generator = SeededGenerator(seed: 7)
        while !(SessionReducer.state(of: log)?.isFinished ?? true) {
            clock = clock.addingTimeInterval(Double.random(in: 14 ... 34, using: &generator))
            let side: TeamSide = Double.random(in: 0 ..< 1, using: &generator) < 0.56 ? .a : .b
            log.append(.point(round: 0, court: 0, team: side), from: device, at: clock)
        }
        guard let state = SessionReducer.state(of: log) else { return nil }
        let record = HistoryRecord(
            id: log.sessionID, finishedAt: clock, title: state.title, state: state,
            startedAt: start, playedUntil: clock
        )
        return (record, MatchTimeline.make(from: log))
    }

    private static func demoPlayerHistory() -> [HistoryRecord] {
        func id(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-00000000D%03X", number))! }
        func set(_ winner: TeamSide, _ loser: Int) -> TraditionalState {
            var score = TraditionalState()
            score.completedSets = [SetResult(games: winner == .a ? BySide(a: 6, b: loser) : BySide(a: loser, b: 6), winner: winner)]
            score.winner = winner
            return score
        }
        var generator = SeededGenerator(seed: 11)
        let now = Date()
        var records: [HistoryRecord] = []

        let group = ["Jonas", "Ada", "Kim", "Sam", "Ola", "Siri", "Tor", "Bjørn"]
        for week in 0 ..< 3 {
            var tournament = Tournament(
                id: TournamentID(id(0x100 + week)), name: "Thursday", format: .americano,
                players: group.enumerated().map { Player(id: PlayerID(id(0x200 + week * 16 + $0.offset)), name: $0.element) },
                config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
            )
            for round in 0 ..< 4 {
                guard let next = try? TournamentEngine.appendingRound(to: tournament) else { break }
                tournament = next
                for court in tournament.rounds[round].matches.indices {
                    let a = Int.random(in: 4 ... 12, using: &generator)
                    tournament.rounds[round].matches[court].state.points = BySide(a: a, b: 16 - a)
                }
            }
            tournament.isFinished = true
            let finished = now.addingTimeInterval(Double(week - 3) * 7 * 86_400)
            records.append(HistoryRecord(id: id(week), finishedAt: finished, title: tournament.name, state: .tournament(tournament)))
        }

        var friendly = FriendlySession(
            id: FriendlyID(id(0x300)), name: "Fredagsmiks",
            players: ["Jonas", "Ola", "Kari", "Ola", "Siri"].enumerated().map { Player(id: PlayerID(id(0x310 + $0.offset)), name: $0.element) }
        )
        for round in 0 ..< 4 {
            guard let next = try? FriendlyScheduler.appendingRound(to: friendly) else { break }
            friendly = next
            friendly.rounds[round].score = set(round.isMultiple(of: 3) ? .b : .a, Int.random(in: 1 ... 4, using: &generator))
        }
        friendly.isFinished = true
        records.append(HistoryRecord(id: id(0x10), finishedAt: now.addingTimeInterval(-4 * 86_400), title: friendly.name, state: .friendly(friendly)))

        let matches: [([String], [String], TeamSide)] = [
            (["Jonas", "Ada"], ["Kim", "Sam"], .a),
            (["Jon", "Ada"], ["Kim", "Sam"], .a),
            (["Jonas", "Kim"], ["Ada", "Sam"], .b),
            (["Jonas", "Ada"], ["Ola", "Siri"], .a),
        ]
        for (index, match) in matches.enumerated() {
            let state = SessionState.traditional(TraditionalSession(
                rules: TraditionalRules(setsToWin: 1),
                teams: BySide(a: TeamInfo(name: "Us", players: match.0), b: TeamInfo(name: "Them", players: match.1)),
                score: set(match.2, 3),
                name: index == 0 ? "Club final" : ""
            ))
            records.append(HistoryRecord(
                id: id(0x20 + index), finishedAt: now.addingTimeInterval(Double(-index - 1) * 86_400),
                title: state.title, state: state,
                note: index == 0 ? "Court 3, and windy. Ada served the last three games out." : nil
            ))
        }
        return records
    }
    #endif

    #if os(watchOS)
    var joining: SharingState { standIn.joining }

    func join(_ code: SessionCode) { standIn.join(code) }

    func stopJoining() { standIn.cancel() }

    func joinScreenClosed() { standIn.joinScreenClosed() }
    #else
    /// The wrist has typed a code, or given up on one. Doing the thing is this end's job.
    private func joinFromWatch(_ signal: SharingSignal) {
        switch signal {
        case .join(let code): sharing.join(code)
        case .cancel: sharing.cancelJoiningFromTheWatch()
        // Said by this end, not heard by it.
        case .state, .standby: break
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
        if arguments.contains("-rekkert-demo-players") {
            for record in Self.demoPlayerHistory() { try? sessionStore?.archive(record) }
        }
        // `-rekkert-demo-period last:30:day`, `previous:year`, `current:month`, `year:2025` or `all`.
        if let index = arguments.firstIndex(of: "-rekkert-demo-period"), index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: ":").map(String.init)
            let unit = parts.last.flatMap(PeriodUnit.init(rawValue:)) ?? .day
            switch parts.first {
            case "last": statsPeriod = .last(parts.count > 1 ? Int(parts[1]) ?? 30 : 30, unit)
            case "current": statsPeriod = .current(unit)
            case "previous": statsPeriod = .previous(unit)
            case "year": statsPeriod = .year(parts.count > 1 ? Int(parts[1]) ?? 2026 : 2026)
            default: statsPeriod = .allTime
            }
        }
        if arguments.contains("-rekkert-demo-workouts") {
            let start = Date().addingTimeInterval(-7_200)
            let workoutID = UUID()
            try? sessionStore?.archive(Self.demoSeries(of: workoutID, from: start, lasting: 5_400))
            if let (record, timeline) = Self.demoMatch(from: start.addingTimeInterval(600)) {
                try? sessionStore?.archive(record)
                try? sessionStore?.archive(timeline, for: record.id)
            }
            try? sessionStore?.archive(WorkoutRecord(
                id: workoutID, startedAt: start, endedAt: start.addingTimeInterval(5_400),
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
            // `-rekkert-demo-courts 8` fills eight courts, which is how the TV's grid gets
            // photographed at its fullest.
            let courts = demoCourtCount(arguments)
            store.configure(.tournament(Tournament(
                name: "Thursday",
                format: format == "mexicano" ? .mexicano : .americano,
                // `-rekkert-demo-sit-outs` brings one more, so somebody has to sit out.
                players: (Array(Self.demoNames.prefix(courts * 4))
                    + (arguments.contains("-rekkert-demo-sit-outs") ? ["Per"] : []))
                    .map { Player(name: $0) },
                config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
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

    private static let demoNames = [
        "Jonas", "Ada", "Kim", "Sam", "No", "Ola", "Siri", "Tor",
        "Kari", "Trond", "Bjørn", "Håkon", "Ingrid", "Marius", "Silje", "Eirik",
        "Nora", "Emil", "Thea", "Henrik", "Maja", "Sander", "Ida", "Magnus",
        "Emma", "Jakob", "Sofie", "Lars", "Hedda", "Aksel", "Tuva", "Filip",
    ]

    private func demoCourtCount(_ arguments: [String]) -> Int {
        guard let index = arguments.firstIndex(of: "-rekkert-demo-courts"),
              index + 1 < arguments.count,
              let count = Int(arguments[index + 1]) else { return 2 }
        return min(max(count, 1), 8)
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
        liveScore.reconcile()
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
    private(set) var revision = 0

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

    func timeline(_ id: UUID) -> MatchTimeline? {
        _ = revision
        return sessionStore?.timeline(id)
    }

    func series(_ workoutID: UUID) -> WorkoutSeries? {
        _ = revision
        return sessionStore?.series(workoutID)
    }

    /// How the heart went while a match was played, from whichever workout was running then,
    /// and the zones that workout was scored against.
    func series(covering record: HistoryRecord) -> (series: WorkoutSeries, zones: HeartRateZones?)? {
        workouts.lazy.filter { $0.covers(record) }.compactMap { workout in
            self.series(workout.id).map { ($0, workout.heartRateZones) }
        }.first
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

    /// Picks a filed session back up, and remembers which record it came from so its rounds
    /// count once and anybody told apart in it stays told apart.
    func resume(_ record: HistoryRecord) {
        guard record.state.canResume else { return }
        store.resume(record.state, from: record.id)
        let resumed = store.log.sessionID
        changeLinks { $0.resume(resumed, from: record.id) }
    }

    // MARK: - Players

    private(set) var playerLinks = PlayerLinks()
    private(set) var playerStats: PlayerStats?
    /// Whatever the period: merging and separating are about who somebody is, not about when.
    private(set) var allPlayerStats: PlayerStats?
    @ObservationIgnored private var playerStatsKey: StatsKey?

    var statsPeriod: StatsPeriod = AppModel.savedStatsPeriod {
        didSet {
            guard statsPeriod != oldValue else { return }
            UserDefaults.standard.set(try? JSONCoding.encoder.encode(statsPeriod), forKey: Self.statsPeriodKey)
            Task { await refreshPlayerStats() }
        }
    }

    private static let statsPeriodKey = "playerStatsPeriod"

    private static var savedStatsPeriod: StatsPeriod {
        guard let data = UserDefaults.standard.data(forKey: statsPeriodKey),
              let period = try? JSONCoding.decoder.decode(StatsPeriod.self, from: data)
        else { return .allTime }
        return period
    }

    /// The day is in it so that "Last 7 days" moves on overnight.
    private struct StatsKey: Equatable {
        var revision: Int
        var period: StatsPeriod
        var day: Date
    }

    private var statsKey: StatsKey {
        StatsKey(revision: revision, period: statsPeriod, day: Calendar.current.startOfDay(for: Date()))
    }

    func refreshPlayerStats(onlyIfStale: Bool = false) async {
        guard let sessionStore else { return }
        let key = statsKey
        if onlyIfStale, playerStats != nil, playerStatsKey == key { return }
        let stats = await Self.playerStats(from: sessionStore, links: playerLinks, during: key.period.interval())
        guard key == statsKey else { return }
        allPlayerStats = stats.all
        playerStats = stats.within
        playerStatsKey = key
    }

    @concurrent
    private nonisolated static func playerStats(
        from store: SessionStore, links: PlayerLinks, during period: DateInterval?
    ) async -> (all: PlayerStats, within: PlayerStats) {
        let history = (try? store.history()) ?? []
        let all = PlayerStats.make(from: history, links: links)
        return (all, period == nil ? all : PlayerStats.make(from: history, links: links, during: period))
    }

    @discardableResult
    func merge(_ person: PersonID, into target: PersonID) -> PersonID {
        var kept = target
        changeLinks { kept = $0.merge(person, into: target) }
        return kept
    }

    func unmerge(_ person: PersonID) {
        changeLinks { $0.unmerge(person) }
    }

    @discardableResult
    func separate(_ appearances: [Appearance], note: String) -> PersonID {
        var person = PersonID.separate(UUID())
        changeLinks { person = $0.separate(appearances, note: note) }
        return person
    }

    func move(_ appearances: [Appearance], to person: PersonID) {
        changeLinks { $0.move(appearances, to: person) }
    }

    func setNote(_ note: String, for person: PersonID) {
        changeLinks { $0.setNote(note, for: person) }
    }

    private func changeLinks(_ change: (inout PlayerLinks) -> Void) {
        var updated = playerLinks
        change(&updated)
        guard updated != playerLinks else { return }
        playerLinks = updated
        try? sessionStore?.save(updated)
        revision += 1
        Task { await refreshPlayerStats() }
    }
}
