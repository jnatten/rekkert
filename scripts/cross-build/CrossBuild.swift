import Foundation
import Testing
import RekkertCore
@testable import RekkertSync

// Compiled into a build exported by scripts/cross-build.sh, any build since sit-outs could be
// picked (25 September 2026), and driven by its environment. It uses only what every such build
// has: `MatchStore`, `LoopbackTransport`, `SessionReducer` and `JSONCoding`.

nonisolated private let env = ProcessInfo.processInfo.environment
nonisolated private let dir = URL(fileURLWithPath: env["XVER_DIR"] ?? ".")
nonisolated private let build = env["XVER_BUILD"] ?? "?"

private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))! }

private func setup(_ format: TournamentFormat) -> Tournament {
    Tournament(
        id: TournamentID(uuid(0xFF)), name: "Thursday", format: format,
        players: (0 ..< Int(env["XVER_PLAYERS"] ?? "9")!).map { Player(id: PlayerID(uuid(0x1000 + $0)), name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
    )
}

@MainActor
private func makeStore(_ log: MatchLog, device: Int) -> MatchStore {
    let (one, _) = LoopbackTransport.pair()
    return MatchStore(
        device: DeviceID(uuid(0xD00 + device)), transport: one, session: ActiveSession(log: log),
        snapshotInterval: 0, retryInterval: .seconds(4)
    )
}

private func tournament(_ state: SessionState?) -> Tournament? {
    guard case .tournament(let t)? = state else { return nil }
    return t
}

/// Each round as the courts and the bench it put people on, by name.
private func draws(_ state: SessionState?) -> [String] {
    guard let t = tournament(state) else { return [] }
    func names(_ ids: [PlayerID]) -> String { ids.compactMap { t.player($0)?.name }.joined(separator: "+") }
    return t.rounds.map { round in
        let courts = round.matches.sorted { $0.courtIndex < $1.courtIndex }.map { "\(names($0.teams.a)) v \(names($0.teams.b))" }
        return courts.joined(separator: " | ") + " / out " + round.sitOuts.compactMap { t.player($0)?.name }.sorted().joined(separator: "+")
    }
}

/// Partnerships repeated within the first turn: the rounds in which every partnership can be new.
private func repeatedInTheTurn(_ state: SessionState?) -> Int {
    guard let t = tournament(state) else { return 0 }
    let turn = t.players.count * (t.players.count - 1) / 2 / (t.playableCourts * 2)
    var seen: Set<Set<PlayerID>> = []
    return t.rounds.prefix(turn).flatMap { $0.matches.flatMap { [Set($0.teams.a), Set($0.teams.b)] } }.count { !seen.insert($0).inserted }
}

private func write(_ value: some Encodable, _ name: String) throws {
    try JSONCoding.encoder.encode(value).write(to: dir.appendingPathComponent(name))
}

private func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONCoding.decoder.decode(type, from: Data(contentsOf: dir.appendingPathComponent(name)))
}

private func save(_ store: MatchStore, _ name: String) throws {
    let state = SessionReducer.state(of: store.log)
    try write(store.log, "\(name)-log.json")
    try write(draws(state), "\(name)-draws.json")
}

/// Folds a log another build wrote and compares every round with what that build made of it.
private func fold(_ name: String) throws -> MatchLog {
    let log = try read(MatchLog.self, "\(name)-log.json")
    let theirs = try read([String].self, "\(name)-draws.json")
    let ours = draws(SessionReducer.state(of: log))
    let differing = zip(ours, theirs).count { $0 != $1 } + abs(ours.count - theirs.count)
    print("XVER [\(build)] folded \(name): \(ours.count) rounds, \(differing) differing")
    for (index, pair) in zip(ours, theirs).enumerated() where pair.0 != pair.1 {
        print("XVER   round \(index + 1) here:  \(pair.0)")
        print("XVER   round \(index + 1) there: \(pair.1)")
    }
    #expect(differing == 0)
    return log
}

@MainActor
private func play(_ store: MatchStore, rounds: Int, redrawLast: Bool) {
    for round in 0 ..< rounds {
        store.nextRound()
        guard let t = tournament(store.state), let current = t.currentRound else { continue }
        if redrawLast, round == rounds - 1, let late = t.players.map(\.id).first(where: { !current.sitOuts.contains($0) }) {
            store.redrawRound(sittingOut: [late])
        }
        guard let drawn = tournament(store.state), drawn.format == .mexicano, let now = drawn.currentRound else { continue }
        for match in now.matches { store.setScore(round: now.index, court: match.courtIndex, points: BySide(a: 9, b: 7)) }
        store.setRoundConfirmed(now.index, true)
    }
}

@Suite("Cross-build", .serialized)
@MainActor
struct CrossBuild {
    @Test func run() throws {
        for format in [TournamentFormat.americano, .mexicano] {
            let from = "\(format)-\(env["XVER_FROM"] ?? "")", to = "\(format)-\(env["XVER_TO"] ?? "")"
            switch env["XVER_ACTION"] ?? "" {
            case "record":
                let store = makeStore(MatchLog(sessionID: uuid(0x44)), device: 1)
                store.configure(.tournament(setup(format)))
                play(store, rounds: 10, redrawLast: true)
                play(store, rounds: 5, redrawLast: false)
                try save(store, to)
                print("XVER [\(build)] recorded \(to): partners repeated within the first turn \(repeatedInTheTurn(SessionReducer.state(of: store.log)))")
            case "continue":
                let store = makeStore(try fold(from), device: Int(env["XVER_DEVICE"] ?? "2")!)
                play(store, rounds: Int(env["XVER_ROUNDS"] ?? "1")!, redrawLast: true)
                try save(store, to)
                print("XVER [\(build)] drew on to \(to): \(draws(SessionReducer.state(of: store.log)).count) rounds")
            case "fold":
                _ = try fold(from)
            default:
                Issue.record("XVER_ACTION is record, continue or fold")
            }
        }
    }
}
