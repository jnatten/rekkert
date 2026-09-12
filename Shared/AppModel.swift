import Foundation
import Observation
import RekkertCore
import RekkertSync

@Observable
final class AppModel {
    let store: MatchStore
    private let sessionStore: SessionStore?
    private var runTask: Task<Void, Never>?

    init() {
        let persistence = try? SessionStore.applicationSupport()
        sessionStore = persistence
        store = MatchStore(
            device: DeviceIdentity.current(),
            transport: AppModel.makeTransport(),
            store: persistence,
            session: try? persistence?.loadActive()
        )
    }

    private static func makeTransport() -> any PeerTransport {
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
        guard let flag = arguments.firstIndex(of: "-rekkert-demo"), flag + 1 < arguments.count else { return }
        store.startNewSession()

        switch arguments[flag + 1] {
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
        Task { [store] in await store.synchronise() }
    }

    var history: [HistoryRecord] {
        (try? sessionStore?.history()) ?? []
    }

    /// Archives the finished session and clears the slate for the next one.
    func archiveAndReset() {
        if let state = store.state {
            try? sessionStore?.archive(HistoryRecord(title: state.title, state: state))
        }
        try? sessionStore?.clearActive()
        store.startNewSession()
    }

    /// Throws the current session away without archiving it. Used when nothing has been
    /// played, so there is nothing worth keeping.
    func discard() {
        try? sessionStore?.clearActive()
        store.startNewSession()
    }

    func deleteHistory(_ id: UUID) {
        try? sessionStore?.deleteHistory(id)
    }
}
