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
    let announcer = ScoreAnnouncer()
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

        let store = MatchStore(
            device: DeviceIdentity.current(),
            transport: links,
            store: persistence,
            session: try? persistence?.loadActive(),
            keepsHistory: AppModel.keepsHistory
        )
        self.store = store
        sharing = SharedSession(store: store, link: localNetwork)
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
        #if DEBUG
        seedDemoIfRequested()
        #endif
    }

    #if DEBUG
    /// `-rekkert-demo traditional|americano|mexicano` seeds a session at launch. simctl
    /// cannot tap, so this is how the watch/phone sync path gets verified headlessly.
    private func seedDemoIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-rekkert-demo-presets") {
            store.savePreset(Preset(name: "Thursday americano", configuration: .tournament(
                format: .americano, name: "Thursday",
                players: ["Jonas", "Ada", "Kim", "Sam", "Ola", "Siri", "Tor", "Bjørn"].map { Player(name: $0) },
                config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
            )))
            store.savePreset(Preset(name: "Vinnerbane", configuration: .winnerCourt(
                rules: WinnerCourtRules(deuceRule: .goldenPoint),
                teams: BySide(a: TeamInfo(name: "Us"), b: TeamInfo(name: "Them"))
            )))
            store.savePreset(Preset(name: "Best of 3", configuration: .traditional(
                rules: TraditionalRules(deuceRule: .starPoint),
                teams: BySide(a: TeamInfo(name: "Us"), b: TeamInfo(name: "Them"))
            )))
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
                rules: TraditionalRules(deuceRule: .starPoint),
                teams: BySide(
                    a: TeamInfo(name: "Blues", players: ["Jonas", "Ada"]),
                    b: TeamInfo(name: "Oranges", players: ["Kim", "Sam"])
                )
            ))
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
        #if os(iOS)
        // `-rekkert-share-host H7K3MR` starts sharing on a pinned code, so two simulators can
        // be pointed at each other from a script.
        if let index = arguments.firstIndex(of: "-rekkert-share-host"),
           index + 1 < arguments.count,
           let code = SessionCode(arguments[index + 1]) {
            sharing.host(code: code)
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

    func becameActive() {
        // Sharing does not survive being put down: the system takes the listener away with
        // the app, so coming back to the front is when it has to be stood up again.
        sharing.resume()
        Task { [store] in await store.synchronise() }
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

    var history: [HistoryRecord] {
        (try? sessionStore?.history()) ?? []
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
    }
}
