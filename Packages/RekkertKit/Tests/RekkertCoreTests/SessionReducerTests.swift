import Foundation
import Testing
@testable import RekkertCore

private let device = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!)
/// Sorts after `device` wherever the two tie, so what it does at the same moment folds last.
private let later = DeviceID(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000003")!)

private func tournamentLog(players: Int = 8, courts: Int = 2, target: Int = 16) -> MatchLog {
    let tournament = Tournament(
        id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!),
        name: "Thursday",
        format: .americano,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: target), courtCount: courts)
    )
    var log = MatchLog(sessionID: UUID(uuidString: "22222222-0000-0000-0000-000000000000")!)
    log.append(.configure(.tournament(tournament)), from: device)
    log.drawRound(from: device)
    return log
}

private func tournament(_ log: MatchLog) -> Tournament? {
    guard case .tournament(let value) = SessionReducer.state(of: log) else { return nil }
    return value
}

@Suite("Session reducer")
struct SessionReducerTests {
    @Test func emptyLogHasNoState() {
        #expect(SessionReducer.state(of: MatchLog()) == nil)
    }

    @Test func pointsLandOnTheAddressedCourt() {
        var log = tournamentLog()
        log.append(.point(round: 0, court: 1, team: .b), from: device)
        log.append(.point(round: 0, court: 1, team: .b), from: device)
        log.append(.point(round: 0, court: 0, team: .a), from: device)

        let round = tournament(log)?.rounds[0]
        #expect(round?.matches[0].state.points == BySide(a: 1, b: 0))
        #expect(round?.matches[1].state.points == BySide(a: 0, b: 2))
    }

    @Test func settingAScoreOverwritesAndClamps() {
        var log = tournamentLog(target: 16)
        log.append(.point(round: 0, court: 0, team: .a), from: device)
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 11, b: 99)), from: device)

        #expect(tournament(log)?.rounds[0].matches[0].state.points == BySide(a: 11, b: 5))
    }

    @Test func undoingASetScoreRestoresTheTappedScore() {
        var log = tournamentLog()
        log.append(.point(round: 0, court: 0, team: .a), from: device)
        let correction = log.append(.setScore(round: 0, court: 0, points: BySide(a: 11, b: 5)), from: device)
        log.append(.undo(correction.id), from: device)

        #expect(tournament(log)?.rounds[0].matches[0].state.points == BySide(a: 1, b: 0))
    }

    @Test func confirmingARoundLocksItsCourts() {
        var log = tournamentLog()
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.append(.point(round: 0, court: 0, team: .a), from: device)

        let round = tournament(log)?.rounds[0]
        #expect(round?.matches.allSatisfy(\.isConfirmed) == true)
        #expect(round?.matches[0].state.points == BySide(a: 0, b: 0), "a locked court ignores points")
    }

    @Test func nextRoundUsesResultsSoFar() {
        var log = tournamentLog()
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 12, b: 4)), from: device)
        log.append(.setScore(round: 0, court: 1, points: BySide(a: 9, b: 7)), from: device)
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.drawRound(from: device)

        let value = tournament(log)
        #expect(value?.rounds.count == 2)
        #expect(value?.rounds[1].matches.count == 2)
        #expect(value?.rounds[0].matches[0].state.points == BySide(a: 12, b: 4), "round 1 is untouched")
    }

    @Test func undoingNextRoundTakesTheRoundBack() {
        var log = tournamentLog()
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        let advance = log.drawRound(from: device)
        #expect(tournament(log)?.rounds.count == 2)

        log.append(.undo(advance.id), from: device)
        #expect(tournament(log)?.rounds.count == 1)
    }

    @Test func reconfiguringKeepsProgress() {
        var log = tournamentLog(target: 16)
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 10, b: 6)), from: device)

        var updated = tournament(log)!
        updated.config.pointRules.target = 24
        log.append(.configure(.tournament(updated)), from: device)

        #expect(tournament(log)?.config.pointRules.target == 24)
        #expect(tournament(log)?.rounds[0].matches[0].state.points == BySide(a: 10, b: 6))
    }

    @Test func finishMarksTheTournamentDone() {
        var log = tournamentLog()
        log.append(.finish(archive: true), from: device)
        #expect(tournament(log)?.isFinished == true)
        #expect(SessionReducer.state(of: log)?.isFinished == true)
    }

    /// A round drawn on one phone as the tournament was finished on another. Folded after the
    /// finish, it put a round nobody played on the finished tournament, and paid its bench for
    /// sitting it out.
    @Test func aDrawThatCrossesTheFinishDoesNotLand() throws {
        var onHost = tournamentLog(players: 9)
        var onGuest = onHost
        let finish = onHost.append(.finish(archive: true), from: device)
        let draw = onGuest.drawRound(from: later)
        onHost.merge([draw])
        onGuest.merge([finish])

        let value = try #require(tournament(onHost))
        #expect(value.isFinished)
        #expect(value.rounds.count == 1, "it ends as it was finished")
        #expect(SessionReducer.state(of: onHost) == SessionReducer.state(of: onGuest))
    }

    @Test func aPointThatCrossesTheFinishDoesNotLand() throws {
        var onHost = tournamentLog()
        var onGuest = onHost
        let finish = onHost.append(.finish(archive: true), from: device)
        let point = onGuest.append(.point(round: 0, court: 0, team: .a), from: later)
        onHost.merge([point])
        onGuest.merge([finish])

        let value = try #require(tournament(onHost))
        #expect(value.rounds[0].matches[0].state.points == BySide(a: 0, b: 0))
        #expect(SessionReducer.state(of: onHost) == SessionReducer.state(of: onGuest))
    }

    /// A match called off on one phone as a point went in on another. Stopped is where it stopped.
    @Test func aPointThatCrossesAStopDoesNotLand() throws {
        var onHost = MatchLog()
        onHost.append(.configure(.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))), from: device)
        onHost.append(.point(round: 0, court: 0, team: .a), from: device)
        var onGuest = onHost
        let stop = onHost.append(.finish(archive: true), from: device)
        let point = onGuest.append(.point(round: 0, court: 0, team: .b), from: later)
        onHost.merge([point])
        onGuest.merge([stop])

        guard case .traditional(let session)? = SessionReducer.state(of: onHost) else {
            Issue.record("a match")
            return
        }
        #expect(session.isStopped)
        #expect(session.score.points == BySide(a: 1, b: 0))
        #expect(SessionReducer.state(of: onHost) == SessionReducer.state(of: onGuest))
    }

    @Test func courtCountReflectsTheCurrentRound() {
        #expect(SessionReducer.state(of: tournamentLog(players: 8, courts: 2))?.courtCount == 2)
        #expect(SessionReducer.state(of: tournamentLog(players: 6, courts: 2))?.courtCount == 1)
    }

    @Test func anEditToAnEarlierRoundDoesNotLandOnTheCurrentOne() {
        var log = tournamentLog()
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 9, b: 7)), from: device)
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.drawRound(from: device)
        log.append(.point(round: 1, court: 0, team: .a), from: device)

        // Round 0 is locked, so correcting it needs reopening first.
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 12, b: 4)), from: device)
        #expect(tournament(log)?.rounds[0].matches[0].state.points == BySide(a: 9, b: 7),
                "a confirmed round ignores edits until it is reopened")

        log.append(.setRoundConfirmed(round: 0, isConfirmed: false), from: device)
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 12, b: 4)), from: device)

        let value = try! #require(tournament(log))
        #expect(value.rounds[0].matches[0].state.points == BySide(a: 12, b: 4), "the old round is corrected")
        #expect(value.rounds[1].matches[0].state.points == BySide(a: 1, b: 0), "the current round is untouched")
        #expect(value.rounds.count == 2)
    }

    @Test func aLatePointForAnOldRoundStillLandsOnThatRound() {
        var log = tournamentLog()

        // Scored on the watch while it was still on round 0, stamped there and then.
        let onTheWatch = MatchEvent(
            id: EventID(device: DeviceID(), seq: 1),
            lamport: 3,
            kind: .point(round: 0, court: 0, team: .b)
        )

        // The phone meanwhile moves the tournament on, and only then does it arrive.
        log.drawRound(from: device)
        log.merge([onTheWatch])

        let value = try! #require(tournament(log))
        #expect(value.rounds[0].matches[0].state.points == BySide(a: 0, b: 1),
                "it belongs to the round it was scored in")
        #expect(value.rounds[1].matches[0].state.points == BySide(a: 0, b: 0))
    }

    @Test func bothDevicesAdvancingAtOnceDrawsOneRound() {
        var log = tournamentLog()
        let watch = DeviceID()

        var onPhone = log
        var onWatch = log
        let fromPhone = onPhone.drawRound(from: device)
        let fromWatch = onWatch.drawRound(from: watch)

        onPhone.merge([fromWatch])
        onWatch.merge([fromPhone])

        #expect(tournament(onPhone)?.rounds.count == 2, "one whistle, one new round")
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))

        // And the round that did get drawn is still the live one.
        log = onPhone
        log.drawRound(from: device)
        #expect(tournament(log)?.rounds.count == 3, "advancing again still works")
    }

    /// The draw that lost the race changed nothing, and it sorts last — so it was what Undo reached
    /// for, and the first press did nothing at all.
    @Test func undoAfterTwoDrawsAtOnceTakesBackTheRoundThatWasDrawn() throws {
        let log = tournamentLog()
        var onPhone = log
        var onWatch = log
        let fromPhone = onPhone.drawRound(from: device)
        let fromWatch = onWatch.drawRound(from: later)
        onPhone.merge([fromWatch])
        #expect(tournament(onPhone)?.rounds.count == 2)

        let target = try #require(onPhone.lastUndoableEvent())
        #expect(target.id == fromPhone.id, "the draw that landed, not the one turned away")
        let targets = onPhone.undoTargets()
        #expect(Set(targets.map(\.id)) == [fromPhone.id, fromWatch.id], "and the one that would land in its place")
        for target in targets { onPhone.append(.undo(target.id), from: device) }
        #expect(tournament(onPhone)?.rounds.count == 1, "one press takes the round back")
    }

    /// Two courts, one phone each. Undo on court 2's own screen took back court 1's point.
    @Test func undoOnOneCourtLeavesTheOtherCourtAlone() throws {
        var log = tournamentLog()
        let mine = log.append(.point(round: 0, court: 1, team: .a), from: device)
        log.append(.point(round: 0, court: 0, team: .b), from: later)

        let target = try #require(log.lastUndoableEvent(round: 0, court: 1))
        #expect(target.id == mine.id)
        log.append(.undo(target.id), from: device)
        let round = try #require(tournament(log)?.rounds.first)
        #expect(round.matches.first { $0.courtIndex == 0 }?.state.points == BySide(a: 0, b: 1), "court 1 keeps its point")
        #expect(round.matches.first { $0.courtIndex == 1 }?.state.points == BySide(a: 0, b: 0))
    }

    @Test func undoingTheDrawLeavesNoRoundButStaysRecoverable() {
        var log = tournamentLog()
        #expect(tournament(log)?.rounds.count == 1)

        // What the Undo button reaches for on a freshly drawn tournament.
        let draw = try! #require(log.lastUndoableEvent())
        #expect(draw.kind == .nextRound(after: -1))
        log.append(.undo(draw.id), from: device)

        let stranded = try! #require(tournament(log))
        #expect(stranded.currentRound == nil)
        #expect(stranded.playableCourts >= 1, "the UI must still offer to draw a round")

        log.drawRound(from: device)
        #expect(tournament(log)?.rounds.count == 1, "drawing again recovers")
    }

    @Test func aTournamentTooSmallToFillACourtReportsItRatherThanDrawing() {
        let tiny = Tournament(name: "Two of us", format: .americano,
                              players: (0 ..< 3).map { Player(name: "P\($0)") })
        var log = MatchLog()
        log.append(.configure(.tournament(tiny)), from: device)
        log.drawRound(from: device)

        let state = try! #require(tournament(log))
        #expect(state.playableCourts == 0, "the draw button is disabled on this")
        #expect(state.currentRound == nil, "and no round is silently invented")
    }

    @Test func aCancelledRoundTakesNoMorePoints() {
        var log = tournamentLog()
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 5, b: 3)), from: device)
        log.append(.setRoundCancelled(round: 0, isCancelled: true), from: device)
        log.append(.point(round: 0, court: 0, team: .a), from: device)

        let value = try! #require(tournament(log))
        #expect(value.rounds[0].isCancelled)
        #expect(value.rounds[0].matches[0].state.points == BySide(a: 5, b: 3))
        #expect(Leaderboard.standings(for: value).allSatisfy { $0.total == 0 })
    }

    @Test func onlyTheLastRoundCanBeCancelled() {
        var log = tournamentLog()
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.drawRound(from: device)
        log.append(.setRoundCancelled(round: 0, isCancelled: true), from: device)

        #expect(tournament(log)?.rounds[0].isCancelled == false,
                "a cancel that arrives after the next draw must not void what it was drawn from")
    }

    @Test func undoingACancelCountsTheRoundAgain() {
        var log = tournamentLog()
        log.append(.setScore(round: 0, court: 0, points: BySide(a: 10, b: 6)), from: device)
        let cancel = log.append(.setRoundCancelled(round: 0, isCancelled: true), from: device)
        #expect(tournament(log).flatMap { Leaderboard.standings(for: $0).first?.total } == 0)

        #expect(log.lastUndoableEvent() == cancel)
        log.append(.undo(cancel.id), from: device)
        #expect(tournament(log)?.rounds[0].isCancelled == false)
        #expect(tournament(log).flatMap { Leaderboard.standings(for: $0).first?.total } == 10)
    }

    @Test func aRoundCanBeDrawnAfterACancelledOne() {
        var log = tournamentLog()
        log.append(.setRoundCancelled(round: 0, isCancelled: true), from: device)
        log.drawRound(from: device)

        let value = try! #require(tournament(log))
        #expect(value.rounds.count == 2)
        #expect(value.rounds[0].isCancelled)
        #expect(!value.rounds[1].isCancelled)
    }

    // MARK: - Choosing who sits out

    @Test func pickingTheBenchRedrawsARoundNothingHasHappenedIn() throws {
        var log = tournamentLog(players: 9)
        let drawn = try #require(tournament(log)?.currentRound)
        let late = try #require(tournament(log)?.players.map(\.id).first { !drawn.sitOuts.contains($0) })

        log.redrawRound(sittingOut: [late], from: device)

        let value = try #require(tournament(log))
        #expect(value.rounds.count == 1, "redrawn in place rather than added")
        #expect(value.rounds[0].sitOuts == [late])
        #expect(!value.rounds[0].matches.flatMap(\.allPlayers).contains(late))
    }

    @Test(arguments: [
        EventKind.point(round: 0, court: 1, team: .a),
        .setRoundConfirmed(round: 0, isConfirmed: true),
        .setRoundCancelled(round: 0, isCancelled: true),
        .finish(archive: true),
    ])
    func aRoundThatHasStartedIsNotRedrawn(first: EventKind) throws {
        var log = tournamentLog(players: 9)
        log.append(first, from: device)
        let before = try #require(tournament(log))
        let late = try #require(before.players.map(\.id).first { !before.rounds[0].sitOuts.contains($0) })

        log.redrawRound(sittingOut: [late], from: device)

        #expect(tournament(log) == before)
    }

    @Test func undoingARedrawBringsBackTheRoundAsDrawn() throws {
        var log = tournamentLog(players: 9)
        let drawn = try #require(tournament(log))
        let late = try #require(drawn.players.map(\.id).first { !drawn.rounds[0].sitOuts.contains($0) })

        let redraw = log.redrawRound(sittingOut: [late], from: device)
        #expect(log.lastUndoableEvent() == redraw)
        log.append(.undo(redraw.id), from: device)

        #expect(tournament(log) == drawn)
    }

    @Test func aRedrawThatArrivesAfterTheNextRoundDoesNothing() throws {
        var log = tournamentLog(players: 9)
        let late = try #require(tournament(log)?.players.map(\.id).first {
            tournament(log)?.rounds[0].sitOuts.contains($0) == false
        })
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        log.drawRound(from: device)
        let before = try #require(tournament(log))

        // Meant for round 1, which has been moved past; round 2 is untouched, but not what it named.
        log.append(.nextRound(after: -1, sitOuts: [late]), from: device)

        #expect(tournament(log) == before)
    }

    @Test func twoDevicesRedrawingAtOnceAgree() throws {
        let base = tournamentLog(players: 10)
        var phone = base
        var watch = base
        let players = try #require(tournament(base)).players.map(\.id)

        let one = phone.redrawRound(sittingOut: [players[0]], from: device)
        let two = watch.redrawRound(sittingOut: [players[1]], from: DeviceID())
        phone.merge([two])
        watch.merge([one])

        #expect(SessionReducer.state(of: phone) == SessionReducer.state(of: watch))
        #expect(tournament(phone)?.rounds.count == 1)
    }

    @Test func aDrawCanNameItsBench() throws {
        var log = tournamentLog(players: 9)
        log.append(.setRoundConfirmed(round: 0, isConfirmed: true), from: device)
        let late = try #require(tournament(log)?.players.first { $0.name == "P4" }).id
        log.append(.nextRound(after: 0, sitOuts: [late]), from: device)

        #expect(tournament(log)?.rounds.count == 2)
        #expect(tournament(log)?.rounds[1].sitOuts == [late])
    }

    @Test func aDrawThatPicksNobodyEncodesAsItAlwaysHas() throws {
        let plain = try JSONCoding.encoder.encode(EventKind.nextRound(after: 0))
        #expect(!String(decoding: plain, as: UTF8.self).contains("sitOuts"))

        let picked = EventKind.nextRound(after: 0, sitOuts: [Player(name: "P1").id])
        #expect(try JSONCoding.decoder.decode(EventKind.self, from: JSONCoding.encoder.encode(picked)) == picked)
    }

    @Test func concurrentPointsOnDifferentCourtsBothLand() {
        let base = tournamentLog()
        var phone = base
        var watch = base
        let other = DeviceID(UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!)

        let one = phone.append(.point(round: 0, court: 0, team: .a), from: device)
        let two = watch.append(.point(round: 0, court: 1, team: .b), from: other)
        phone.merge([two])
        watch.merge([one])

        #expect(tournament(phone)?.rounds[0].matches[0].state.points == BySide(a: 1, b: 0))
        #expect(tournament(phone)?.rounds[0].matches[1].state.points == BySide(a: 0, b: 1))
        #expect(SessionReducer.state(of: phone) == SessionReducer.state(of: watch))
    }
}
