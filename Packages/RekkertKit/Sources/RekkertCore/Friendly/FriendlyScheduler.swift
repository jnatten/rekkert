import Foundation

public enum FriendlyError: Error, Sendable, Hashable {
    case notEnoughPlayers(needed: Int, have: Int)
}

/// Draws the partnerships for the next round of a friendly.
///
/// Seeded on the session id and the round number, so the phone and the watch fold the same
/// event log into the same draw without ever having to agree about it. The draw reads the
/// teams and the bench of the rounds already played and nothing else — never the scores — so
/// correcting or undoing a point cannot re-partner a round that has already been drawn.
public enum FriendlyScheduler {
    public static func appendingRound(to session: FriendlySession) throws -> FriendlySession {
        var next = session
        next.rounds.append(try nextRound(for: session))
        return next
    }

    public static func nextRound(for session: FriendlySession) throws -> FriendlyRound {
        guard session.canPlay else {
            throw FriendlyError.notEnoughPlayers(needed: 2, have: session.players.count)
        }

        let index = session.rounds.count
        var history = PairingHistory()
        for round in session.rounds {
            history.record([round.teams], sitOuts: round.sitOuts)
        }
        var generator = SeededGenerator(session.id.raw, salt: UInt64(index))

        let teams: BySide<[PlayerID]>
        let sitting: [PlayerID]

        if session.players.count == 2 {
            // Nothing to decide, and shuffling anyway would swap the two of them between the
            // colours every round, which reads as a bug rather than as a draw.
            teams = BySide(a: [session.players[0].id], b: [session.players[1].id])
            sitting = []
        } else if let replay = replayedTeams(for: session) {
            teams = replay
            sitting = []
        } else {
            let split = RoundScheduler.split(
                players: session.players, seats: session.seats,
                history: history, generator: &generator
            )
            sitting = split.sitting
            teams = session.teamSize == 1
                // The bench has already made the only choice there is: whoever is left plays.
                ? BySide(a: [split.playing[0]], b: [split.playing[1]])
                : PairingSearch.teams(from: split.playing, courts: 1, history: history)[0]
        }

        return FriendlyRound(
            index: index,
            teams: teams,
            sitOuts: sitting,
            // Moves the first serve of the evening around instead of handing it to the same
            // slot every round.
            score: TraditionalState(firstServerIndex: index % ServeRotation.order.count)
        )
    }

    /// Four pair up in only three ways, and the draw gets through all three in as many rounds.
    /// From then on every candidate costs the same and the shuffle alone would decide, so each
    /// block of three would come out in a fresh order. Instead the partition played least is
    /// replayed as it stood, sides and all, ties going to the one that came up first: round
    /// four is round one again. Nil for any other number of players, and while a fresh
    /// partition is still to be had, so the ordinary draw runs exactly as before.
    private static func replayedTeams(for session: FriendlySession) -> BySide<[PlayerID]>? {
        guard session.players.count == 4 else { return nil }
        let four = Set(session.players.map(\.id))

        // The list can be corrected mid-session, so only rounds that were a partition of
        // exactly these four count.
        var seen: [Set<PairKey>: (plays: Int, first: Int, teams: BySide<[PlayerID]>)] = [:]
        for (position, round) in session.rounds.enumerated()
        where round.teams.a.count == 2 && round.teams.b.count == 2
            && Set(round.teams.a + round.teams.b) == four
        {
            let key: Set<PairKey> = [
                PairKey(round.teams.a[0], round.teams.a[1]),
                PairKey(round.teams.b[0], round.teams.b[1]),
            ]
            if seen[key] == nil { seen[key] = (plays: 0, first: position, teams: round.teams) }
            seen[key]?.plays += 1
        }

        // Three ways to split four into pairs. `first` differs between them, so the minimum is
        // unique and the dictionary's order cannot leak into the draw.
        guard seen.count == 3 else { return nil }
        return seen.values.min { ($0.plays, $0.first) < ($1.plays, $1.first) }?.teams
    }
}
