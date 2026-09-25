import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "71717171-0000-0000-0000-00000000000A")!)
private let watch = DeviceID(UUID(uuidString: "71717171-0000-0000-0000-00000000000B")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)
private func seconds(_ count: Double) -> Date { noon.addingTimeInterval(count) }

private let teams = BySide(a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]), b: TeamInfo(name: "Them", players: ["Kim", "Sam"]))

/// A log that stamps each event half a minute after the last, like a match being played.
private struct Play {
    var log = MatchLog(sessionID: UUID(uuidString: "72727272-0000-0000-0000-000000000000")!, createdAt: noon)
    var clock: Double = 0

    @discardableResult
    mutating func append(_ kind: EventKind, from device: DeviceID = phone) -> MatchEvent {
        defer { clock += 30 }
        return log.append(kind, from: device, at: seconds(clock))
    }

    mutating func points(_ sides: [TeamSide], round: Int = 0, court: Int = 0) {
        for side in sides { append(.point(round: round, court: court, team: side)) }
    }

    var timeline: MatchTimeline { MatchTimeline.make(from: log) }
    var state: SessionState? { SessionReducer.state(of: log) }
}

private func match(_ rules: TraditionalRules = TraditionalRules()) -> Play {
    var play = Play()
    play.append(.configure(.traditional(rules: rules, teams: teams), at: noon))
    return play
}

private func tournament(players: Int = 8, courts: Int = 2) -> Play {
    var play = Play()
    let setup = Tournament(
        id: TournamentID(UUID(uuidString: "73737373-0000-0000-0000-000000000000")!),
        format: .americano,
        players: (0 ..< players).map { Player(name: "P\($0)") },
        config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: courts)
    )
    play.append(.configure(.tournament(setup), at: noon))
    play.append(.nextRound(after: -1, at: noon))
    return play
}

@Suite("The timeline of a match")
struct MatchTimelineTests {
    // MARK: - Point by point

    @Test func everyPointIsKeptWithTheScoreItMade() {
        var play = match()
        play.points([.a, .b, .a])
        let entries = play.timeline.entries

        #expect(entries.map(\.winner) == [.a, .b, .a])
        #expect(entries.map(\.board.points) == [BySide(a: "15", b: "0"), BySide(a: "15", b: "15"), BySide(a: "30", b: "15")])
        #expect(entries.map(\.at) == [seconds(30), seconds(60), seconds(90)])
    }

    @Test func aGameASetAndTheMatchAreMarkedOnThePointThatWonThem() throws {
        var play = match(TraditionalRules(setsToWin: 1))
        play.points(repeated([.a], 24))
        let ended = play.timeline.entries.compactMap(\.ended)

        #expect(ended.count == 6)
        #expect(ended.prefix(5).allSatisfy { $0 == .game(.a) })
        #expect(ended.last == .match(.a))
        #expect(play.timeline.entries.last?.board.sets == [BySide(a: 6, b: 0)])
    }

    @Test func theServerIsWhoeverServedThePoint() throws {
        var play = match()
        var expected: [TeamSide?] = []
        for side in repeated([.b], 4) + repeated([.a], 3) {
            expected.append(play.state?.serve()?.slot.team)
            play.points([side])
        }
        #expect(play.timeline.entries.map(\.server) == expected)
    }

    @Test func aGameWonAgainstTheServeIsABreak() {
        var play = match()
        let firstServer = play.state?.serve()?.slot.team
        let receiver = firstServer?.other ?? .b
        // The receivers take the first game, then the new servers hold theirs.
        play.points(repeated([receiver], 4))
        play.points(repeated([receiver], 4))
        let stats = play.timeline.stats()

        #expect(stats.breaks[receiver] == 1)
        #expect(stats.breaks[receiver.other] == 0)
    }

    @Test func aGoldenPointIsMarkedAndCounted() throws {
        var play = match(TraditionalRules(deuceRule: .goldenPoint))
        play.points(repeated([.a, .b], 3) + [.b])
        let decider = try #require(play.timeline.entries.last)

        #expect(decider.wasSuddenDeath)
        #expect(decider.ended == .game(.b))
        #expect(play.timeline.entries.dropLast().allSatisfy { !$0.wasSuddenDeath })
        #expect(play.timeline.stats().suddenDeathWon == BySide(a: 0, b: 1))
    }

    @Test func aTiebreakPointIsMarkedAndNeverABreak() throws {
        var play = match(TraditionalRules(setsToWin: 1))
        for _ in 0 ..< 6 { play.points(repeated([.a], 4)); play.points(repeated([.b], 4)) }
        play.points(repeated([.b], 7))
        let tiebreak = play.timeline.entries.suffix(7)

        #expect(tiebreak.allSatisfy { $0.wasTiebreak })
        #expect(tiebreak.last?.ended == .match(.b))
        #expect(!(tiebreak.last?.isBreak ?? true))
    }

    // MARK: - What leaves no mark

    @Test func anUndonePointIsNotThere() {
        var play = match()
        play.points([.a])
        let mistake = play.append(.point(round: 0, court: 0, team: .b))
        play.append(.undo(mistake.id))
        play.points([.a])

        #expect(play.timeline.entries.map(\.winner) == [.a, .a])
    }

    @Test func anUndoTakenBackPutsThePointBack() {
        var play = match()
        let point = play.append(.point(round: 0, court: 0, team: .b))
        let undo = play.append(.undo(point.id))
        play.append(.undo(undo.id))

        #expect(play.timeline.entries.map(\.winner) == [.b])
    }

    @Test func aPointOnAConfirmedCourtIsTurnedAway() {
        var play = tournament()
        play.points([.a], court: 0)
        play.append(.setRoundConfirmed(round: 0, isConfirmed: true))
        play.points([.a], court: 0)

        #expect(play.timeline.entries(court: 0).map(\.winner) == [.a])
    }

    @Test func aServeCorrectionIsNotAnEntry() {
        var play = match()
        play.points([.a])
        play.append(.setFirstServer(round: 0, court: 0, index: 1))
        #expect(play.timeline.entries.count == 1)
    }

    // MARK: - The modes

    @Test func theWhistleHandsTheGameToTheLeaderAndStartsTheNextRound() throws {
        var play = Play()
        play.append(.configure(.winnerCourt(rules: WinnerCourtRules(), teams: teams), at: noon))
        // A game up, and ahead in the next when the whistle goes.
        play.points(repeated([.a], 4) + [.a, .a, .b])
        play.append(.endRound(round: 0, at: seconds(999)))
        play.points([.a])
        let entries = play.timeline.entries
        let whistle = try #require(entries.first { $0.kind == .whistle })

        #expect(whistle.round == 0)
        #expect(whistle.ended == .set(.a))
        #expect(whistle.board.sets == [BySide(a: 2, b: 0)])
        #expect(entries.last?.round == 1)
        #expect(entries.last?.board.points == BySide(a: "15", b: "0"))
    }

    @Test func aTypedScoreIsACorrection() {
        var play = tournament()
        play.points([.a, .a], court: 1)
        play.append(.setScore(round: 0, court: 1, points: BySide(a: 10, b: 6)))
        let court = play.timeline.entries(court: 1)

        #expect(court.map(\.kind) == [.point(.a), .point(.a), .corrected])
        #expect(court.last?.board.points == BySide(a: "10", b: "6"))
        #expect(court.last?.ended == .match(.a))
    }

    @Test func aLatePointLandsOnTheRoundItWasScoredIn() {
        var play = tournament()
        play.points([.a], court: 0)
        play.append(.nextRound(after: 0, at: seconds(600)))
        play.points([.b], round: 0, court: 0)

        #expect(play.timeline.entries.map(\.round) == [0, 0])
        #expect(play.timeline.entries.last?.board.points == BySide(a: "1", b: "1"))
    }

    @Test func aFriendlyKeepsEachRoundApart() throws {
        var play = Play()
        let friendly = FriendlySession(
            id: FriendlyID(UUID(uuidString: "74747474-0000-0000-0000-000000000000")!),
            rules: TraditionalRules(setsToWin: 1, deuceRule: .goldenPoint),
            players: (0 ..< 4).map { Player(name: "P\($0)") }
        )
        play.append(.configure(.friendly(friendly), at: noon))
        play.append(.nextRound(after: -1, at: noon))
        play.points([.a, .a], round: 0)
        play.append(.endRound(round: 0, at: seconds(500)))
        play.append(.nextRound(after: 0, at: seconds(510)))
        play.points([.b], round: 1)

        #expect(play.timeline.entries(round: 0).map(\.winner) == [.a, .a])
        #expect(play.timeline.entries(round: 1).map(\.board.points) == [BySide(a: "0", b: "15")])
    }

    @Test func settlingOnlyMarksTheCourtsItMoved() throws {
        var play = tournament()
        play.points([.a], court: 0)
        play.points([.b], court: 1)
        guard case .tournament(var settled) = play.state else { Issue.record("not a tournament"); return }
        settled.rounds[0].matches[1].state.points = BySide(a: 3, b: 5)
        play.append(.restore(.tournament(settled)))
        let marks = play.timeline.entries.filter { $0.kind == .settled }

        #expect(marks.map(\.court) == [1])
        #expect(marks.first?.board.points == BySide(a: "3", b: "5"))
    }

    // MARK: - Carried over

    @Test func aResultTakenBackCarriesOnWithoutTheLastPoint() throws {
        var first = match(TraditionalRules(setsToWin: 1))
        first.points(repeated([.a], 24))
        let carry = TimelineCarry.takingBack(first.log, into: UUID(), carried: nil, me: nil)
        let rewound = try #require(SessionReducer.state(of: first.log.takingBackTheResult()))

        var second = Play()
        second.clock = 2000
        second.append(.restore(rewound))
        second.points([.b, .b])
        let timeline = MatchTimeline.make(from: second.log, continuing: carry)

        #expect(timeline.entries.count == 23 + 2)
        #expect(!timeline.entries.contains { $0.kind == .settled })
        #expect(timeline.entries.last?.board.points == BySide(a: "40", b: "30"))
        #expect(carry.startedAt == noon)
    }

    @Test func aSessionPickedBackUpSaysWhen() throws {
        var first = match()
        first.points([.a, .a])
        let carry = TimelineCarry(sessionID: UUID(), reason: .resumed, timeline: first.timeline)

        var second = Play()
        second.clock = 86_400
        second.append(.restore(try #require(first.state)))
        second.points([.b])
        let timeline = MatchTimeline.make(from: second.log, continuing: carry)

        #expect(timeline.resumedAt == [seconds(86_400)])
        #expect(timeline.entries.map(\.winner) == [.a, .a, .b])
    }

    @Test func aRestoreWithNothingCarriedStartsFromItsScore() throws {
        var first = match()
        first.points([.a, .a])
        var second = Play()
        second.append(.restore(try #require(first.state)))

        #expect(MatchTimeline.make(from: second.log).entries.map(\.kind) == [.settled])
    }

    // MARK: - Reading it

    @Test func theLongestRunStopsWhenTheOtherSideScores() {
        var play = match()
        play.points([.a, .a, .a, .b, .a, .b, .b, .b, .b, .b])
        let stats = play.timeline.stats()

        #expect(stats.pointsWon == BySide(a: 4, b: 6))
        #expect(stats.longestRun == BySide(a: 3, b: 5))
    }

    @Test func momentumIsTheRunningDifference() {
        var play = match()
        play.points([.a, .a, .b, .b, .b])
        #expect(play.timeline.momentum().map(\.lead) == [1, 2, 1, 0, -1])
    }

    // MARK: - The invariant

    /// Whatever happens in whatever order, the last entry on each court is the score that
    /// was filed — the one property everything drawn from the timeline leans on.
    @Test(arguments: 0 ..< 12)
    func theLastEntryIsAlwaysTheFiledScore(seed: Int) throws {
        var generator = SeededGenerator(seed: UInt64(seed))
        var play = seed.isMultiple(of: 3) ? tournament() : (seed % 3 == 1 ? match(TraditionalRules(deuceRule: .starPoint)) : Play())
        if seed % 3 == 2 {
            play.append(.configure(.winnerCourt(rules: WinnerCourtRules(), teams: teams), at: noon))
        }
        var recorded: [MatchEvent] = []
        for step in 0 ..< 150 {
            let roll = Int.random(in: 0 ..< 20, using: &generator)
            let side: TeamSide = Bool.random(using: &generator) ? .a : .b
            let court = Int.random(in: 0 ..< 2, using: &generator)
            let device = Bool.random(using: &generator) ? phone : watch
            switch roll {
            case 0 where !recorded.isEmpty:
                play.append(.undo(recorded.removeLast().id), from: device)
            case 1:
                play.append(.endRound(round: step / 40, at: seconds(Double(step))), from: device)
            case 2:
                play.append(.setScore(round: 0, court: court, points: BySide(a: step % 9, b: step % 5)), from: device)
            case 3:
                play.append(.setRoundConfirmed(round: 0, isConfirmed: Bool.random(using: &generator)), from: device)
            default:
                recorded.append(play.append(.point(round: 0, court: court, team: side), from: device))
            }
        }
        let state = try #require(play.state)
        let timeline = play.timeline

        for (slot, board) in MatchTimeline.boards(of: state) where !board.isBlank {
            let last = timeline.entries.last { entry in
                if case .winnerCourt = state { true } else { entry.round == slot.round && entry.court == slot.court }
            }
            #expect(last?.board == board)
        }
    }

    // MARK: - On disk

    @Test func itReadsBackAsItWasWritten() throws {
        var play = match(TraditionalRules(deuceRule: .goldenPoint))
        play.points(repeated([.a, .b], 3) + [.a] + repeated([.b], 4))
        var timeline = play.timeline
        timeline.me = PlayerID(UUID(uuidString: "75757575-0000-0000-0000-000000000000")!)
        timeline.resumedAt = [seconds(10)]

        let decoded = try JSONDecoder().decode(MatchTimeline.self, from: JSONEncoder().encode(timeline))
        #expect(decoded == timeline)
    }

    @Test func aLongMatchStaysSmall() throws {
        var play = match()
        for _ in 0 ..< 3 { play.points(repeated([.a, .b], 60)) }
        let size = try JSONEncoder().encode(play.timeline).count
        #expect(play.timeline.entries.count == 360)
        #expect(size < 40_000)
    }
}
