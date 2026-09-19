import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID()

private func traditional() -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.traditional(
        rules: TraditionalRules(),
        teams: BySide(a: .home, b: .away)
    )), from: device)
    return log
}

private func serving(_ log: MatchLog) -> TeamSide? {
    SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }?.serving
}

/// What `MatchStore.swapServingTeam` does, so the tests exercise the same arithmetic.
private func swapServe(_ log: inout MatchLog, round: Int = 0, court: Int = 0) {
    guard let order = SessionReducer.state(of: log)?.serveOrder(round: round, court: court) else { return }
    log.append(.setServeOrder(round: round, court: court, order: order.swappingTeams()), from: device)
}

/// And `MatchStore.swapServingPlayer`: the other partner on the side serving now.
private func swapPlayer(_ log: inout MatchLog, round: Int = 0, court: Int = 0) {
    guard let state = SessionReducer.state(of: log),
          let order = state.serveOrder(round: round, court: court),
          let serving = state.serve(round: round, court: court)?.slot.team else { return }
    log.append(
        .setServeOrder(round: round, court: court, order: order.swappingPlayers(of: serving)),
        from: device
    )
}

private func board(_ log: MatchLog) -> ScoreboardSnapshot? {
    SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }
}

private func namedMatch(
    a: [String] = ["Jonas", "Ada"],
    b: [String] = ["Kim", "Sam"],
    rules: TraditionalRules = TraditionalRules()
) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.traditional(
        rules: rules,
        teams: BySide(a: TeamInfo(name: "Us", players: a), b: TeamInfo(name: "Them", players: b))
    )), from: device)
    return log
}

/// The slot each of the next `count` games is served from, A winning them one at a time.
private func slots(_ log: MatchLog, games count: Int) -> [ServeSlot] {
    var log = log
    return (0 ..< count).map { _ in
        let slot = SessionReducer.state(of: log)!.serve()!.slot
        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        return slot
    }
}

@Suite("Swapping service")
struct ServeSwapTests {
    @Test func swappingHandsServiceToTheOtherTeam() {
        var log = traditional()
        #expect(serving(log) == .a)

        swapServe(&log)
        #expect(serving(log) == .b)

        swapServe(&log)
        #expect(serving(log) == .a, "and back again")
    }

    @Test func theCorrectionCarriesThroughLaterGames() {
        var log = traditional()
        swapServe(&log)
        #expect(serving(log) == .b)

        // Win a game; service passes to the other team, from the corrected rotation.
        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        #expect(serving(log) == .a)

        for _ in 0 ..< 4 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        #expect(serving(log) == .b)
    }

    @Test func bothDevicesCorrectingAtOnceSwapOnce() {
        let watch = DeviceID()
        let base = traditional()
        #expect(serving(base) == .a)

        var onPhone = base
        var onWatch = base
        swapServe(&onPhone)
        // The watch works it out from the same state and reaches the same answer.
        let current = SessionReducer.state(of: onWatch)!.serveOrder()!
        let fromWatch = onWatch.append(
            .setServeOrder(round: 0, court: 0, order: current.swappingTeams()),
            from: watch
        )
        onPhone.merge([fromWatch])
        onWatch.merge(onPhone.ordered)

        #expect(serving(onPhone) == .b, "one correction, not two")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func swappingDoesNotDisturbTheScore() {
        var log = traditional()
        for _ in 0 ..< 3 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        swapServe(&log)

        let snapshot = SessionReducer.state(of: log).flatMap { ScoreboardSnapshot.make(from: $0) }
        #expect(snapshot?.primary.a == "40")
        #expect(snapshot?.serving == .b)
    }

    @Test func undoTargetsTheScoreRatherThanTheCorrection() {
        var log = traditional()
        let point = log.append(.point(round: 0, court: 0, team: .a), from: device)
        swapServe(&log)

        #expect(log.lastUndoableEvent()?.id == point.id,
                "a serve correction is not something undo should reach for")
    }

    @Test func eachTournamentCourtIsCorrectedOnItsOwn() {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            name: "T", format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 2)
        ))), from: device)
        log.drawRound(from: device)

        swapServe(&log, court: 1)

        let state = SessionReducer.state(of: log)
        #expect(ScoreboardSnapshot.make(from: state!, court: 0)?.serving == .a, "court 1 is untouched")
        #expect(ScoreboardSnapshot.make(from: state!, court: 1)?.serving == .b)
    }
}

@Suite("Swapping service on a tournament court")
struct CourtServeSwapTests {
    private func tournament(courts: Int = 2, players: Int = 8) -> MatchLog {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!),
            name: "Test", format: .americano,
            players: (0 ..< players).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
        ))), from: device)
        log.drawRound(from: device)
        return log
    }

    private func serving(_ log: MatchLog, court: Int) -> TeamSide? {
        SessionReducer.state(of: log)
            .flatMap { ScoreboardSnapshot.make(from: $0, court: court) }?
            .serving
    }

    @Test func everyCourtCanBeCorrectedOnItsOwn() {
        var log = tournament()
        #expect(serving(log, court: 0) == .a)
        #expect(serving(log, court: 1) == .a)

        swapServe(&log, court: 1)

        #expect(serving(log, court: 1) == .b, "the court that was corrected")
        #expect(serving(log, court: 0) == .a, "and only that one")
    }

    @Test func aCorrectionOnALaterRoundLeavesTheEarlierOneAlone() {
        var log = tournament()
        for court in 0 ..< 2 {
            log.append(.setScore(round: 0, court: court, points: BySide(a: 9, b: 7)), from: device)
        }
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.drawRound(from: device)

        swapServe(&log, round: 1, court: 0)

        guard case .tournament(let value)? = SessionReducer.state(of: log) else {
            Issue.record("expected a tournament")
            return
        }
        #expect(value.rounds[1].matches[0].state.serveOrder
            == ServeOrder(firstServerIndex: 1, serversSwapped: BySide(a: true, b: false)))
        #expect(value.rounds[0].matches[0].state.serveOrder == ServeOrder(), "round one is untouched")
    }

    @Test func swappingTwiceOnOneCourtPutsItBack() {
        var log = tournament()
        swapServe(&log, court: 1)
        swapServe(&log, court: 1)
        #expect(serving(log, court: 1) == .a)
        #expect(
            SessionReducer.state(of: log)?.serve(court: 1)?.slot == ServeSlot(team: .a, playerIndex: 0),
            "the same player too, however the order is written down"
        )
    }
}

@Suite("Swapping the serving player")
struct ServingPlayerSwapTests {
    private let engine = TraditionalEngine(rules: TraditionalRules())

    /// The slot each of four games is served from, A winning them one at a time.
    private func sequence(from state: TraditionalState) -> [ServeSlot] {
        var state = state
        return (0 ..< 4).map { _ in
            let slot = engine.serve(state).slot
            state = engine.winGames(1, for: .a, from: state)
            return slot
        }
    }

    @Test func swappingTheServingPlayerHandsTheServeToThePartner() {
        var log = namedMatch()
        #expect(board(log)?.servingPlayer == "Jonas")

        swapPlayer(&log)
        #expect(board(log)?.servingPlayer == "Ada")
        #expect(board(log)?.serving == .a, "same side, other partner")
    }

    @Test func swappingThePlayerCarriesThroughThatTeamsLaterTurns() {
        var log = namedMatch()
        swapPlayer(&log)
        #expect(slots(log, games: 4) == [
            ServeSlot(team: .a, playerIndex: 1),
            ServeSlot(team: .b, playerIndex: 0),
            ServeSlot(team: .a, playerIndex: 0),
            ServeSlot(team: .b, playerIndex: 1),
        ], "the other side's order is left alone")
    }

    @Test func swappingThePlayerTwicePutsItBack() {
        var log = namedMatch()
        let before = slots(log, games: 4)
        swapPlayer(&log)
        swapPlayer(&log)
        #expect(slots(log, games: 4) == before)
    }

    @Test(arguments: 0 ..< 4)
    func swappingTeamsKeepsEachTeamsOwnFirstServer(start: Int) {
        let before = TraditionalState(firstServerIndex: start)
        var after = before
        after.serveOrder = before.serveOrder.swappingTeams()

        let was = sequence(from: before)
        let now = sequence(from: after)
        #expect(now.map(\.team) == was.map(\.team.other), "the sides change places")
        for side in TeamSide.allCases {
            #expect(
                now.filter { $0.team == side }.map(\.playerIndex) == was.filter { $0.team == side }.map(\.playerIndex),
                "\(side) keeps its own order"
            )
        }
    }

    @Test(arguments: 0 ..< 4)
    func swappingTeamsTwiceIsWhereYouStarted(start: Int) {
        let before = TraditionalState(firstServerIndex: start)
        var after = before
        after.serveOrder = before.serveOrder.swappingTeams().swappingTeams()
        #expect(sequence(from: after) == sequence(from: before))
    }

    @Test func bothDevicesSwappingThePlayerAtOnceSwapOnce() {
        let watch = DeviceID()
        let base = namedMatch()
        var onPhone = base
        var onWatch = base
        swapPlayer(&onPhone)
        let order = SessionReducer.state(of: onWatch)!.serveOrder()!
        let fromWatch = onWatch.append(
            .setServeOrder(round: 0, court: 0, order: order.swappingPlayers(of: .a)),
            from: watch
        )
        onPhone.merge([fromWatch])
        onWatch.merge(onPhone.ordered)

        #expect(board(onPhone)?.servingPlayer == "Ada", "one correction, not two")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func aTeamSwapAndAPlayerSwapAtOnceStillAgree() {
        let watch = DeviceID()
        let base = namedMatch()
        var onPhone = base
        var onWatch = base
        swapServe(&onPhone)
        let order = SessionReducer.state(of: onWatch)!.serveOrder()!
        let fromWatch = onWatch.append(
            .setServeOrder(round: 0, court: 0, order: order.swappingPlayers(of: .a)),
            from: watch
        )
        onPhone.merge([fromWatch])
        onWatch.merge(onPhone.ordered)

        #expect(
            SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch),
            "whichever correction wins, both devices show the same one"
        )
    }

    @Test func theOldServeCorrectionStillReplays() {
        var log = namedMatch()
        log.append(.setFirstServer(round: 0, court: 0, index: 1), from: device)
        #expect(board(log)?.serving == .b)
        #expect(SessionReducer.state(of: log)?.serveOrder()?.serversSwapped == BySide(both: false))
    }

    @Test func aPlayerSwapIsNeitherProgressNorUndoable() {
        var log = namedMatch()
        swapPlayer(&log)
        #expect(!log.hasProgress, "nothing has been played")

        let point = log.append(.point(round: 0, court: 0, team: .a), from: device)
        swapPlayer(&log)
        #expect(log.lastUndoableEvent()?.id == point.id, "undo still reaches for the point")
    }

    @Test func eachTournamentCourtSwapsItsOwnPlayer() {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            name: "T", format: .americano,
            players: (0 ..< 8).map { Player(name: "P\($0)") },
            config: TournamentConfig(courtCount: 2)
        ))), from: device)
        log.drawRound(from: device)

        swapPlayer(&log, court: 1)

        let state = SessionReducer.state(of: log)
        #expect(state?.serve(court: 1)?.slot == ServeSlot(team: .a, playerIndex: 1))
        #expect(state?.serve(court: 0)?.slot == ServeSlot(team: .a, playerIndex: 0), "court 1 is untouched")
    }

    @Test func aPlayerSwapInAFriendlyLandsOnItsRound() {
        var log = MatchLog()
        log.append(.configure(.friendly(FriendlySession(
            players: (0 ..< 4).map { Player(name: "P\($0)") }
        ))), from: device)
        log.drawFriendlyRound(from: device)

        swapPlayer(&log, round: 0)

        #expect(SessionReducer.state(of: log)?.serve(round: 0)?.slot == ServeSlot(team: .a, playerIndex: 1))
    }
}

@Suite("Who can swap the serving player")
struct ServingPlayerSwapAvailabilityTests {
    @Test func twoNamedPlayersCanSwap() {
        #expect(board(namedMatch())?.canSwapServingPlayer == true)
    }

    @Test func aLoneOrBlankNameCannot() {
        #expect(board(namedMatch(a: ["Jonas"]))?.canSwapServingPlayer == false)
        #expect(board(namedMatch(a: ["Jonas", ""]))?.canSwapServingPlayer == false)

        let secondOnly = board(namedMatch(a: ["", "Ada"]))
        #expect(secondOnly?.canSwapServingPlayer == false)
        #expect(secondOnly?.servingPlayer == nil, "a blank slot is nobody, not an empty name")
    }

    @Test func aQuickMatchHasNobodyToSwap() {
        #expect(board(namedMatch(a: [], b: []))?.canSwapServingPlayer == false)
    }

    @Test func aFinishedMatchHasNobodyToSwap() {
        var log = namedMatch(rules: TraditionalRules(setsToWin: 1))
        for _ in 0 ..< 24 { log.append(.point(round: 0, court: 0, team: .a), from: device) }
        #expect(board(log)?.isFinished == true)
        #expect(board(log)?.canSwapServingPlayer == false)
    }

    @Test func singlesInAFriendlyCannotSwapButDoublesCan() {
        for (count, expected) in [(2, false), (4, true)] {
            var log = MatchLog()
            log.append(.configure(.friendly(FriendlySession(
                players: (0 ..< count).map { Player(name: "P\($0)") }
            ))), from: device)
            log.drawFriendlyRound(from: device)
            #expect(board(log)?.canSwapServingPlayer == expected, "\(count) players")
        }
    }

    @Test func aConfirmedTournamentRoundCannotSwap() {
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            name: "T", format: .americano,
            players: (0 ..< 4).map { Player(name: "P\($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
        ))), from: device)
        log.drawRound(from: device)
        #expect(board(log)?.canSwapServingPlayer == true)

        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        #expect(board(log)?.canSwapServingPlayer == false)
    }
}

@Suite("Serve order coding")
struct ServeOrderCodingTests {
    /// A value filed before the flag existed: the same encoding with the key taken out.
    private func withoutTheFlag<Value: Encodable>(_ value: Value) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(value)) as! [String: Any]
        object.removeValue(forKey: "serversSwapped")
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func aScoreFiledBeforePlayerSwapsStillReads() throws {
        let engine = TraditionalEngine(rules: TraditionalRules())
        let state = engine.winGames(2, for: .b, from: TraditionalState(firstServerIndex: 1))
        let decoded = try JSONCoding.decoder.decode(TraditionalState.self, from: withoutTheFlag(state))
        #expect(decoded.firstServerIndex == 1)
        #expect(decoded.games == BySide(a: 0, b: 2))
        #expect(decoded.serversSwapped == BySide(both: false), "nobody had swapped")
        #expect(decoded == state)
    }

    @Test func aCountedRoundFiledBeforePlayerSwapsStillReads() throws {
        let state = PointCountState(points: BySide(a: 3, b: 1), firstServerIndex: 2)
        let decoded = try JSONCoding.decoder.decode(PointCountState.self, from: withoutTheFlag(state))
        #expect(decoded == state)
    }

    @Test func aSwappedOrderSurvivesTheRoundTrip() throws {
        var state = TraditionalState()
        state.serveOrder = ServeOrder().swappingPlayers(of: .b)
        let data = try JSONCoding.encoder.encode(state)
        #expect(try JSONCoding.decoder.decode(TraditionalState.self, from: data) == state)
    }
}
