import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000004")!)
private let later = DeviceID(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000004")!)

private func uuid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", number))!
}

private func log(
    _ format: TournamentFormat = .americano, players: Int = 10, courts: Int = 2, seed: Int = 0xFF
) -> MatchLog {
    let tournament = Tournament(
        id: TournamentID(uuid(seed)),
        name: "Thursday",
        format: format,
        players: (0 ..< players).map { Player(id: PlayerID(uuid(0x1000 + $0)), name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
    )
    var log = MatchLog(sessionID: UUID(uuidString: "44444444-0000-0000-0000-000000000000")!)
    log.append(.configure(.tournament(tournament)), from: device)
    return log
}

private func tournament(_ log: MatchLog) -> Tournament? {
    guard case .tournament(let value) = SessionReducer.state(of: log) else { return nil }
    return value
}

/// Every court settled 9–7 and confirmed, so a Mexicano table has something to rank by.
private func settle(_ log: inout MatchLog) {
    guard let current = tournament(log), let round = current.currentRound else { return }
    for match in round.matches {
        log.append(.setScore(round: round.index, court: match.courtIndex, points: BySide(a: 9, b: 7)), from: device)
    }
    log.append(.setRoundConfirmed(round: round.index, isConfirmed: true), from: device)
}

private func drawing(_ start: MatchLog, rounds: Int, settling: Bool = false) -> MatchLog {
    var log = start
    for _ in 0 ..< rounds {
        log.drawRound(from: device)
        if settling { settle(&log) }
    }
    return log
}

private func benches(_ tournament: Tournament) -> [Set<PlayerID>] {
    tournament.rounds.map { Set($0.sitOuts) }
}

/// How many times a pair sat out together after already having done so.
private func repeatedPairs(_ tournament: Tournament) -> Int {
    var seen: Set<PairKey> = []
    var repeats = 0
    for round in tournament.rounds {
        let bench = round.sitOuts
        for (index, one) in bench.enumerated() {
            for two in bench[(index + 1)...] where !seen.insert(PairKey(one, two)).inserted {
                repeats += 1
            }
        }
    }
    return repeats
}

private func gaps(_ tournament: Tournament) -> [Int] {
    tournament.players.flatMap { player in
        let rounds = tournament.rounds.indices.filter { tournament.rounds[$0].sitOuts.contains(player.id) }
        return zip(rounds.dropFirst(), rounds).map { $0 - $1 }
    }
}

private func evenAfterEveryRound(_ tournament: Tournament) -> Bool {
    (1 ... tournament.rounds.count).allSatisfy { count in
        let tallies = tournament.players.map { player in
            tournament.rounds.prefix(count).count { $0.sitOuts.contains(player.id) }
        }
        return tallies.max()! - tallies.min()! <= 1
    }
}

/// `nextRound` as builds from before draws carried their round have it, which fold a draw from
/// `sitOuts` alone.
private enum OlderEventKind: Codable, Equatable {
    case nextRound(after: Int, at: Date? = nil, sitOuts: [PlayerID]? = nil)
}

@Suite("Mixing who sits out together")
struct MixedBenchTests {
    /// Mexicano mixes who sits out together. Americano gives that up where it has to, to keep
    /// anybody from partnering twice in a turn (`PartnerTurnTests`).
    @Test func tenPlayersNeverSitOutWithTheSamePlayerTwice() throws {
        let played = try #require(tournament(drawing(log(.mexicano), rounds: 15, settling: true)))
        #expect(benches(played).allSatisfy { $0.count == 2 })
        #expect(repeatedPairs(played) == 0, "\(benches(played).map { $0.compactMap { played.player($0)?.name }.sorted() })")
        #expect(gaps(played).allSatisfy { $0 >= 4 }, "\(gaps(played))")
        #expect(evenAfterEveryRound(played))
    }

    /// The bench this replaced came round as a queue, sending the same five pairs back every
    /// five rounds.
    @Test func theSamePairsNoLongerComeRoundEveryRotation() throws {
        let played = try #require(tournament(drawing(log(), rounds: 15)))
        var older = log()
        for _ in 0 ..< 15 { older.drawRoundAsOlderBuild(from: device) }
        let queue = try #require(tournament(older))

        #expect(benches(queue)[5 ..< 15].elementsEqual(benches(queue)[0 ..< 10]), "the queue it replaced")
        #expect(benches(played)[0 ..< 5].elementsEqual(benches(queue)[0 ..< 5]), "the first rotation is drawn as it was")
        #expect(!benches(played)[5 ..< 10].elementsEqual(benches(played)[0 ..< 5]))
    }

    @Test(arguments: [(5, 1, 15), (6, 1, 12), (9, 2, 18), (10, 2, 15), (11, 2, 12), (12, 2, 12), (13, 2, 12), (14, 3, 21)])
    func sitOutsStayEvenAndSpreadOut(players: Int, courts: Int, rounds: Int) throws {
        let bench = players - courts * 4
        let rotation = (players + bench - 1) / bench
        for seed in 1 ... 8 {
            let mexicano = try #require(tournament(drawing(log(.mexicano, players: players, courts: courts, seed: seed), rounds: rounds, settling: true)))
            #expect(evenAfterEveryRound(mexicano), "seed \(seed)")
            #expect(gaps(mexicano).allSatisfy { $0 >= max(2, rotation - 1) }, "seed \(seed): \(gaps(mexicano))")

            let americano = try #require(tournament(drawing(log(players: players, courts: courts, seed: seed), rounds: rounds)))
            #expect(evenAfterEveryRound(americano), "seed \(seed)")
            #expect(gaps(americano).allSatisfy { $0 >= 2 }, "seed \(seed): nobody two rounds running, \(gaps(americano))")
        }
    }

    @Test(arguments: [(10, 2, 15), (14, 3, 21)])
    func pairsDoNotRepeatWhileFreshOnesAreLeft(players: Int, courts: Int, rounds: Int) throws {
        for seed in 1 ... 8 {
            let played = try #require(tournament(drawing(log(.mexicano, players: players, courts: courts, seed: seed), rounds: rounds, settling: true)))
            #expect(repeatedPairs(played) == 0, "seed \(seed)")
        }
    }

    /// One sits out a round: the order changes from one rotation to the next instead of coming
    /// round as a queue, and nobody sits out again within four rounds.
    @Test func aBenchOfOneVariesItsOrder() throws {
        var varied = 0
        for seed in 1 ... 8 {
            let played = try #require(tournament(drawing(log(players: 5, courts: 1, seed: seed), rounds: 15)))
            let order = played.rounds.map(\.sitOuts)
            if !order[5 ..< 10].elementsEqual(order[0 ..< 5]) || !order[10 ..< 15].elementsEqual(order[5 ..< 10]) { varied += 1 }
            #expect(gaps(played).allSatisfy { $0 >= 4 }, "seed \(seed): \(gaps(played))")
            #expect(evenAfterEveryRound(played))
        }
        #expect(varied == 8, "\(varied) of 8 varied")
    }

    @Test(arguments: [TournamentFormat.americano, .mexicano])
    func theFirstRotationCarriesNoBench(format: TournamentFormat) throws {
        let drawn = drawing(log(format), rounds: 5, settling: format == .mexicano)
        let carried = drawn.ordered.compactMap { event -> [PlayerID]?? in
            guard case .nextRound(_, _, let sitOuts, _) = event.kind else { return nil }
            return sitOuts
        }
        #expect(carried.count == 5)
        #expect(carried.allSatisfy { $0 == nil }, "nothing an older build would draw differently")
    }

    /// A build from before draws carried their round folds each draw from `sitOuts` alone, and
    /// lands on the same rounds.
    @Test(arguments: [TournamentFormat.americano, .mexicano])
    func anOlderBuildFollowsTheBenchTheDrawCarries(format: TournamentFormat) throws {
        let drawn = drawing(log(format), rounds: 15, settling: format == .mexicano)
        var older = MatchLog(sessionID: drawn.sessionID)
        for event in drawn.ordered {
            if case .nextRound(let after, let at, let sitOuts, _) = event.kind {
                let data = try JSONCoding.encoder.encode(OlderEventKind.nextRound(after: after, at: at, sitOuts: sitOuts))
                let kind = try JSONCoding.decoder.decode(EventKind.self, from: data)
                older.append(kind, from: device)
            } else {
                older.append(event.kind, from: device)
            }
        }
        let newer = try #require(tournament(drawn))
        #expect(tournament(older) == newer)
        #expect(repeatedPairs(newer) == 0)
    }

    @Test func aRoundAnOlderBuildDrawsIsFollowedAndTheMixingCarriesOn() throws {
        var mixed = drawing(log(), rounds: 7)
        let before = try #require(tournament(mixed))
        mixed.drawRoundAsOlderBuild(from: later)
        let queued = try #require(tournament(mixed))
        #expect(try queued.rounds[7] == TournamentEngine.appendingRound(to: before).rounds[7], "drawn the old way, as the older build drew it")

        let played = try #require(tournament(drawing(mixed, rounds: 7)))
        #expect(played.rounds.count == 15)
        #expect(evenAfterEveryRound(played))
        #expect(gaps(played).allSatisfy { $0 >= 2 }, "\(gaps(played))")
    }

    /// A tournament under way when the app is updated keeps every round it has played.
    @Test func roundsPlayedBeforeTheUpdateStayAsTheyWere() throws {
        var older = log()
        for _ in 0 ..< 8 { older.drawRoundAsOlderBuild(from: device) }
        let played = try #require(tournament(older))

        let updated = try #require(tournament(drawing(older, rounds: 7)))
        #expect(Array(updated.rounds.prefix(8)) == played.rounds)
        #expect(evenAfterEveryRound(updated))
    }

    @Test func aRedrawKeepsThePickAndMixesTheRest() throws {
        var drawn = drawing(log(), rounds: 6)
        let current = try #require(tournament(drawn))
        let late = try #require(current.players.map(\.id).first { !current.rounds[5].sitOuts.contains($0) })
        let expected = try #require(TournamentEngine.bench(for: current, picked: [late], redrawing: true))

        let event = drawn.redrawRound(sittingOut: [late], from: device)
        let redrawn = try #require(tournament(drawn))
        #expect(redrawn.rounds.count == 6)
        #expect(redrawn.rounds[5].sitOuts.contains(late))
        #expect(Set(redrawn.rounds[5].sitOuts) == Set(expected))
        guard case .nextRound(_, _, let carried?, _) = event.kind else {
            Issue.record("a redraw carries its bench")
            return
        }
        let older = try TournamentEngine.redrawingLastRound(of: current, sitOuts: carried)
        #expect(older.rounds[5] == redrawn.rounds[5], "an older build given the same event draws the same round")
    }

    @Test func aMexicanoIsStillDrawnFromTheTableAroundTheMixedBench() throws {
        var drawn = log(.mexicano)
        for _ in 0 ..< 15 {
            let before = try #require(tournament(drawn))
            drawn.drawRound(from: device)
            let round = try #require(tournament(drawn)?.currentRound)
            let fromTable = try TournamentEngine.appendingRound(to: before, sitOuts: round.sitOuts).currentRound
            #expect(round == fromTable)
            settle(&drawn)
        }
        let played = try #require(tournament(drawn))
        #expect(repeatedPairs(played) == 0)
        #expect(evenAfterEveryRound(played))
    }

    @Test(arguments: [LadderPartners.fixed, .split])
    func aLadderDrawsItsBenchAsItAlwaysHas(partners: LadderPartners) throws {
        var ladder = makeLadder(players: 10, courts: 2, partners: partners, start: .random)
        for _ in 0 ..< 8 {
            let next = try TournamentEngine.appendingRound(to: ladder)
            #expect(TournamentEngine.sitOuts(for: ladder) == nil, "nothing carried beyond the placement")
            #expect(TournamentEngine.bench(for: ladder) == next.currentRound?.sitOuts)
            ladder = settle(next, [.a, .b])
        }
    }

    /// Two devices draw the same round at once. Both carry the same bench, so the second is drawn
    /// again around it and lands on the round the first drew.
    @Test func twoDevicesDrawingAtOnceMakeOneRound() throws {
        let shared = drawing(log(), rounds: 7)
        let state = try #require(tournament(shared))
        let sitOuts = try #require(TournamentEngine.sitOuts(for: state), "a round where the bench is carried")

        var both = shared
        both.append(.nextRound(after: 6, sitOuts: sitOuts), from: device)
        both.append(.nextRound(after: 6, sitOuts: sitOuts), from: later)
        var one = shared
        one.append(.nextRound(after: 6, sitOuts: sitOuts), from: device)

        #expect(tournament(both)?.rounds.count == 8)
        #expect(tournament(both) == tournament(one))
    }
}
