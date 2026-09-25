import Foundation

/// A filed session, point by point: what each event did to the score, and when.
///
/// Built from the log at the moment the session is filed, because the log is not kept. It is
/// read off the board rather than off the events: every event is folded, and an entry is
/// written wherever a court's score moved. So a whistle, a typed score or a settled one leaves
/// its mark like a point does, a point the reducer turned away leaves none, and the last entry
/// on every court is the score that was filed.
public struct MatchTimeline: Sendable, Hashable {
    public struct Board: Codable, Sendable, Hashable {
        public var points: BySide<String>
        /// Games in the set under way, for the modes that play games.
        public var games: BySide<Int>?
        /// Games in each set, or winner-court round, already over.
        public var sets: [BySide<Int>]

        public init(points: BySide<String>, games: BySide<Int>? = nil, sets: [BySide<Int>] = []) {
            self.points = points
            self.games = games
            self.sets = sets
        }

        var isBlank: Bool {
            points.a == "0" && points.b == "0" && (games.map { $0.a == 0 && $0.b == 0 } ?? true) && sets.isEmpty
        }
    }

    public enum Kind: Sendable, Hashable {
        case point(TeamSide)
        /// The winner-court whistle, which hands the game in progress to whoever leads it.
        case whistle
        /// A score typed in, or the setup put right.
        case corrected
        /// The score replaced wholesale, by the host settling it or by a session picked back up.
        case settled
    }

    public enum Ended: Sendable, Hashable {
        case game(TeamSide)
        /// `nil` for a winner-court round the whistle closed level.
        case set(TeamSide?)
        case match(TeamSide?)
    }

    public struct Entry: Sendable, Hashable {
        public var at: Date?
        public var kind: Kind
        /// The round: a tournament or friendly round, or how many winner-court rounds were
        /// already over. Zero for a match or a points round.
        public var round: Int
        public var court: Int
        public var board: Board
        /// Who served the point, for a point.
        public var server: TeamSide?
        /// Whether the point was a golden or star point: the one that decides the game.
        public var wasSuddenDeath: Bool
        public var wasTiebreak: Bool
        public var ended: Ended?

        public init(
            at: Date?, kind: Kind, round: Int = 0, court: Int = 0, board: Board,
            server: TeamSide? = nil, wasSuddenDeath: Bool = false, wasTiebreak: Bool = false,
            ended: Ended? = nil
        ) {
            self.at = at
            self.kind = kind
            self.round = round
            self.court = court
            self.board = board
            self.server = server
            self.wasSuddenDeath = wasSuddenDeath
            self.wasTiebreak = wasTiebreak
            self.ended = ended
        }

        public var winner: TeamSide? {
            if case .point(let side) = kind { side } else { nil }
        }

        /// A game won against the serve. Not in a tiebreak, where the serve changes hands
        /// every other point.
        public var isBreak: Bool {
            guard let winner, let server, !wasTiebreak, let ended else { return false }
            switch ended {
            case .game, .set, .match: return winner != server
            }
        }
    }

    public var entries: [Entry]
    /// Who the phone's owner said they were, so a tournament can be read from their court.
    public var me: PlayerID?
    /// When a filed session was picked back up. The stretches either side are drawn apart.
    public var resumedAt: [Date]

    public init(entries: [Entry] = [], me: PlayerID? = nil, resumedAt: [Date] = []) {
        self.entries = entries
        self.me = me
        self.resumedAt = resumedAt
    }

    public var isEmpty: Bool { entries.isEmpty }
}

// MARK: - Building

extension MatchTimeline {
    struct Slot: Hashable, Comparable {
        var round: Int
        var court: Int

        static func < (lhs: Slot, rhs: Slot) -> Bool { (lhs.round, lhs.court) < (rhs.round, rhs.court) }
    }

    /// `carry` is what was played before this log began: a result taken back, or a filed
    /// session picked up again. Its last scores are where this log's opening restore is
    /// measured from, so the restore only leaves a mark where it changed something.
    public static func make(from log: MatchLog, continuing carry: TimelineCarry? = nil, me: PlayerID? = nil) -> MatchTimeline {
        var timeline = carry?.timeline ?? MatchTimeline()
        timeline.me = me ?? timeline.me

        // A winner-court session is one board however many whistles it has heard, where its
        // entries count the rounds; the opening restore says which kind this is.
        var isWinnerCourt = false
        if case .restore(.winnerCourt)? = log.effectiveEvents.first?.kind { isWinnerCourt = true }
        var last: [Slot: Board] = [:]
        for entry in timeline.entries {
            last[isWinnerCourt ? Slot(round: 0, court: 0) : Slot(round: entry.round, court: entry.court)] = entry.board
        }

        var state: SessionState?
        for (index, event) in log.effectiveEvents.enumerated() {
            let before = state
            SessionReducer.apply(event.kind, to: &state)
            guard let after = state else { continue }

            if index == 0, case .restore = event.kind, carry?.reason == .resumed, let at = event.at {
                timeline.resumedAt.append(at)
            }
            for (slot, board) in boards(of: after).sorted(by: { $0.key < $1.key }) {
                let previous = last[slot]
                last[slot] = board
                if previous == nil, board.isBlank { continue }
                guard previous != board else { continue }
                timeline.entries.append(entry(for: event, slot: slot, board: board, before: before, after: after))
            }
        }
        return timeline
    }

    static func boards(of state: SessionState) -> [Slot: Board] {
        switch state {
        case .traditional(let session):
            [Slot(round: 0, court: 0): board(session.score, engine: session.engine)]
        case .winnerCourt(let session):
            [Slot(round: 0, court: 0): board(session.score, engine: session.engine)]
        case .pointCount(let session):
            [Slot(round: 0, court: 0): Board(points: session.score.points.map(String.init))]
        case .friendly(let session):
            Dictionary(uniqueKeysWithValues: session.rounds.map { round in
                (Slot(round: round.index, court: 0), board(round.score, engine: session.engine))
            })
        case .tournament(let tournament):
            Dictionary(uniqueKeysWithValues: tournament.rounds.flatMap { round in
                round.matches.map { match in
                    (Slot(round: round.index, court: match.courtIndex), Board(points: match.state.points.map(String.init)))
                }
            })
        }
    }

    private static func board(_ score: TraditionalState, engine: TraditionalEngine) -> Board {
        Board(
            points: engine.pointDisplay(score).map(\.text),
            games: score.games,
            sets: score.completedSets.map(\.games)
        )
    }

    private static func entry(for event: MatchEvent, slot: Slot, board: Board, before: SessionState?, after: SessionState) -> Entry {
        let kind: Kind = switch event.kind {
        case .point(_, _, let team): .point(team)
        case .endRound: .whistle
        case .restore: .settled
        default: .corrected
        }
        var entry = Entry(at: event.at, kind: kind, round: slot.round, court: slot.court, board: board)

        let previous = before.flatMap { traditional(of: $0, slot: slot) }
        let current = traditional(of: after, slot: slot)
        if case .winnerCourt = after, let previous {
            entry.round = previous.score.completedSets.count
        }
        if case .point = kind, let before {
            entry.server = before.serve(round: slot.round, court: slot.court)?.slot.team
            if let previous {
                entry.wasSuddenDeath = previous.engine.isSuddenDeathPoint(previous.score)
                if case .tiebreak = previous.engine.phase(previous.score) { entry.wasTiebreak = true }
            }
        }
        if let previous, let current {
            entry.ended = ended(from: previous.score, to: current.score, engine: current.engine, by: entry.winner)
        } else if let finish = pointCountFinish(of: after, slot: slot), before.flatMap({ pointCountFinish(of: $0, slot: slot) }) == nil {
            entry.ended = .match(finish.winner)
        }
        return entry
    }

    private static func ended(from before: TraditionalState, to after: TraditionalState, engine: TraditionalEngine, by winner: TeamSide?) -> Ended? {
        if before.winner == nil, after.winner != nil { return .match(after.winner) }
        if after.completedSets.count > before.completedSets.count { return .set(after.completedSets.last?.winner) }
        if engine.totalGamesPlayed(after) > engine.totalGamesPlayed(before), let side = gameWinner(from: before, to: after) ?? winner {
            return .game(side)
        }
        return nil
    }

    private static func gameWinner(from before: TraditionalState, to after: TraditionalState) -> TeamSide? {
        TeamSide.allCases.first { after.games[$0] > before.games[$0] }
    }

    private static func traditional(of state: SessionState, slot: Slot) -> (engine: TraditionalEngine, score: TraditionalState)? {
        switch state {
        case .traditional(let session): (session.engine, session.score)
        case .winnerCourt(let session): (session.engine, session.score)
        case .friendly(let session): session.round(at: slot.round).map { (session.engine, $0.score) }
        case .pointCount, .tournament: nil
        }
    }

    private struct Finish: Equatable {
        var winner: TeamSide?
    }

    /// A finished points round or tournament court, and who took it.
    private static func pointCountFinish(of state: SessionState, slot: Slot) -> Finish? {
        switch state {
        case .pointCount(let session):
            session.engine.isFinished(session.score) ? Finish(winner: session.engine.winner(session.score)) : nil
        case .tournament(let tournament):
            tournament.round(at: slot.round)?.matches.first { $0.courtIndex == slot.court }.flatMap { match in
                let engine = PointCountEngine(rules: tournament.config.pointRules)
                return engine.isFinished(match.state) ? Finish(winner: engine.winner(match.state)) : nil
            }
        case .traditional, .winnerCourt, .friendly:
            nil
        }
    }
}

// MARK: - Reading

extension MatchTimeline {
    public struct Stats: Sendable, Hashable {
        public var pointsWon = BySide(both: 0)
        public var longestRun = BySide(both: 0)
        public var suddenDeathWon = BySide(both: 0)
        public var breaks = BySide(both: 0)

        public var suddenDeathPlayed: Int { suddenDeathWon.a + suddenDeathWon.b }
    }

    /// The entries of one round, or one court of it, or all of them.
    public func entries(round: Int? = nil, court: Int? = nil) -> [Entry] {
        entries.filter { entry in
            (round.map { entry.round == $0 } ?? true) && (court.map { entry.court == $0 } ?? true)
        }
    }

    /// A run is broken by the other side taking a point, and by the court or the round
    /// changing under it.
    public func stats(round: Int? = nil, court: Int? = nil) -> Stats {
        var stats = Stats()
        var run: (side: TeamSide, round: Int, court: Int, length: Int)?

        for entry in entries(round: round, court: court) {
            guard let winner = entry.winner else { continue }
            stats.pointsWon[winner] += 1
            if entry.wasSuddenDeath { stats.suddenDeathWon[winner] += 1 }
            if entry.isBreak { stats.breaks[winner] += 1 }

            if let current = run, current.side == winner, current.round == entry.round, current.court == entry.court {
                run?.length += 1
            } else {
                run = (winner, entry.round, entry.court, 1)
            }
            if let run { stats.longestRun[winner] = max(stats.longestRun[winner], run.length) }
        }
        return stats
    }

    public struct Lead: Sendable, Hashable {
        public var entry: Entry
        /// Points won by side A less points won by side B, from the start of the selection.
        public var lead: Int
    }

    /// The running point difference, one step per point.
    public func momentum(round: Int? = nil, court: Int? = nil) -> [Lead] {
        var lead = 0
        return entries(round: round, court: court).compactMap { entry in
            guard let winner = entry.winner else { return nil }
            lead += winner == .a ? 1 : -1
            return Lead(entry: entry, lead: lead)
        }
    }
}

// MARK: - Coding

/// Compact on disk: a long match is a few hundred of these, so times are offsets from the
/// first one, pairs are two-element arrays, and anything at its default is left out.
extension MatchTimeline: Codable {
    private enum CodingKeys: String, CodingKey { case version, origin, entries, me, resumedAt }

    private struct Stored: Codable {
        var t: Double?
        var k: String
        var r: Int?
        var c: Int?
        var p: [String]
        var g: [Int]?
        var x: [[Int]]?
        var s: String?
        var sd: Bool?
        var tb: Bool?
        var e: String?
        var w: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try container.decodeIfPresent(Date.self, forKey: .origin)
        let stored = try container.decodeIfPresent([Stored].self, forKey: .entries) ?? []
        entries = stored.compactMap { Self.entry(from: $0, origin: origin) }
        me = try container.decodeIfPresent(PlayerID.self, forKey: .me)
        resumedAt = try container.decodeIfPresent([Date].self, forKey: .resumedAt) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let origin = entries.lazy.compactMap(\.at).first
        try container.encode(1, forKey: .version)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(entries.map { Self.stored($0, origin: origin) }, forKey: .entries)
        try container.encodeIfPresent(me, forKey: .me)
        if !resumedAt.isEmpty { try container.encode(resumedAt, forKey: .resumedAt) }
    }

    private static func stored(_ entry: Entry, origin: Date?) -> Stored {
        let (kind, ended, endedBy): (String, String?, TeamSide?) = {
            let kind = switch entry.kind {
            case .point(let side): side.rawValue
            case .whistle: "w"
            case .corrected: "c"
            case .settled: "s"
            }
            return switch entry.ended {
            case .game(let side): (kind, "g", side)
            case .set(let side): (kind, "s", side)
            case .match(let side): (kind, "m", side)
            case nil: (kind, nil, nil)
            }
        }()
        return Stored(
            t: zip(entry.at, origin).map { (($0.timeIntervalSince($1)) * 10).rounded() / 10 },
            k: kind,
            r: entry.round == 0 ? nil : entry.round,
            c: entry.court == 0 ? nil : entry.court,
            p: [entry.board.points.a, entry.board.points.b],
            g: entry.board.games.map { [$0.a, $0.b] },
            x: entry.board.sets.isEmpty ? nil : entry.board.sets.map { [$0.a, $0.b] },
            s: entry.server?.rawValue,
            sd: entry.wasSuddenDeath ? true : nil,
            tb: entry.wasTiebreak ? true : nil,
            e: ended,
            w: endedBy?.rawValue
        )
    }

    private static func entry(from stored: Stored, origin: Date?) -> Entry? {
        let kind: Kind
        switch stored.k {
        case "a": kind = .point(.a)
        case "b": kind = .point(.b)
        case "w": kind = .whistle
        case "c": kind = .corrected
        case "s": kind = .settled
        default: return nil
        }
        guard stored.p.count == 2 else { return nil }
        let pair: ([Int]) -> BySide<Int>? = { $0.count == 2 ? BySide(a: $0[0], b: $0[1]) : nil }
        let endedBy = stored.w.flatMap(TeamSide.init(rawValue:))
        let ended: Ended? = switch stored.e {
        case "g": endedBy.map(Ended.game)
        case "s": .set(endedBy)
        case "m": .match(endedBy)
        default: nil
        }
        return Entry(
            at: zip(stored.t, origin).map { $1.addingTimeInterval($0) },
            kind: kind,
            round: stored.r ?? 0,
            court: stored.c ?? 0,
            board: Board(
                points: BySide(a: stored.p[0], b: stored.p[1]),
                games: stored.g.flatMap(pair),
                sets: (stored.x ?? []).compactMap(pair)
            ),
            server: stored.s.flatMap(TeamSide.init(rawValue:)),
            wasSuddenDeath: stored.sd ?? false,
            wasTiebreak: stored.tb ?? false,
            ended: ended
        )
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
