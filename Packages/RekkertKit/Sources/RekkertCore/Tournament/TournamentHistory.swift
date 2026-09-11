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

struct TournamentHistory: Sendable {
    private(set) var partnered: [PairKey: Int] = [:]
    private(set) var opposed: [PairKey: Int] = [:]
    private(set) var sitOuts: [PlayerID: Int] = [:]

    init(_ tournament: Tournament) {
        for round in tournament.rounds {
            for match in round.matches {
                for side in TeamSide.allCases {
                    let team = match.teams[side]
                    if team.count == 2 {
                        partnered[PairKey(team[0], team[1]), default: 0] += 1
                    }
                }
                for one in match.teams.a {
                    for two in match.teams.b {
                        opposed[PairKey(one, two), default: 0] += 1
                    }
                }
            }
            for id in round.sitOuts {
                sitOuts[id, default: 0] += 1
            }
        }
    }

    func partnerCount(_ one: PlayerID, _ two: PlayerID) -> Int { partnered[PairKey(one, two)] ?? 0 }
    func opponentCount(_ one: PlayerID, _ two: PlayerID) -> Int { opposed[PairKey(one, two)] ?? 0 }
    func sitOutCount(_ id: PlayerID) -> Int { sitOuts[id] ?? 0 }
}
