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

private struct BenchDue: Comparable {
    let notChosen: Int
    let sitOuts: Int
    let rested: Int

    static func < (lhs: BenchDue, rhs: BenchDue) -> Bool {
        (lhs.notChosen, lhs.sitOuts, lhs.rested) < (rhs.notChosen, rhs.sitOuts, rhs.rested)
    }
}

/// How far a bench falls short of spreading sit-outs out: the rounds each of them is short of
/// `gap` since they last sat out, and how often its pairs have sat out together before.
private struct BenchSpread {
    let history: PairingHistory
    let gap: Int

    /// `previous` is a bench drawn the round before this one, for looking a round ahead.
    func cost(of bench: [PlayerID], after previous: Set<PlayerID> = []) -> (short: Int, together: Int) {
        let now = history.recorded + (previous.isEmpty ? 0 : 1)
        var short = 0
        var together = 0
        for (index, one) in bench.enumerated() {
            let since = previous.contains(one) ? 1 : history.lastSitOut(one).map { now - $0 }
            if let since { short += max(0, gap - since) }
            for two in bench[(index + 1)...] {
                together += history.satOutTogether(one, two) + (previous.contains(one) && previous.contains(two) ? 1 : 0)
            }
        }
        return (short, together)
    }
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
        rules: [PairingRule] = [],
        generator: inout SeededGenerator
    ) -> (playing: [PlayerID], sitting: [PlayerID]) {
        let shuffled = players.map(\.id).shuffled(seededBy: &generator)
        let seatCount = seats
        guard shuffled.count > seatCount else { return (shuffled, []) }

        let order = Dictionary(uniqueKeysWithValues: shuffled.enumerated().map { ($1, $0) })
        let chosenSet = Set(chosen)
        let due = { (id: PlayerID) in
            BenchDue(
                notChosen: chosenSet.contains(id) ? 0 : 1, sitOuts: history.sitOutCount(id),
                rested: benchOrder == .longestRested ? history.lastSitOut(id) ?? -1 : 0
            )
        }
        let benchFirst = shuffled.sorted { one, two in
            let a = due(one)
            let b = due(two)
            if a != b { return a < b }
            return order[one, default: 0] < order[two, default: 0]
        }

        let benchSize = shuffled.count - seatCount
        var sitting = Array(benchFirst.prefix(benchSize))
        if !rules.isEmpty, seatCount == 4 {
            let dueNext = { (benched: Set<PlayerID>) in
                { (id: PlayerID) in
                    BenchDue(
                        notChosen: 1, sitOuts: history.sitOutCount(id) + (benched.contains(id) ? 1 : 0),
                        rested: benchOrder == .longestRested ? (benched.contains(id) ? history.recorded : history.lastSitOut(id) ?? -1) : 0
                    )
                }
            }
            sitting = benchKeeping(rules, benchFirst: benchFirst, size: benchSize, due: due, dueNext: dueNext)
        }
        let sittingSet = Set(sitting)
        let playing = shuffled.filter { !sittingSet.contains($0) }
        return (playing, sitting)
    }

    /// The bench as even as ever, its tie-breaks leaning towards the rules (spec 006, FR-006):
    /// whoever must sit out does, and of those equally due the first combination, in the seeded
    /// order, whose court keeps the rules and leaves the next round able to keep them too.
    /// Failing that, the one that breaks fewest. With every combination keeping them, the first
    /// is the bench drawn without rules.
    private static func benchKeeping(
        _ rules: [PairingRule], benchFirst: [PlayerID], size: Int,
        due: (PlayerID) -> BenchDue, dueNext: (Set<PlayerID>) -> (PlayerID) -> BenchDue
    ) -> [PlayerID] {
        var budget = 20_000
        var best: (score: (Int, Int), bench: [PlayerID])?
        forEachBench(of: benchFirst, size: size, due: due) { bench in
            let benched = Set(bench)
            let now = rules.fewestBreaks(among: benchFirst.filter { !benched.contains($0) })
            if let best, now > best.score.0 { return true }
            let ahead = budget > 0
                ? fewestBreaks(rules, players: benchFirst, size: size, due: dueNext(benched), budget: &budget)
                : 0
            if best == nil || (now, ahead) < best!.score { best = ((now, ahead), bench) }
            return (now, ahead) != (0, 0)
        }
        let chosen = Set(best?.bench ?? [])
        return benchFirst.filter(chosen.contains)
    }

    private static func fewestBreaks(
        _ rules: [PairingRule], players: [PlayerID], size: Int, due: (PlayerID) -> BenchDue, budget: inout Int
    ) -> Int {
        let ordered = players.enumerated().sorted { (due($0.element), $0.offset) < (due($1.element), $1.offset) }.map(\.element)
        var fewest = Int.max
        var spent = budget
        forEachBench(of: ordered, size: size, due: due) { bench in
            spent -= 1
            let benched = Set(bench)
            fewest = min(fewest, rules.fewestBreaks(among: ordered.filter { !benched.contains($0) }))
            return fewest > 0 && spent > 0
        }
        budget = spent
        return fewest == .max ? 0 : fewest
    }

    /// The bench as even as ever, mixing who sits out together: of those equally due, the first
    /// combination in the seeded order that leaves nobody sitting out again sooner than a
    /// rotation less one and puts fewest back on the bench with someone they sat out with,
    /// counting the best bench the round after it would leave. With no history to go on that is
    /// the bench `split` draws. The search stops after a fixed amount of work, the same on every
    /// device, and the bench `.longestRested` would draw stands in for it whenever it did better
    /// than all the search got to.
    static func mixedBench(
        players: [Player], seats: Int, history: PairingHistory, chosen: [PlayerID] = [],
        generator: inout SeededGenerator
    ) -> [PlayerID] {
        let shuffled = players.map(\.id).shuffled(seededBy: &generator)
        let size = shuffled.count - seats
        guard size > 0 else { return [] }

        let chosenSet = Set(chosen)
        let due = { (id: PlayerID) in
            BenchDue(notChosen: chosenSet.contains(id) ? 0 : 1, sitOuts: history.sitOutCount(id), rested: 0)
        }
        let benchFirst = ordered(shuffled, by: due) { _ in 0 }
        let rotation = (shuffled.count + size - 1) / size
        let spread = BenchSpread(history: history, gap: max(2, rotation - 1))
        let work = size * (size + 1) / 2
        var budget = 200_000

        func score(_ bench: [PlayerID]) -> (Int, Int, Int) {
            let now = spread.cost(of: bench)
            let benched = Set(bench)
            let dueNext = { (id: PlayerID) in
                BenchDue(notChosen: 1, sitOuts: history.sitOutCount(id) + (benched.contains(id) ? 1 : 0), rested: 0)
            }
            var ahead = (short: Int.max, together: Int.max)
            let nextFirst = ordered(benchFirst, by: dueNext) { benched.contains($0) ? history.recorded : history.lastSitOut($0) ?? -1 }
            forEachBench(of: nextFirst, size: size, due: dueNext) { next in
                budget -= work
                let cost = spread.cost(of: next, after: benched)
                if (cost.short, cost.together) < (ahead.short, ahead.together) { ahead = cost }
                return (ahead.short, ahead.together) != (0, 0) && budget > 0
            }
            return (now.short + ahead.short, now.together + ahead.together, now.short)
        }

        let rested = Array(ordered(shuffled, by: due) { history.lastSitOut($0) ?? -1 }.prefix(size))
        let restedScore = score(rested)
        var best: (score: (Int, Int, Int), bench: [PlayerID])?
        forEachBench(of: benchFirst, size: size, due: due) { bench in
            budget -= work
            let now = spread.cost(of: bench)
            if let best, (now.short, now.together) >= (best.score.0, best.score.1) { return budget > 0 }
            let candidate = score(bench)
            if best == nil || candidate < best!.score { best = (candidate, bench) }
            return candidate != (0, 0, 0) && budget > 0
        }
        let picked = Set(best.map { $0.score <= restedScore ? $0.bench : rested } ?? rested)
        return benchFirst.filter(picked.contains)
    }

    /// Americano's benches from this round to the end of the turn, planned for the partners they
    /// leave (bug americano-partner-repeats). Older builds work out a round's teams themselves
    /// from its bench and never take them from the draw, so the bench is the one thing that can
    /// steer them: each round's teams are drawn here exactly as every build will draw them, from
    /// that round's seeded order less the bench, and a bench whose teams would pair anybody again
    /// is passed over. The turn is as many rounds as the pairs not yet partnered as often as the
    /// rest can fill, so past the first turn nobody partners a third time before everyone has
    /// twice, and never with last round's partner. Benches are tried as sit-outs prefer them:
    /// fewest sit-outs, then the spread `mixedBench` keeps, from the first few hundred a round
    /// allows; nobody sits out two rounds running unless no turn can be found without. Each
    /// pass stops after a fixed amount of work, the same on every device; short of a whole turn
    /// it keeps the plan that got furthest, and with not even one round it takes the bench whose
    /// teams repeat least, never last round's partners where it can help it.
    static func plannedTurn(
        players: [Player], courts: Int, seed: UUID, round first: Int, history: PairingHistory,
        chosen: [PlayerID] = []
    ) -> [[PlayerID]] {
        let ids = players.map(\.id)
        let size = ids.count - courts * 4
        guard size > 0, courts >= 1 else { return [] }

        var least = Int.max
        for (index, one) in ids.enumerated() {
            for two in ids[(index + 1)...] { least = min(least, history.partnerCount(one, two)) }
        }
        let cap = least + 1
        var open = 0
        for (index, one) in ids.enumerated() {
            for two in ids[(index + 1)...] where history.partnerCount(one, two) < cap { open += 1 }
        }
        let horizon = open / (courts * 2)
        let orders = (0 ..< max(horizon, 1)).map { offset in
            var generator = SeededGenerator(seed, salt: UInt64(first + offset))
            return ids.shuffled(seededBy: &generator)
        }
        let gap = max(2, (ids.count + size - 1) / size - 1)

        let weighing = size * (size + 1) / 2
        let drawing = courts * courts * 100
        var budget = 200_000
        func benches(_ depth: Int, _ history: PairingHistory, _ chosen: Set<PlayerID>, twiceRunning: Bool) -> [[PlayerID]] {
            let due = { (id: PlayerID) in
                BenchDue(notChosen: chosen.contains(id) ? 0 : 1, sitOuts: history.sitOutCount(id), rested: 0)
            }
            let spread = BenchSpread(history: history, gap: gap)
            var found: [(key: (Int, Int, Int, Int), bench: [PlayerID])] = []
            forEachBench(of: ordered(orders[depth], by: due) { _ in 0 }, size: size, due: due) { bench in
                budget -= weighing
                let again = bench.count { !chosen.contains($0) && history.lastSitOut($0) == history.recorded - 1 }
                if twiceRunning || again == 0 {
                    let cost = spread.cost(of: bench)
                    found.append(((again, cost.short, cost.together, found.count), bench))
                }
                return found.count < 300 && budget > 0
            }
            return found.sorted { $0.key < $1.key }.map(\.bench)
        }
        func draw(_ depth: Int, _ bench: [PlayerID], _ history: PairingHistory) -> [BySide<[PlayerID]>] {
            budget -= drawing
            let benched = Set(bench)
            return PairingSearch.teams(from: orders[depth].filter { !benched.contains($0) }, courts: courts, history: history)
        }
        func partners(_ teams: [BySide<[PlayerID]>]) -> [(PlayerID, PlayerID)] {
            teams.flatMap { match in TeamSide.allCases.map { (match[$0][0], match[$0][1]) } }
        }

        var path: [[PlayerID]] = []
        var furthest: [[PlayerID]] = []
        func search(_ depth: Int, _ history: PairingHistory, _ chosen: Set<PlayerID>, twiceRunning: Bool) -> Bool {
            if depth == horizon { return true }
            for bench in benches(depth, history, chosen, twiceRunning: twiceRunning) {
                guard budget > 0 else { return false }
                let teams = draw(depth, bench, history)
                let fresh = partners(teams).allSatisfy { pair in
                    history.partnerCount(pair.0, pair.1) < cap && !history.partneredLastRound(pair.0, pair.1)
                }
                guard fresh else { continue }
                var next = history
                next.record(teams, sitOuts: bench)
                path.append(bench)
                if path.count > furthest.count { furthest = path }
                if search(depth + 1, next, [], twiceRunning: twiceRunning) { return true }
                path.removeLast()
            }
            return false
        }
        if horizon > 0 {
            if search(0, history, Set(chosen), twiceRunning: false) { return path }
            let kept = furthest
            budget = 100_000
            path = []
            furthest = []
            if search(0, history, Set(chosen), twiceRunning: true) { return path }
            if kept.count >= furthest.count, !kept.isEmpty { return kept }
            if !furthest.isEmpty { return furthest }
        }

        budget = 50_000
        var best: (key: (Int, Int, Int, Int, Int), bench: [PlayerID])?
        for (index, bench) in benches(0, history, Set(chosen), twiceRunning: true).enumerated() where best == nil || budget > 0 {
            let again = bench.count { !chosen.contains($0) && history.lastSitOut($0) == history.recorded - 1 }
            var key = (0, 0, again, 0, index)
            for pair in partners(draw(0, bench, history)) {
                let count = history.partnerCount(pair.0, pair.1)
                if history.partneredLastRound(pair.0, pair.1) { key.0 += 1 }
                if count >= cap { key.1 += 1 }
                key.3 += count
            }
            if best == nil || key < best!.key { best = (key, bench) }
        }
        return best.map { [$0.bench] } ?? []
    }

    private static func ordered(_ ids: [PlayerID], by due: (PlayerID) -> BenchDue, rested: (PlayerID) -> Int) -> [PlayerID] {
        ids.enumerated()
            .sorted { (due($0.element), rested($0.element), $0.offset) < (due($1.element), rested($1.element), $1.offset) }
            .map(\.element)
    }

    /// Every bench the rotation allows, in the seeded order: those with fewer sit-outs than the
    /// last place on it, and every way of filling the rest from those equally due. `visit`
    /// returns whether to go on.
    private static func forEachBench(
        of benchFirst: [PlayerID], size: Int, due: (PlayerID) -> BenchDue, _ visit: ([PlayerID]) -> Bool
    ) {
        let boundaryDue = due(benchFirst[size - 1])
        let mustSit = Array(benchFirst.prefix { due($0) < boundaryDue })
        let boundary = benchFirst.filter { due($0) == boundaryDue }
        var picks = Array(0 ..< (size - mustSit.count))
        while visit(mustSit + picks.map { boundary[$0] }) {
            guard let next = nextCombination(picks, of: boundary.count) else { return }
            picks = next
        }
    }

    private static func nextCombination(_ picks: [Int], of count: Int) -> [Int]? {
        var picks = picks
        var index = picks.count - 1
        while index >= 0, picks[index] == count - picks.count + index { index -= 1 }
        guard index >= 0 else { return nil }
        picks[index] += 1
        for later in (index + 1) ..< picks.count { picks[later] = picks[later - 1] + 1 }
        return picks
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
        from playing: [PlayerID], courts: Int, history: PairingHistory, rules: [PairingRule] = []
    ) -> [BySide<[PlayerID]>] {
        var teams = greedyTeams(from: playing, courts: courts, history: history)
        improve(&teams, history: history, rules: rules)
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
    private static func improve(_ teams: inout [BySide<[PlayerID]>], history: PairingHistory, rules: [PairingRule]) {
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

                    // Rules first, compared rather than weighted: a long evening's repeats can
                    // outgrow any weight.
                    let proposed = (rules.breakCount(candidate), cost(candidate, history: history))
                    let current = (rules.breakCount(teams), cost(teams, history: history))
                    if proposed < current {
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
    /// open is filled as it always is. `placed` is the round as the device that drew it
    /// worked it out, taken as it is when it fits.
    public static func appendingRound(
        to tournament: Tournament,
        sitOuts: [PlayerID]? = nil,
        placed: RoundPlacement? = nil
    ) throws -> Tournament {
        var next = tournament
        let round = switch tournament.format {
        case .americano: try AmericanoScheduler.nextRound(for: tournament, sitOuts: sitOuts)
        case .mexicano:
            try placed?.round(for: tournament) ?? MexicanoScheduler.nextRound(for: tournament, sitOuts: sitOuts)
        case .winnerCourt:
            try placed?.round(for: tournament) ?? LadderScheduler.nextRound(for: tournament, sitOuts: sitOuts)
        }
        next.rounds.append(round)
        return next
    }

    /// The last round drawn again from what came before it, around who is sitting it out.
    /// Same index, same seed: picking the bench it already has gives back the same round.
    public static func redrawingLastRound(
        of tournament: Tournament,
        sitOuts: [PlayerID],
        placed: RoundPlacement? = nil
    ) throws -> Tournament {
        var base = tournament
        _ = base.rounds.popLast()
        return try appendingRound(to: base, sitOuts: sitOuts, placed: placed)
    }

    /// Where the next round puts everybody, for the draw to carry. A ladder is drawn from how
    /// the round before finished and Mexicano from the table; worked out again on each device,
    /// either would be read off scores that a point or a correction racing the draw may since
    /// have changed, moving people already on their courts. `redrawing` draws the round in
    /// play again around `sitOuts`. Nil for Americano, which never reads a score.
    public static func placement(
        of tournament: Tournament,
        sitOuts: [PlayerID]? = nil,
        redrawing: Bool = false
    ) -> RoundPlacement? {
        switch tournament.format {
        case .americano: return nil
        case .mexicano, .winnerCourt: break
        }
        let drawn = if redrawing {
            try? redrawingLastRound(of: tournament, sitOuts: sitOuts ?? [])
        } else {
            try? appendingRound(to: tournament, sitOuts: sitOuts)
        }
        return drawn?.rounds.last.map(RoundPlacement.init)
    }

    /// Who sits out the next round, or with `redrawing` the round in play drawn again: `picked`
    /// first, the rest as evenly as ever. Americano plans them so nobody partners anybody twice
    /// in a turn, and Mexicano mixes who sits out together. A ladder's bench is drawn as it
    /// always is. Nil when the round cannot be drawn.
    public static func bench(for tournament: Tournament, picked: [PlayerID] = [], redrawing: Bool = false) -> [PlayerID]? {
        var base = tournament
        if redrawing { _ = base.rounds.popLast() }
        switch base.format {
        case .winnerCourt:
            return (try? appendingRound(to: base, sitOuts: picked.isEmpty ? nil : picked))?.currentRound?.sitOuts
        case .americano:
            guard base.playableCourts >= 1, let chosen = try? RoundScheduler.chosen(picked, in: base) else { return nil }
            return RoundScheduler.plannedTurn(
                players: base.players, courts: base.playableCourts, seed: base.id.raw, round: base.rounds.count,
                history: PairingHistory(base), chosen: chosen
            ).first ?? []
        case .mexicano:
            guard base.playableCourts >= 1, let chosen = try? RoundScheduler.chosen(picked, in: base) else { return nil }
            var generator = SeededGenerator(base.id.raw, salt: UInt64(base.rounds.count))
            return RoundScheduler.mixedBench(
                players: base.players, seats: base.playableCourts * 4, history: PairingHistory(base),
                chosen: chosen, generator: &generator
            )
        }
    }

    /// What the event drawing that round carries as `sitOuts`: the bench `bench(for:)` picks
    /// wherever it is not the one the draw makes without it. Every build since sit-outs could be
    /// picked benches exactly those and draws the courts around them, so an older device lands on
    /// the same round without knowing how the bench was chosen; the draw itself never mixes, or
    /// it would disagree with them over an event that carries nothing.
    public static func sitOuts(for tournament: Tournament, picked: [PlayerID]? = nil, redrawing: Bool = false) -> [PlayerID]? {
        guard tournament.format != .winnerCourt,
              let bench = bench(for: tournament, picked: picked ?? [], redrawing: redrawing) else { return picked }
        let drawn = redrawing
            ? try? redrawingLastRound(of: tournament, sitOuts: picked ?? [])
            : try? appendingRound(to: tournament, sitOuts: picked)
        if let round = drawn?.currentRound, Set(round.sitOuts) == Set(bench) { return picked }
        return bench
    }
}
