import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID()

private func setup(
    players: Int = 4,
    rules: TraditionalRules = TraditionalRules(setsToWin: 1, gamesPerSet: 6),
    id: String = "00000000-0000-0000-0000-0000000000A1"
) -> FriendlySession {
    FriendlySession(
        id: FriendlyID(UUID(uuidString: id)!),
        name: "Thursday",
        rules: rules,
        players: (0 ..< players).map { Player(name: "P\($0)") }
    )
}

/// Configured and with the first round drawn, which is what starting one does.
private func log(
    players: Int = 4,
    rules: TraditionalRules = TraditionalRules(setsToWin: 1, gamesPerSet: 6)
) -> MatchLog {
    var log = MatchLog()
    log.append(.configure(.friendly(setup(players: players, rules: rules))), from: device)
    log.drawFriendlyRound(from: device)
    return log
}

private func session(_ log: MatchLog) -> FriendlySession? {
    guard case .friendly(let value)? = SessionReducer.state(of: log) else { return nil }
    return value
}

private func score(_ log: inout MatchLog, round: Int, _ sequence: [TeamSide]) {
    for team in sequence { log.append(.point(round: round, court: 0, team: team), from: device) }
}

/// Wins `count` whole games for `side`, four straight points each.
private func winGames(_ log: inout MatchLog, _ count: Int, for side: TeamSide, round: Int = 0) {
    score(&log, round: round, Array(repeating: side, count: count * 4))
}

/// Every round's partnerships as names. Two sessions built from the same names hold
/// different `PlayerID`s, so names are the only way to compare one draw with another.
private func partnerships(_ session: FriendlySession) -> [[[String]]] {
    session.rounds.map { round in
        TeamSide.allCases.map { side in round.teams[side].map(session.name) }
    }
}

@Suite("Friendly mode")
struct FriendlyModeTests {
    @Test func startingDrawsTheFirstRound() throws {
        let value = try #require(session(log()))
        #expect(value.rounds.count == 1)
        #expect(value.currentIndex == 0)
        #expect(!value.isFinished)
    }

    @Test func pointsLandOnTheAddressedRound() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        score(&value, round: 1, [.b, .b])

        let friendly = try #require(session(value))
        #expect(friendly.rounds[0].games == BySide(a: 6, b: 0))
        #expect(friendly.rounds[1].score.points == BySide(a: 0, b: 2))
    }

    @Test func aRoundEndsWhenSomebodyWinsTheMatch() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)

        let friendly = try #require(session(value))
        #expect(friendly.rounds[0].score.winner == .a)
        #expect(friendly.rounds[0].isFinished)
        #expect(!friendly.isFinished, "the session goes on; only the round is over")
    }

    @Test func aFinishedRoundIgnoresFurtherPoints() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        score(&value, round: 0, [.b, .b, .b])

        let friendly = try #require(session(value))
        #expect(friendly.rounds[0].score.points == BySide(both: 0))
        #expect(friendly.rounds[0].score.winner == .a)
    }

    @Test func drawingTheNextRoundKeepsTheFinishedOneAndChangesThePartners() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        let before = try #require(session(value)).rounds[0]
        value.drawFriendlyRound(from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds.count == 2)
        #expect(friendly.rounds[0] == before, "the round played is left exactly as it was")
        #expect(friendly.rounds[1].teams != before.teams, "new partnerships")
        #expect(friendly.rounds[1].score.points == BySide(both: 0))
    }

    @Test func theRulesApplyToEveryRound() throws {
        var value = log(rules: TraditionalRules(setsToWin: 1, gamesPerSet: 6, deuceRule: .goldenPoint))
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        // Three each is the first 40–40, which golden point makes sudden death.
        score(&value, round: 1, [.a, .b, .a, .b, .a, .b])

        let friendly = try #require(session(value))
        #expect(friendly.engine.isSuddenDeathPoint(friendly.rounds[1].score))

        score(&value, round: 1, [.b])
        #expect(try #require(session(value)).rounds[1].games == BySide(a: 0, b: 1))
    }

    @Test func undoingTheDrawReopensThePreviousRound() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        #expect(try #require(session(value)).rounds.count == 2)

        let target = try #require(value.lastUndoableEvent())
        value.append(.undo(target.id), from: device)
        #expect(try #require(session(value)).rounds.count == 1, "back to the round just won")
    }

    @Test func undoingTheWinningPointReopensTheRound() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)

        // Twice: the draw first, then the point that won it.
        for _ in 0 ..< 2 {
            let target = try #require(value.lastUndoableEvent())
            value.append(.undo(target.id), from: device)
        }

        let friendly = try #require(session(value))
        #expect(friendly.rounds.count == 1)
        #expect(friendly.rounds[0].score.winner == nil)
        #expect(friendly.rounds[0].games == BySide(a: 5, b: 0))
        #expect(friendly.rounds[0].score.points == BySide(a: 3, b: 0))
    }

    @Test func bothDevicesAdvancingAtOnceDrawsOneRound() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        let watch = DeviceID()

        var onPhone = value
        var onWatch = value
        let fromPhone = onPhone.drawFriendlyRound(from: device)
        let fromWatch = onWatch.drawFriendlyRound(from: watch)

        onPhone.merge([fromWatch])
        onWatch.merge([fromPhone])

        #expect(try #require(session(onPhone)).rounds.count == 2, "two taps, one new round")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func aLatePointNeverLeaksIntoTheRoundAfterIt() throws {
        var value = log()
        winGames(&value, 5, for: .a, round: 0)
        let watch = DeviceID()

        // The watch scores in round 1 without having heard that round 1 is over.
        var onWatch = value
        let late = onWatch.append(.point(round: 0, court: 0, team: .b), from: watch)

        // Meanwhile the phone finishes round 1 and draws round 2.
        var onPhone = value
        winGames(&onPhone, 1, for: .a, round: 0)
        onPhone.drawFriendlyRound(from: device)

        onPhone.merge([late])
        onWatch.merge(onPhone.ordered)

        let friendly = try #require(session(onPhone))
        #expect(friendly.rounds.count == 2)
        #expect(friendly.rounds[0].score.winner == .a)
        #expect(friendly.rounds[1].score.points == BySide(both: 0),
                "the point was addressed to round 1 and stayed there")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch),
                "both devices fold the same log into the same state")
    }

    @Test func aScoreCorrectionNeverRePairsALaterRound() throws {
        var straight = log()
        for round in 0 ..< 3 {
            winGames(&straight, 6, for: .a, round: round)
            straight.drawFriendlyRound(from: device)
        }
        let expected = partnerships(try #require(session(straight)))

        // The same run, with one point in the first round taken back and replayed.
        var corrected = log()
        score(&corrected, round: 0, [.b])
        let stray = try #require(corrected.lastUndoableEvent())
        corrected.append(.undo(stray.id), from: device)
        for round in 0 ..< 3 {
            winGames(&corrected, 6, for: .a, round: round)
            corrected.drawFriendlyRound(from: device)
        }

        #expect(partnerships(try #require(session(corrected))) == expected,
                "the draw reads teams and the bench, never the score")
    }

    @Test func reconfiguringKeepsTheRoundsPlayed() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        let before = try #require(session(value)).rounds

        var again = setup()
        again.name = "Friday"
        again.players.append(Player(name: "P4"))
        value.append(.configure(.friendly(again)), from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds == before, "a latecomer does not rewrite what has been played")
        #expect(friendly.name == "Friday")
        #expect(friendly.players.count == 5)
    }

    @Test func theWhistleStopsTheRoundWhereItStands() throws {
        var value = log()
        winGames(&value, 3, for: .a, round: 0)
        winGames(&value, 2, for: .b, round: 0)
        value.append(.endRound(round: 0), from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds[0].isStopped)
        #expect(friendly.rounds[0].isFinished)
        #expect(friendly.rounds[0].score.winner == nil, "stopped is not won")
        #expect(friendly.rounds[0].games == BySide(a: 3, b: 2), "the games played still count")

        value.drawFriendlyRound(from: device)
        #expect(try #require(session(value)).rounds.count == 2)
    }

    @Test func aRoundNothingHasHappenedInCannotBeStopped() throws {
        var value = log()
        value.append(.endRound(round: 0), from: device)

        let friendly = try #require(session(value))
        #expect(!friendly.rounds[0].isStopped, "there is nothing to stop yet")
        #expect(!friendly.rounds[0].isFinished)
    }

    @Test func whistlingTwiceIsANoOp() throws {
        var value = log()
        winGames(&value, 3, for: .a, round: 0)
        value.append(.endRound(round: 0), from: device)
        value.append(.endRound(round: 0), from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds.count == 1)
        #expect(friendly.rounds[0].games == BySide(a: 3, b: 0))
    }

    @Test func finishLocksTheSession() throws {
        var value = log()
        winGames(&value, 2, for: .a, round: 0)
        value.append(.finish(archive: true), from: device)

        let state = try #require(SessionReducer.state(of: value))
        #expect(state.isFinished)
        #expect(state.hasResults)
        #expect(state.canResume, "a friendly always has another round in it")
    }

    @Test func aSessionWithNoPointsHasNoResults() throws {
        let state = try #require(SessionReducer.state(of: log()))
        #expect(!state.hasResults, "a round merely drawn is not a round played")
        #expect(state.title == "Thursday")
        #expect(state.modeName == "Friendly")
        #expect(state.courtCount == 1)
    }

    @Test func theFirstServerIsAddressedPerRound() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        value.append(.setFirstServer(round: 1, court: 0, index: 3), from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds[1].score.firstServerIndex == 3)
        #expect(friendly.rounds[0].score.firstServerIndex == 0, "the round already played is untouched")
        #expect(try #require(SessionReducer.state(of: value)).firstServerIndex(round: 1) == 3)
    }

    @Test func drawingCarriesOnFromWhereARestoreLeftOff() throws {
        var straight = log()
        for round in 0 ..< 2 {
            winGames(&straight, 6, for: .a, round: round)
            straight.drawFriendlyRound(from: device)
        }
        let expected = try #require(session(straight)).rounds[2].teams

        // The same session picked back up out of history, then advanced.
        var restored = MatchLog()
        var carried = try #require(session(straight))
        carried.rounds.removeLast()
        restored.append(.restore(.friendly(carried)), from: device)
        restored.drawFriendlyRound(from: device)

        #expect(try #require(session(restored)).rounds[2].teams == expected)
    }

    // MARK: - The scoreboard

    @Test func theScoreboardNamesThePartnership() throws {
        var value = log()
        score(&value, round: 0, [.a, .a])
        let friendly = try #require(session(value))
        let board = try #require(ScoreboardSnapshot.make(from: .friendly(friendly)))

        #expect(board.kind == .friendly)
        #expect(board.teamNames.a == friendly.names(.a, in: friendly.rounds[0]))
        #expect(board.teamNames.a.contains(" & "), "two names, joined")
        #expect(board.games == BySide(both: 0))
        #expect(board.primary == BySide(a: "30", b: "0"))
        #expect(board.detail == "Round 1")
        #expect(!board.isLocked)
    }

    @Test func theScoreboardFollowsTheCurrentRound() throws {
        var value = log()
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        score(&value, round: 1, [.b])

        let friendly = try #require(session(value))
        let current = try #require(ScoreboardSnapshot.make(from: .friendly(friendly)))
        #expect(current.detail == "Round 2")
        #expect(current.primary == BySide(a: "0", b: "15"))

        let first = try #require(ScoreboardSnapshot.make(from: .friendly(friendly), round: 0))
        #expect(first.isLocked, "a round that is over takes no more taps")
        #expect(first.detail.hasSuffix("won"))
        #expect(first.serving == nil)
    }

    @Test func aStoppedRoundReadsAsStopped() throws {
        var value = log()
        winGames(&value, 3, for: .a, round: 0)
        value.append(.endRound(round: 0), from: device)

        let friendly = try #require(session(value))
        let board = try #require(ScoreboardSnapshot.make(from: .friendly(friendly)))
        #expect(board.detail == "Round 1 · stopped")
        #expect(board.isLocked)
        #expect(board.serving == nil)
    }

    @Test func theServingPlayerIsNamedInSingles() throws {
        var value = log(players: 3)
        #expect(try #require(session(value)).teamSize == 1)

        // The padel rotation asks for a second player on each side; a singles team has one.
        for game in 0 ..< 4 {
            let friendly = try #require(session(value))
            let board = try #require(ScoreboardSnapshot.make(from: .friendly(friendly)))
            #expect(board.servingPlayer != nil, "somebody serves in game \(game + 1)")
            winGames(&value, 1, for: .a, round: 0)
        }
    }

    @Test func theSetNumberOnlyShowsWhenThereIsMoreThanOne() throws {
        var value = log(rules: TraditionalRules(setsToWin: 2, gamesPerSet: 6))
        winGames(&value, 6, for: .a, round: 0)

        let friendly = try #require(session(value))
        let board = try #require(ScoreboardSnapshot.make(from: .friendly(friendly)))
        #expect(board.detail == "Round 1 · set 2")
    }

    // MARK: - Filing it away

    @Test func aFriendlySurvivesBeingFiledAway() throws {
        var value = log(players: 5)
        winGames(&value, 6, for: .a, round: 0)
        value.drawFriendlyRound(from: device)
        score(&value, round: 1, [.a, .b])
        let state = try #require(SessionReducer.state(of: value))

        let record = HistoryRecord(id: UUID(), title: state.title, state: state, startedAt: Date())
        let data = try JSONCoding.encoder.encode(record)
        let back = try JSONCoding.decoder.decode(HistoryRecord.self, from: data)

        #expect(back.state == state)
        #expect(SessionResult.make(from: back.state).rounds.count == 2)
    }

    /// The decoder is hand-rolled so a field added later cannot quietly make every filed
    /// session undecodable — `SessionStore.history()` drops those without a word.
    @Test func aRoundMissingTheNewerFieldsStillDecodes() throws {
        let round = FriendlyRound(
            index: 0,
            teams: BySide(a: [PlayerID()], b: [PlayerID()]),
            sitOuts: [PlayerID()],
            isStopped: true
        )
        let data = try JSONCoding.encoder.encode(round)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isStopped")
        object.removeValue(forKey: "sitOuts")

        let trimmed = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONCoding.decoder.decode(FriendlyRound.self, from: trimmed)

        #expect(!back.isStopped)
        #expect(back.sitOuts.isEmpty)
        #expect(back.teams == round.teams)
    }

    @Test func theReceiversChoiceLandsOnTheRoundInPlay() throws {
        var value = log(rules: TraditionalRules(setsToWin: 1, gamesPerSet: 6, deuceRule: .goldenPoint))
        // Three each is the first 40–40, which golden point makes sudden death.
        score(&value, round: 0, [.a, .b, .a, .b, .a, .b])
        value.append(.chooseServeSide(.ad), from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds[0].score.suddenDeathCourt == .ad)

        let board = try #require(ScoreboardSnapshot.make(from: .friendly(friendly)))
        #expect(board.isSuddenDeath)
        #expect(board.suddenDeathCourt == .ad)
        #expect(board.detail == "Round 1 · sudden death")
    }

    @Test func thereIsNoBoardForARoundThatIsNotThere() throws {
        let friendly = try #require(session(log()))
        #expect(ScoreboardSnapshot.make(from: .friendly(friendly), round: 5) == nil)
        #expect(ScoreboardSnapshot.make(from: .friendly(setup()), round: nil) == nil, "nothing drawn yet")
    }

    @Test func undoingTheOnlyDrawLeavesNothingOnTheBoard() throws {
        var value = log()
        let draw = try #require(value.lastUndoableEvent())
        value.append(.undo(draw.id), from: device)

        let friendly = try #require(session(value))
        #expect(friendly.rounds.isEmpty)
        #expect(friendly.currentIndex == 0)
        #expect(
            ScoreboardSnapshot.make(from: .friendly(friendly), round: nil) == nil,
            "nothing to draw, so a view showing it has to keep its own way out"
        )
        #expect(value.lastUndoableEvent() == nil, "nothing left to take back")
    }
}
