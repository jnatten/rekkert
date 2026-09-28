import Foundation
@testable import RekkertCore

/// Filed sessions built by hand rather than drawn, so every partnership is the one the test
/// says it is.
enum Filed {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    static func record(_ state: SessionState, day: Int, id: UUID = UUID()) -> HistoryRecord {
        HistoryRecord(
            id: id,
            finishedAt: epoch.addingTimeInterval(Double(day) * 86_400),
            title: state.title,
            state: state
        )
    }

    static func teams(_ a: [String], _ b: [String]) -> BySide<TeamInfo> {
        BySide(a: TeamInfo(name: "Us", players: a), b: TeamInfo(name: "Them", players: b))
    }

    /// Six games to love for `winner`, or two games in and stopped when there is none.
    static func match(_ a: [String], _ b: [String], winner: TeamSide?) -> SessionState {
        var session = TraditionalSession(rules: TraditionalRules(setsToWin: 1), teams: teams(a, b))
        if let winner {
            session.score = session.engine.winGames(6, for: winner, from: session.score)
        } else {
            session.score = session.engine.winGames(2, for: .a, from: session.score)
            session.isStopped = true
        }
        return .traditional(session)
    }

    static func points(_ a: [String], _ b: [String], _ score: BySide<Int>, stopped: Bool = false) -> SessionState {
        .pointCount(PointCountSession(
            rules: PointCountRules(target: 16),
            teams: teams(a, b),
            score: PointCountState(points: score),
            isStopped: stopped
        ))
    }

    static func winnerCourt(
        _ a: [String], _ b: [String],
        rounds: [BySide<Int>], inProgress: BySide<Int> = BySide(both: 0)
    ) -> SessionState {
        var session = WinnerCourtSession(rules: WinnerCourtRules(), teams: teams(a, b), isFinished: true)
        session.score.completedSets = rounds.map { SetResult(games: $0, winner: $0.leader) }
        session.score.games = inProgress
        return .winnerCourt(session)
    }

    static func friendly(_ group: Group, id: FriendlyID = FriendlyID(), rounds: [FriendlyRound]) -> SessionState {
        .friendly(FriendlySession(id: id, name: "Friday", players: group.players, rounds: rounds, isFinished: true))
    }

    static func round(
        _ index: Int, _ a: [PlayerID], _ b: [PlayerID], winner: TeamSide?, sitOuts: [PlayerID] = []
    ) -> FriendlyRound {
        let engine = TraditionalEngine(rules: TraditionalRules(setsToWin: 1))
        let score = winner.map { engine.winGames(6, for: $0, from: TraditionalState()) }
            ?? engine.winGames(2, for: .a, from: TraditionalState())
        return FriendlyRound(index: index, teams: BySide(a: a, b: b), sitOuts: sitOuts, score: score, isStopped: winner == nil)
    }

    static func tournament(
        _ group: Group, id: TournamentID = TournamentID(),
        format: TournamentFormat = .americano, rounds: [Round]
    ) -> SessionState {
        .tournament(Tournament(
            id: id, name: "Thursday", format: format, players: group.players,
            config: TournamentConfig(pointRules: PointCountRules(target: 16)),
            rounds: rounds, isFinished: true
        ))
    }

    static func court(
        _ a: [PlayerID], _ b: [PlayerID], _ points: BySide<Int>, index: Int = 0, confirmed: Bool = false
    ) -> CourtMatch {
        CourtMatch(courtIndex: index, teams: BySide(a: a, b: b), state: PointCountState(points: points), isConfirmed: confirmed)
    }
}

struct Group {
    let players: [Player]

    init(_ names: String...) {
        players = names.map { Player(name: $0) }
    }

    subscript(_ indices: Int...) -> [PlayerID] {
        indices.map { players[$0].id }
    }
}

extension BySide where Value == Int {
    static func score(_ a: Int, _ b: Int) -> BySide<Int> { BySide(a: a, b: b) }
}

extension PlayerStats {
    func named(_ name: String) -> PersonStats? { person(.named(name)) }
}
