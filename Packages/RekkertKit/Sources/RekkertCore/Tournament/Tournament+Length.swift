/// How far a tournament has got through the length it was given.
public struct TournamentPlan: Sendable, Hashable {
    public let length: TournamentLength
    /// Rounds that count and are behind the players: earlier ones, and the one in play once done.
    public let roundsPlayed: Int
    /// Full rotation only: pairs among today's players that no drawn round has partnered.
    public let partnershipsLeft: Int?
    /// The round whose draw completes the plan, once it has been drawn.
    public let finalRound: Int?
    public let isReached: Bool
    /// The final round while it is still the one in play, played out, in a tournament not
    /// yet finished: the moment to ask whether to finish.
    public let finishPromptRound: Int?

    public var progress: String {
        switch length {
        case .rounds(let count):
            if isReached {
                return count == 1 ? "The planned round is played" : "All \(count) planned rounds played"
            }
            let planned = count == 1 ? "1 round planned" : "\(count) rounds planned"
            if roundsPlayed == 0, finalRound == nil { return planned }
            if finalRound != nil { return "\(planned) · this is the last one" }
            return "\(planned) · \(count - roundsPlayed) to go"
        case .fullRotation:
            if isReached { return "Full rotation done: everyone has partnered everyone" }
            if finalRound != nil { return "Full rotation · everyone has partnered everyone after this round" }
            let left = partnershipsLeft ?? 0
            return "Full rotation · \(left) \(left == 1 ? "partnership" : "partnerships") to go"
        }
    }

    /// The fewest rounds in which everybody can partner everybody: each court pairs off two
    /// partnerships a round. Nil when there are not four players for a court.
    public static func fewestRounds(players: Int, courts: Int) -> Int? {
        let playable = min(courts, players / 4)
        guard playable >= 1 else { return nil }
        let pairs = players * (players - 1) / 2
        let perRound = playable * 2
        return (pairs + perRound - 1) / perRound
    }
}

extension TournamentConfig {
    /// The length a tournament of that format is actually played to: none for a ladder, and
    /// none for a full rotation of a Mexicano, which pairs off the table and has no rotation
    /// to complete.
    public func length(for format: TournamentFormat) -> TournamentLength? {
        switch (format, length) {
        case (.winnerCourt, _), (_, nil): nil
        case (.mexicano, .fullRotation?): nil
        case (_, .rounds(let count)?): count >= 1 ? .rounds(count) : nil
        case (.americano, .fullRotation?): .fullRotation
        }
    }
}

extension Tournament {
    public var length: TournamentLength? { config.length(for: format) }

    public var plan: TournamentPlan? {
        guard let length else { return nil }
        let counted = rounds.filter { !$0.isCancelled }

        var partnershipsLeft: Int?
        let finalRound: Int?
        switch length {
        case .rounds(let count):
            finalRound = counted.dropFirst(count - 1).first?.index
        case .fullRotation:
            let ids = Set(players.map(\.id))
            var unpaired = Set(ids.flatMap { one in ids.filter { one < $0 }.map { PairKey(one, $0) } })
            var completedBy: Int?
            for round in counted where !unpaired.isEmpty {
                for match in round.matches {
                    for side in TeamSide.allCases where match.teams[side].count == 2 {
                        unpaired.remove(PairKey(match.teams[side][0], match.teams[side][1]))
                    }
                }
                if unpaired.isEmpty { completedBy = round.index }
            }
            partnershipsLeft = unpaired.count
            finalRound = completedBy
        }

        let latest = currentRound
        let latestIsDone = latest.map { !$0.isCancelled && isDone($0) } ?? false
        let isReached = finalRound.map { $0 < latestRoundIndex || latestIsDone } ?? false
        let roundsPlayed = counted.filter { $0.index < latestRoundIndex }.count + (latestIsDone ? 1 : 0)
        let prompt = !isFinished && finalRound != nil && finalRound == latest?.index && latestIsDone
            ? finalRound : nil

        return TournamentPlan(
            length: length,
            roundsPlayed: roundsPlayed,
            partnershipsLeft: partnershipsLeft,
            finalRound: finalRound,
            isReached: isReached,
            finishPromptRound: prompt
        )
    }
}
