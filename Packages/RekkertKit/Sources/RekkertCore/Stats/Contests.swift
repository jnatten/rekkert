import Foundation

/// One game-up with a result: a match, a round, a court. `winner` is nil for a draw.
struct Contest: Sendable, Hashable {
    var sides: BySide<[Seat]>
    var winner: TeamSide?
    var points: BySide<Int>?
    var format: TournamentFormat?
    /// Winner court only tracks this side of the net; whoever was across it changed at every
    /// whistle, so it says nothing about who beat whom.
    var countsHeadToHead: Bool
}

struct FiledSession: Sendable {
    var record: HistoryRecord
    var seats: [(seat: Seat, name: String)]
    var contests: [Contest]

    init(_ record: HistoryRecord) {
        self.record = record
        switch record.state {
        case .traditional(let session):
            seats = Self.seats(session.teams, in: record.id)
            contests = session.score.winner.map { [Self.contest(session.teams, in: record.id, winner: $0)] } ?? []

        case .pointCount(let session):
            seats = Self.seats(session.teams, in: record.id)
            contests = session.engine.isFinished(session.score)
                ? [Self.contest(session.teams, in: record.id, winner: session.score.points.leader)]
                : []

        case .winnerCourt(let session):
            seats = Self.seats(session.teams, in: record.id)
            contests = session.completedRounds.map { round in
                var contest = Self.contest(session.teams, in: record.id, winner: round.winner)
                contest.countsHeadToHead = false
                return contest
            }

        case .friendly(let session):
            let named = Self.named(session.players)
            seats = session.players.compactMap { player in named[player.id].map { (.player(player.id), $0) } }
            contests = session.rounds.compactMap { round in
                guard let winner = round.score.winner else { return nil }
                return Contest(
                    sides: round.teams.map { Self.seats($0, named: named) },
                    winner: winner, countsHeadToHead: true
                )
            }

        case .tournament(let tournament):
            let named = Self.named(tournament.players)
            let engine = PointCountEngine(rules: tournament.config.pointRules)
            seats = tournament.players.compactMap { player in named[player.id].map { (.player(player.id), $0) } }
            contests = tournament.rounds.filter { !$0.isCancelled }.flatMap { round in
                round.matches
                    .filter { ($0.isConfirmed || engine.isFinished($0.state)) && $0.state.points.total > 0 }
                    .map { match in
                        Contest(
                            sides: match.teams.map { Self.seats($0, named: named) },
                            winner: match.state.points.leader,
                            points: match.state.points,
                            format: tournament.format,
                            countsHeadToHead: true
                        )
                    }
            }
        }
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func named(_ players: [Player]) -> [PlayerID: String] {
        Dictionary(
            players.map { ($0.id, trimmed($0.name)) }.filter { !$0.1.isEmpty },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func seats(_ ids: [PlayerID], named: [PlayerID: String]) -> [Seat] {
        ids.filter { named[$0] != nil }.map { .player($0) }
    }

    private static func slots(_ team: TeamInfo, side: TeamSide, in record: UUID) -> [(seat: Seat, name: String)] {
        team.players.enumerated()
            .map { (seat: Seat.slot(record: record, side: side, index: $0.offset), name: trimmed($0.element)) }
            .filter { !$0.name.isEmpty }
    }

    private static func seats(_ teams: BySide<TeamInfo>, in record: UUID) -> [(seat: Seat, name: String)] {
        slots(teams.a, side: .a, in: record) + slots(teams.b, side: .b, in: record)
    }

    private static func contest(_ teams: BySide<TeamInfo>, in record: UUID, winner: TeamSide?) -> Contest {
        Contest(
            sides: BySide(
                a: slots(teams.a, side: .a, in: record).map(\.seat),
                b: slots(teams.b, side: .b, in: record).map(\.seat)
            ),
            winner: winner,
            countsHeadToHead: true
        )
    }

    /// Newest first, with the copies a resume leaves behind taken out: a tournament or friendly
    /// picked up again keeps its id and so carries every round of the copy it came from, and
    /// any other mode is known to have been picked up only by what the links recorded.
    static func counted(_ records: [HistoryRecord], links: PlayerLinks) -> [HistoryRecord] {
        let continued = Set(records.compactMap { links.resumed[$0.id] })
        var lineages: Set<UUID> = []
        return records
            .sorted { $0.finishedAt > $1.finishedAt }
            .filter { record in
                guard !continued.contains(record.id) else { return false }
                guard let lineage = record.state.lineage else { return true }
                return lineages.insert(lineage).inserted
            }
    }
}

extension SessionState {
    fileprivate var lineage: UUID? {
        switch self {
        case .tournament(let tournament): tournament.id.raw
        case .friendly(let session): session.id.raw
        case .traditional, .pointCount, .winnerCourt: nil
        }
    }
}
