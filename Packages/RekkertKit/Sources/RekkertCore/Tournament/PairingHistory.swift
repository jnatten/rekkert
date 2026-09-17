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

    init() {}

    init(_ tournament: Tournament) {
        for round in tournament.rounds {
            record(round.matches.map(\.teams), sitOuts: round.sitOuts)
        }
    }

    mutating func record(_ matches: [BySide<[PlayerID]>], sitOuts benched: [PlayerID]) {
        for teams in matches {
            for side in TeamSide.allCases {
                let team = teams[side]
                if team.count == 2 {
                    partnered[PairKey(team[0], team[1]), default: 0] += 1
                }
            }
            for one in teams.a {
                for two in teams.b {
                    opposed[PairKey(one, two), default: 0] += 1
                }
            }
        }
        for id in benched {
            sitOuts[id, default: 0] += 1
        }
    }

    func partnerCount(_ one: PlayerID, _ two: PlayerID) -> Int { partnered[PairKey(one, two)] ?? 0 }
    func opponentCount(_ one: PlayerID, _ two: PlayerID) -> Int { opposed[PairKey(one, two)] ?? 0 }
    func sitOutCount(_ id: PlayerID) -> Int { sitOuts[id] ?? 0 }
}
