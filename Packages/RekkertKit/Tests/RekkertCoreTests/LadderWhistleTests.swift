import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000EE")!)
private let watch = DeviceID(UUID(uuidString: "FFFFFFFF-0000-0000-0000-0000000000EE")!)
/// Sorts before `phone` wherever the two tie, so what it does at the same moment folds first.
private let early = DeviceID(UUID(uuidString: "AAAAAAAA-0000-0000-0000-0000000000EE")!)

private func status(_ log: MatchLog, round: Int = 0, court: Int) -> CourtStatus? {
    ladder(log)?.status(round: round, court: court)
}

private func games(_ count: Int, _ side: TeamSide) -> [TeamSide] {
    repeated([side], 4 * count)
}

@Suite("Winner court ladder: the whistle")
struct LadderWhistleTests {
    @Test func theWhistleClosesEveryCourt() throws {
        var log = ladderLog()
        score(&log, court: 0, games(2, .a))
        score(&log, court: 1, games(1, .b))
        #expect(ladder(log)?.canDrawNextRound == false, "a timed round runs until the whistle")

        log.blowWhistle(from: phone)
        #expect(status(log, court: 0)?.winner == .a)
        #expect(status(log, court: 1)?.winner == .b)
        #expect(ladder(log)?.canDrawNextRound == true)
    }

    @Test func theGameInProgressGoesToWhoeverLeadsIt() {
        var log = ladderLog()
        score(&log, court: 0, games(2, .a) + games(2, .b) + [.b, .b])
        log.blowWhistle(from: phone)
        #expect(status(log, court: 0)?.winner == .b)
        #expect(status(log, court: 0)?.line == BySide(a: 2, b: 3))
    }

    @Test func aCourtLevelOnGamesWaitsForADecidingPoint() throws {
        var log = ladderLog()
        score(&log, court: 0, games(2, .a) + games(2, .b) + [.a, .b])
        score(&log, court: 1, games(1, .a))
        log.blowWhistle(from: phone)

        #expect(status(log, court: 0)?.awaitsDecider == true)
        #expect(ladder(log)?.canDrawNextRound == false)
        let snapshot = try #require(board(log, court: 0))
        #expect(snapshot.isSuddenDeath)
        #expect(snapshot.detail == "Round 1 · deciding point")

        score(&log, court: 0, [.b])
        #expect(status(log, court: 0)?.winner == .b)
        #expect(ladder(log)?.canDrawNextRound == true)
        #expect(board(log, court: 0)?.primary == BySide(a: "0", b: "1"))
    }

    @Test func theFirstDecidingPointDecidesAndTheRestAreIgnored() {
        var log = ladderLog()
        log.blowWhistle(from: phone)
        score(&log, court: 0, [.a, .b, .b])
        #expect(status(log, court: 0)?.winner == .a)
        #expect(ladder(log)?.rounds[0].matches[0].games == TraditionalState(), "no game was played after the whistle")
    }

    @Test func pointsAfterTheWhistleOnADecidedCourtAreIgnored() {
        var log = ladderLog()
        score(&log, court: 1, games(1, .a))
        log.blowWhistle(from: phone)
        let settled = status(log, court: 1)
        score(&log, court: 1, [.b, .b])
        #expect(status(log, court: 1) == settled)
    }

    @Test func aCourtNobodyScoredIsSettledByOneTap() {
        var log = ladderLog()
        log.blowWhistle(from: phone)
        #expect(status(log, court: 1)?.awaitsDecider == true)
        score(&log, court: 1, [.b])
        #expect(status(log, court: 1)?.winner == .b)
    }

    @Test func aMatchRoundWhistledEarlyGoesToWhoeverIsAhead() {
        var log = ladderLog(minutes: nil, rules: TraditionalRules(setsToWin: 2, gamesPerSet: 4, deuceRule: .goldenPoint))
        score(&log, court: 0, games(4, .a) + games(1, .b))
        score(&log, court: 1, games(4, .b))
        log.blowWhistle(from: phone)
        #expect(status(log, court: 0)?.winner == .a, "a set up")
        #expect(status(log, court: 1)?.winner == .b)
    }

    @Test func bothDevicesWhistlingAtOnceCloseOneRound() throws {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        var onPhone = ladderLog()
        score(&onPhone, court: 0, games(1, .a))
        var onWatch = onPhone
        onPhone.blowWhistle(from: phone, at: noon)
        let fromWatch = onWatch.blowWhistle(from: watch, at: noon.addingTimeInterval(2))
        onPhone.merge([fromWatch])
        #expect(ladder(onPhone)?.rounds[0].isEnded == true)

        for target in onPhone.undoTargets() { onPhone.append(.undo(target.id), from: phone) }
        #expect(ladder(onPhone)?.rounds[0].isEnded == false, "one press opens the round again")
    }

    @Test func aWhistleForAnEarlierOrCancelledRoundDoesNothing() {
        var log = ladderLog()
        log.blowWhistle(from: phone)
        log.drawRound(from: phone)
        log.append(.endRound(round: 0), from: phone)
        #expect(ladder(log)?.rounds[1].isEnded == false)

        log.append(.setRoundCancelled(round: 1, isCancelled: true), from: phone)
        log.blowWhistle(from: phone)
        #expect(ladder(log)?.rounds[1].isEnded == false)
    }

    @Test func aPointThatRacesTheWhistleFoldsTheSameEverywhere() {
        var start = ladderLog()
        score(&start, court: 0, games(1, .a))
        var onPhone = start
        var onWatch = start
        let whistle = onPhone.blowWhistle(from: phone)
        score(&onWatch, court: 0, [.b], from: watch)
        let point = onWatch.ordered.last!

        onPhone.merge([point])
        onWatch.merge([whistle])
        #expect(SessionReducer.state(of: onPhone) == SessionReducer.state(of: onWatch))
    }

    @Test func aDrawWithACourtStillUndecidedStillDraws() {
        var log = ladderLog()
        score(&log, court: 1, games(1, .b))
        log.drawRound(from: phone)
        #expect(ladder(log)?.rounds.count == 2, "the gate is the store's to keep")
    }

    /// The watch's point sorts before the whistle and the draw, and turns a decided court
    /// level. The round drawn after it has to survive the merge, with what was scored in it.
    @Test func aLatePointBeforeTheDrawLeavesTheNextRoundStanding() {
        var start = ladderLog()
        score(&start, court: 0, games(1, .a))
        var onWatch = start
        score(&onWatch, court: 0, games(1, .b), from: early)
        let late = Array(onWatch.ordered.suffix(4))

        var onPhone = start
        onPhone.blowWhistle(from: phone)
        onPhone.drawRound(from: phone)
        score(&onPhone, round: 1, court: 0, [.a])
        #expect(ladder(onPhone)?.status(round: 0, court: 0)?.winner == .a)
        onPhone.merge(late)

        #expect(ladder(onPhone)?.status(round: 0, court: 0)?.winner != .a, "the late point made it level at the whistle")
        #expect(ladder(onPhone)?.rounds.count == 2)
        #expect(ladder(onPhone)?.rounds[1].matches[0].games?.points == BySide(a: 1, b: 0))
    }

    /// Two points from the watch race the whistle and turn court 1 around: it was A's when
    /// the phone drew, and B's once they land. The score says so; the drawn round stays put.
    @Test func aLatePointThatTurnsACourtAroundMovesNobodyAlreadyDrawn() throws {
        var start = ladderLog()
        score(&start, court: 0, games(1, .a) + games(1, .b) + [.a])
        score(&start, court: 1, games(1, .a))
        var onWatch = start
        score(&onWatch, court: 0, [.b, .b], from: early)
        let late = Array(onWatch.ordered.suffix(2))

        var onPhone = start
        onPhone.blowWhistle(from: phone)
        onPhone.drawRound(from: phone)
        #expect(status(onPhone, court: 0)?.winner == .a)
        let drawn = try #require(ladder(onPhone)?.rounds[1])

        onPhone.merge(late)
        #expect(status(onPhone, court: 0)?.winner == .b, "the late points won court 1 at the whistle")
        #expect(ladder(onPhone)?.rounds[1] == drawn)
    }

    @Test func undoOnAnEarlierLadderRoundIsNotOffered() {
        var log = ladderLog()
        score(&log, court: 0, games(1, .a))
        log.blowWhistle(from: phone)
        score(&log, court: 1, [.a])
        #expect(!log.undoTargets(round: 0, court: 1).isEmpty)

        log.drawRound(from: phone)
        #expect(log.undoTargets(round: 0, court: 1).isEmpty)
        #expect(log.lastUndoableEvent(round: 0, court: 0) == nil)
    }

    @Test func undoingTheDecidingPointPutsTheCourtBackToWaiting() {
        var log = ladderLog()
        log.blowWhistle(from: phone)
        score(&log, court: 0, [.a])
        for target in log.undoTargets(round: 0, court: 0) { log.append(.undo(target.id), from: phone) }
        #expect(status(log, court: 0)?.awaitsDecider == true)
    }
}
