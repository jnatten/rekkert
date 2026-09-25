import Foundation

/// Who goes to the bench when several players have sat out equally often.
public enum BenchOrder: String, Codable, Sendable, Hashable {
    /// The seeded shuffle decides, so a rotation that has come round can land straight back
    /// on whoever sat out last. How every draw was made before the other existed.
    case fewestSitOuts
    /// Whoever sat out longest ago, so the gap between anyone's sit-outs is as long as the
    /// numbers allow.
    case longestRested
}

enum RoundScheduler {
    /// Everyone who can't be given a seat this round. Benches whoever has sat out least
    /// so far, so sit-outs spread evenly; ties break on a seeded order rather than on
    /// dictionary iteration, which would differ between devices. `chosen` go to the bench
    /// ahead of all of that, and must not outnumber it.
    static func split(
        players: [Player],
        seats: Int,
        history: PairingHistory,
        order benchOrder: BenchOrder = .fewestSitOuts,
        chosen: [PlayerID] = [],
        generator: inout SeededGenerator
    ) -> (playing: [PlayerID], sitting: [PlayerID]) {
        let shuffled = players.map(\.id).shuffled(using: &generator)
        let seatCount = seats
        guard shuffled.count > seatCount else { return (shuffled, []) }

        let order = Dictionary(uniqueKeysWithValues: shuffled.enumerated().map { ($1, $0) })
        let chosenSet = Set(chosen)
        let benchFirst = shuffled.sorted { one, two in
            let isChosen = chosenSet.contains(one)
            if isChosen != chosenSet.contains(two) { return isChosen }
            let a = history.sitOutCount(one)
            let b = history.sitOutCount(two)
            if a != b { return a < b }
            if benchOrder == .longestRested {
                let rested = history.lastSitOut(one) ?? -1
                let other = history.lastSitOut(two) ?? -1
                if rested != other { return rested < other }
            }
            return order[one, default: 0] < order[two, default: 0]
        }

        let sitting = Array(benchFirst.prefix(shuffled.count - seatCount))
        let sittingSet = Set(sitting)
        let playing = shuffled.filter { !sittingSet.contains($0) }
        return (playing, sitting)
    }

    static func chosen(_ sitOuts: [PlayerID]?, in tournament: Tournament) throws -> [PlayerID] {
        guard let sitOuts else { return [] }
        let known = Set(tournament.players.map(\.id))
        guard Set(sitOuts).count == sitOuts.count, sitOuts.allSatisfy(known.contains),
              sitOuts.count <= tournament.benchSize else { throw TournamentError.invalidSitOuts }
        return sitOuts
    }

    static func pair(_ four: [PlayerID], as pairing: MexicanoPairing) -> BySide<[PlayerID]> {
        switch pairing {
        case .topWithBottom: BySide(a: [four[0], four[3]], b: [four[1], four[2]])
        case .topWithThird: BySide(a: [four[0], four[2]], b: [four[1], four[3]])
        }
    }
}

/// Picks the partnerships for a set of players already known to be on court, preferring the
/// pairs and the match-ups that have come up least.
///
/// Doubles only: the search swaps players between four fixed slots per court, so every team
/// handed to it must have exactly two players. A singles draw has nothing left to decide
/// once the bench is chosen, and goes nowhere near this.
enum PairingSearch {
    private static let repeatPartnerCost = 100
    private static let repeatOpponentCost = 1

    static func teams(
        from playing: [PlayerID], courts: Int, history: PairingHistory
    ) -> [BySide<[PlayerID]>] {
        var teams = greedyTeams(from: playing, courts: courts, history: history)
        improve(&teams, history: history)
        return teams
    }

    private static func greedyTeams(
        from playing: [PlayerID], courts: Int, history: PairingHistory
    ) -> [BySide<[PlayerID]>] {
        var pool = playing
        var teams: [BySide<[PlayerID]>] = []

        for _ in 0 ..< courts {
            let first = pool.removeFirst()
            let partnerIndex = bestIndex(in: pool) { history.partnerCount(first, $0) }
            let partner = pool.remove(at: partnerIndex)

            let third = pool.removeFirst()
            let fourthIndex = bestIndex(in: pool) { candidate in
                history.partnerCount(third, candidate) * repeatPartnerCost
                    + crossCost([first, partner], [third, candidate], history: history)
            }
            let fourth = pool.remove(at: fourthIndex)

            teams.append(BySide(a: [first, partner], b: [third, fourth]))
        }
        return teams
    }

    /// Deterministic argmin: the earliest index wins ties, so two devices agree.
    private static func bestIndex(in pool: [PlayerID], cost: (PlayerID) -> Int) -> Int {
        var best = 0
        var bestCost = Int.max
        for (index, candidate) in pool.enumerated() {
            let value = cost(candidate)
            if value < bestCost {
                bestCost = value
                best = index
            }
        }
        return best
    }

    private static func crossCost(_ one: [PlayerID], _ two: [PlayerID], history: PairingHistory) -> Int {
        var total = 0
        for left in one {
            for right in two {
                total += history.opponentCount(left, right) * repeatOpponentCost
            }
        }
        return total
    }

    static func cost(_ teams: [BySide<[PlayerID]>], history: PairingHistory) -> Int {
        teams.reduce(0) { running, match in
            var total = running
            for side in TeamSide.allCases where match[side].count == 2 {
                total += history.partnerCount(match[side][0], match[side][1]) * repeatPartnerCost
            }
            total += crossCost(match.a, match.b, history: history)
            return total
        }
    }

    /// Bounded, deterministic local search: swap two players between slots whenever it
    /// lowers the repeat cost. Greedy alone can leave obvious repeats on the table.
    private static func improve(_ teams: inout [BySide<[PlayerID]>], history: PairingHistory) {
        let slots = teams.indices.flatMap { court in
            TeamSide.allCases.flatMap { side in (0 ..< 2).map { (court, side, $0) } }
        }
        for _ in 0 ..< 4 {
            var improved = false
            for left in slots.indices {
                for right in (left + 1) ..< slots.count {
                    let one = slots[left]
                    let two = slots[right]
                    guard one.0 != two.0 || one.1 != two.1 else { continue }

                    var candidate = teams
                    let held = candidate[one.0][one.1][one.2]
                    candidate[one.0][one.1][one.2] = candidate[two.0][two.1][two.2]
                    candidate[two.0][two.1][two.2] = held

                    if cost(candidate, history: history) < cost(teams, history: history) {
                        teams = candidate
                        improved = true
                    }
                }
            }
            if !improved { break }
        }
    }
}

public enum AmericanoScheduler {
    public static func nextRound(for tournament: Tournament, sitOuts: [PlayerID]? = nil) throws -> Round {
        let courts = tournament.playableCourts
        guard courts >= 1 else {
            throw TournamentError.notEnoughPlayers(needed: 4, have: tournament.players.count)
        }
        let chosen = try RoundScheduler.chosen(sitOuts, in: tournament)

        let index = tournament.rounds.count
        let history = PairingHistory(tournament)
        var generator = SeededGenerator(tournament.id.raw, salt: UInt64(index))
        let (playing, sitting) = RoundScheduler.split(
            players: tournament.players, seats: courts * 4, history: history,
            order: tournament.benchOrder, chosen: chosen, generator: &generator
        )

        let teams = PairingSearch.teams(from: playing, courts: courts, history: history)

        let matches = teams.enumerated().map { CourtMatch(courtIndex: $0.offset, teams: $0.element) }
        return Round(index: index, matches: matches, sitOuts: sitting)
    }
}

public enum MexicanoScheduler {
    public static func nextRound(for tournament: Tournament, sitOuts: [PlayerID]? = nil) throws -> Round {
        let courts = tournament.playableCourts
        guard courts >= 1 else {
            throw TournamentError.notEnoughPlayers(needed: 4, have: tournament.players.count)
        }
        let chosen = try RoundScheduler.chosen(sitOuts, in: tournament)

        let index = tournament.rounds.count
        let history = PairingHistory(tournament)
        var generator = SeededGenerator(tournament.id.raw, salt: UInt64(index))
        let (playing, sitting) = RoundScheduler.split(
            players: tournament.players, seats: courts * 4, history: history,
            order: tournament.benchOrder, chosen: chosen, generator: &generator
        )

        let ranked: [PlayerID]
        if tournament.rounds.allSatisfy(\.isCancelled) {
            ranked = playing
        } else {
            let playingSet = Set(playing)
            let order = Leaderboard.standings(for: tournament, onlyConfirmed: true)
                .map(\.player.id)
                .filter { playingSet.contains($0) }
            let missing = playing.filter { !order.contains($0) }
            ranked = order + missing
        }

        let matches = (0 ..< courts).map { court in
            let four = Array(ranked[(court * 4) ..< (court * 4 + 4)])
            return CourtMatch(
                courtIndex: court,
                teams: RoundScheduler.pair(four, as: tournament.config.mexicanoPairing)
            )
        }
        return Round(index: index, matches: matches, sitOuts: sitting)
    }
}

public enum TournamentEngine {
    /// `sitOuts` are players picked to sit this round out; whatever of the bench they leave
    /// open is filled as it always is.
    public static func appendingRound(to tournament: Tournament, sitOuts: [PlayerID]? = nil) throws -> Tournament {
        var next = tournament
        let round = switch tournament.format {
        case .americano: try AmericanoScheduler.nextRound(for: tournament, sitOuts: sitOuts)
        case .mexicano: try MexicanoScheduler.nextRound(for: tournament, sitOuts: sitOuts)
        }
        next.rounds.append(round)
        return next
    }

    /// The last round drawn again from what came before it, around who is sitting it out.
    /// Same index, same seed: picking the bench it already has gives back the same round.
    public static func redrawingLastRound(of tournament: Tournament, sitOuts: [PlayerID]) throws -> Tournament {
        var base = tournament
        _ = base.rounds.popLast()
        return try appendingRound(to: base, sitOuts: sitOuts)
    }
}
