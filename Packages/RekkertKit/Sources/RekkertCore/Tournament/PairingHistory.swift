struct PairKey: Hashable, Sendable {
    let low: PlayerID
    let high: PlayerID

    init(_ one: PlayerID, _ two: PlayerID) {
        if one < two {
            low = one
            high = two
        } else {
            low = two
            high = one
        }
    }
}

/// Who has partnered, opposed and sat out whom, in the shape the draw asks about it. Built
/// from whatever has been played rather than from one particular mode, so a tournament and a
/// friendly session are scheduled by the same bookkeeping.
struct PairingHistory: Sendable {
    private(set) var partnered: [PairKey: Int] = [:]
    private(set) var opposed: [PairKey: Int] = [:]
    private(set) var sitOuts: [PlayerID: Int] = [:]
    /// How many rounds had been recorded when each player last sat out.
    private(set) var lastSatOut: [PlayerID: Int] = [:]
    private(set) var benchedTogether: [PairKey: Int] = [:]
    private(set) var lastPartners: Set<PairKey> = []
    private(set) var recorded = 0

    init() {}

    init(_ tournament: Tournament) {
        var returned = Set<Int>()
        for round in tournament.rounds where !round.isCancelled {
            welcomeBack(in: tournament, upTo: round.index, done: &returned)
            record(round.matches.map(\.teams), sitOuts: round.sitOuts)
        }
        welcomeBack(in: tournament, upTo: tournament.rounds.count, done: &returned)
    }

    /// A returner is put level with the least rested of those who play the round they are back
    /// for, as if they had just sat one out, so the bench owes them neither a rest nor a game
    /// (spec 008, D-6). Only the bench's bookkeeping: the table counts real sit-outs.
    private mutating func welcomeBack(in tournament: Tournament, upTo index: Int, done: inout Set<Int>) {
        for (position, absence) in tournament.absences.enumerated() {
            guard let until = absence.until, until <= index, done.insert(position).inserted else { continue }
            let here = tournament.present(inRound: until)
            let seats = min(tournament.config.courtCount, here.count / 4) * 4
            let bench = max(0, here.count - seats)
            let others = here.map(\.id).filter { $0 != absence.player }.map(sitOutCount).sorted()
            if bench < others.count {
                sitOuts[absence.player] = max(sitOutCount(absence.player), others[bench])
            }
            lastSatOut[absence.player] = recorded - 1
        }
    }

    mutating func record(_ matches: [BySide<[PlayerID]>], sitOuts benched: [PlayerID]) {
        lastPartners = []
        for teams in matches {
            for side in TeamSide.allCases {
                let team = teams[side]
                if team.count == 2 {
                    partnered[PairKey(team[0], team[1]), default: 0] += 1
                    lastPartners.insert(PairKey(team[0], team[1]))
                }
            }
            for one in teams.a {
                for two in teams.b {
                    opposed[PairKey(one, two), default: 0] += 1
                }
            }
        }
        for (index, one) in benched.enumerated() {
            sitOuts[one, default: 0] += 1
            lastSatOut[one] = recorded
            for two in benched[(index + 1)...] {
                benchedTogether[PairKey(one, two), default: 0] += 1
            }
        }
        recorded += 1
    }

    func partnerCount(_ one: PlayerID, _ two: PlayerID) -> Int { partnered[PairKey(one, two)] ?? 0 }
    func opponentCount(_ one: PlayerID, _ two: PlayerID) -> Int { opposed[PairKey(one, two)] ?? 0 }
    func sitOutCount(_ id: PlayerID) -> Int { sitOuts[id] ?? 0 }
    func lastSitOut(_ id: PlayerID) -> Int? { lastSatOut[id] }
    func satOutTogether(_ one: PlayerID, _ two: PlayerID) -> Int { benchedTogether[PairKey(one, two)] ?? 0 }
    func partneredLastRound(_ one: PlayerID, _ two: PlayerID) -> Bool { lastPartners.contains(PairKey(one, two)) }
}
