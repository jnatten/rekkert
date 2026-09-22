/// What an umpire would say after a point.
///
/// Built from the change between two scoreboards rather than from one of them, because the
/// most interesting calls leave nothing behind to read: a won game puts the score back to
/// love–all, and a won set clears the games too.
public struct ScoreCall: Sendable, Hashable {
    /// Said in order, with a pause between them.
    public var phrases: [String]

    public init(phrases: [String]) {
        self.phrases = phrases
    }

    public var spoken: String {
        phrases.joined(separator: ". ") + "."
    }
}

public enum ScoreCaller {
    /// `nil` when nothing happened worth saying: the serve was corrected, a round was
    /// locked, or the game simply started and the score is still love–all.
    public static func call(from previous: ScoreboardSnapshot, to current: ScoreboardSnapshot) -> ScoreCall? {
        guard scoreChanged(from: previous, to: current) else { return nil }
        let phrases = points(current) + conclusion(from: previous, to: current)
        return phrases.isEmpty ? nil : ScoreCall(phrases: phrases)
    }

    private static func scoreChanged(from previous: ScoreboardSnapshot, to current: ScoreboardSnapshot) -> Bool {
        previous.points != current.points
            || previous.games != current.games
            || previous.completedSets != current.completedSets
            || previous.isFinished != current.isFinished
    }

    // MARK: - The score as it stands

    /// Server first, which is the convention and also the only order both ends of the court
    /// agree on.
    private static func points(_ snapshot: ScoreboardSnapshot) -> [String] {
        let server = snapshot.serving ?? .a
        let serving = snapshot.points[server]
        let receiving = snapshot.points[server.other]
        // Nobody calls love–all; the game score said everything a moment ago.
        guard !(serving.isZero && receiving.isZero) else { return [] }

        let phrase: String
        if serving == .advantage || receiving == .advantage {
            let leader = serving == .advantage ? server : server.other
            phrase = "Advantage \(snapshot.teamNames[leader])"
        } else if serving == .forty, receiving == .forty {
            phrase = "Deuce"
        } else if serving == receiving {
            phrase = sentence("\(serving.spoken) all")
        } else {
            phrase = sentence("\(serving.spoken), \(receiving.spoken)")
        }
        return snapshot.isSuddenDeath ? [phrase, "Sudden death"] : [phrase]
    }

    // MARK: - What the point finished

    private static func conclusion(from previous: ScoreboardSnapshot, to current: ScoreboardSnapshot) -> [String] {
        ending(from: previous, to: current) + changingEnds(from: previous, to: current)
    }

    private static func ending(from previous: ScoreboardSnapshot, to current: ScoreboardSnapshot) -> [String] {
        if current.completedSets.count > previous.completedSets.count, let set = current.completedSets.last {
            return closingSet(set, current)
        }
        if let winner = gameWinner(from: previous, to: current) {
            return ["Game, \(current.teamNames[winner])", games(current)]
        }
        if current.isFinished, !previous.isFinished {
            return reachingTheTarget(current)
        }
        return []
    }

    /// Its own phrase, so it earns the pause after whatever tally came before it.
    ///
    /// Only ever one more walk than before, for the same reason `gameWinner` insists on
    /// exactly one more game: undo takes the count back down, and nobody walks anywhere on
    /// a score being corrected. Nobody walks over to shake hands either.
    private static func changingEnds(from previous: ScoreboardSnapshot, to current: ScoreboardSnapshot) -> [String] {
        guard current.changeovers == previous.changeovers + 1, !current.isFinished else { return [] }
        return ["Swap sides"]
    }

    /// Counted modes end by arriving at a number rather than by winning a game, so they
    /// need saying out loud — the score alone does not sound like an ending.
    private static func reachingTheTarget(_ snapshot: ScoreboardSnapshot) -> [String] {
        switch snapshot.kind {
        case .tournament:
            return ["\(snapshot.courtLabel ?? "Court") finished"]
        case .pointCount:
            guard let winner = snapshot.winner else { return ["Finished, all square"] }
            return ["Game to \(snapshot.teamNames[winner])"]
        case .traditional, .winnerCourt, .friendly:
            return []
        }
    }

    /// Only ever one more game than before, and only for one side — so an undo, which takes
    /// a game back off, says nothing about a game being won.
    private static func gameWinner(from previous: ScoreboardSnapshot, to current: ScoreboardSnapshot) -> TeamSide? {
        guard let before = previous.games, let now = current.games else { return nil }
        return TeamSide.allCases.first { side in
            now[side] == before[side] + 1 && now[side.other] == before[side.other]
        }
    }

    private static func closingSet(_ set: SetResult, _ snapshot: ScoreboardSnapshot) -> [String] {
        guard let winner = set.winner else {
            // Winner court only: the whistle can close a round with the two sides level.
            return ["Round drawn, \(set.games.a) all"]
        }
        let name = snapshot.teamNames[winner]
        let score = "\(set.games[winner]) to \(set.games[winner.other])"

        if snapshot.kind == .winnerCourt {
            return ["Round to \(name), \(score)"]
        }
        if snapshot.isFinished {
            return ["Game, set and match, \(name)"]
        }
        return ["Game and set, \(name), \(score)", sets(snapshot)]
    }

    // MARK: - Tallies

    private static func games(_ snapshot: ScoreboardSnapshot) -> String {
        let games = snapshot.games ?? BySide(both: 0)
        guard let leader = games.leader else {
            return "\(games.a) \(unit(games.a, "game")) all"
        }
        return "\(games[leader]) \(unit(games[leader], "game")) to \(games[leader.other]), \(snapshot.teamNames[leader])"
    }

    private static func sets(_ snapshot: ScoreboardSnapshot) -> String {
        var won = BySide(both: 0)
        for set in snapshot.completedSets {
            if let winner = set.winner { won[winner] += 1 }
        }
        guard let leader = won.leader else {
            return "\(won.a) \(unit(won.a, "set")) all"
        }
        return "\(won[leader]) \(unit(won[leader], "set")) to \(won[leader.other]), \(snapshot.teamNames[leader])"
    }

    private static func unit(_ count: Int, _ singular: String) -> String {
        count == 1 ? singular : singular + "s"
    }

    private static func sentence(_ phrase: String) -> String {
        phrase.prefix(1).uppercased() + phrase.dropFirst()
    }
}
