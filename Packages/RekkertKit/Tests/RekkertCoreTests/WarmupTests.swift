import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000F1")!)
private let watch = DeviceID(UUID(uuidString: "FFFFFFFF-0000-0000-0000-0000000000F1")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)
private func minutes(_ count: Double) -> Date { noon.addingTimeInterval(count * 60) }

private let teams = BySide(
    a: TeamInfo(name: "Us", players: ["Jonas", "Ada"]),
    b: TeamInfo(name: "Them", players: ["Kim", "Sam"])
)

private let americano = Tournament(
    id: TournamentID(UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!),
    name: "Thursday",
    format: .americano,
    players: (0 ..< 8).map { Player(name: "P\($0)") },
    config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 2)
)

private let friendly = FriendlySession(
    id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!),
    name: "Thursday",
    players: (0 ..< 4).map { Player(name: "P\($0)") }
)

private let setups: [SessionSetup] = [
    .traditional(rules: TraditionalRules(), teams: teams),
    .pointCount(rules: PointCountRules(), teams: teams),
    .winnerCourt(rules: WinnerCourtRules(), teams: teams),
    .tournament(americano),
    .tournament(makeLadder(players: 8, courts: 2)),
    .friendly(friendly),
]

/// Mirrors `NewSessionView.start()`: a session that plays in rounds has its first one drawn
/// as it starts, warm-up or not.
private func warmingUp(_ setup: SessionSetup) -> MatchLog {
    var log = MatchLog(sessionID: UUID(uuidString: "44444444-0000-0000-0000-0000000000F1")!)
    log.append(.configure(setup, at: noon, warmup: true), from: phone)
    switch setup {
    case .tournament: log.drawRound(from: phone, at: noon)
    case .friendly: log.drawFriendlyRound(from: phone, at: noon)
    case .traditional, .pointCount, .winnerCourt: break
    }
    return log
}

private func state(_ log: MatchLog) -> SessionState? { SessionReducer.state(of: log) }

private func clockStart(_ log: MatchLog) -> Date? {
    state(log).flatMap { ScoreboardSnapshot.make(from: $0) }?.clockStart
}

@Suite("Warm-up")
struct WarmupTests {
    @Test(arguments: setups)
    func everyModeCanOpenOnAWarmup(_ setup: SessionSetup) {
        #expect(state(warmingUp(setup))?.warmingUpSince == noon)
    }

    @Test(arguments: setups)
    func startingTheGameEndsTheWarmupAndStartsTheClock(_ setup: SessionSetup) throws {
        var log = warmingUp(setup)
        log.append(.endWarmup(at: minutes(10)), from: phone)

        let started = try #require(state(log))
        #expect(started.warmingUpSince == nil)
        #expect(clockStart(log) == minutes(10), "the game is timed from its start, not the warm-up's")
    }

    @Test func withoutTheSwitchThereIsNoWarmup() {
        var log = MatchLog()
        log.append(.configure(.traditional(rules: TraditionalRules(), teams: teams), at: noon), from: phone)
        #expect(state(log)?.warmingUpSince == nil)
        #expect(clockStart(log) == noon)
    }

    @Test func aTimedLadderRoundsCountdownWaitsForTheGame() throws {
        var log = warmingUp(.tournament(makeLadder(players: 8, courts: 2, minutes: 12)))
        log.append(.endWarmup(at: minutes(5)), from: phone)
        #expect(ladder(log)?.currentRound?.clock == RoundClock(length: 12 * 60, runningSince: minutes(5)))
    }

    @Test func theAlarmDoesNotRingDuringTheWarmup() {
        let session = UUID()
        let log = warmingUp(.tournament(makeLadder(players: 8, courts: 2, minutes: 12)))
        var alarm = RoundAlarm()
        alarm.heard(state(log), session: session, at: noon)
        #expect(alarm.nextDeadline == nil)
        let rang = alarm.tick(at: minutes(13))
        #expect(!rang)
    }

    @Test func twoDevicesStartingAtOnceStartOnce() {
        var log = warmingUp(.traditional(rules: TraditionalRules(), teams: teams))
        log.append(.endWarmup(at: minutes(5)), from: phone)
        log.append(.endWarmup(at: minutes(5.1)), from: watch)
        #expect(clockStart(log) == minutes(5))
    }

    @Test func correctingTheSetupKeepsTheWarmup() {
        var log = warmingUp(.traditional(rules: TraditionalRules(), teams: teams))
        var renamed = teams
        renamed.a.name = "Blues"
        log.append(.configure(.traditional(rules: TraditionalRules(), teams: renamed), at: minutes(1)), from: phone)
        #expect(state(log)?.warmingUpSince == noon)
    }

    @Test func startingTheGameIsNeitherProgressNorUndone() {
        var log = warmingUp(.traditional(rules: TraditionalRules(), teams: teams))
        log.append(.endWarmup(at: minutes(5)), from: phone)
        #expect(!log.hasProgress, "a session called off straight after its warm-up has nothing to keep")
        #expect(log.undoTargets().isEmpty, "undo takes back the score, and there is none")
    }

    @Test func aSessionPickedUpAgainDoesNotWarmUpAgain() throws {
        let log = warmingUp(.traditional(rules: TraditionalRules(), teams: teams))
        let resumed = try #require(state(log)?.restarted(at: minutes(30)))
        #expect(resumed.warmingUpSince == nil)
    }

    @Test func aWarmupSurvivesTheAppBeingClosed() throws {
        for setup in setups {
            let warming = try #require(state(warmingUp(setup)))
            let decoded = try JSONCoding.decoder.decode(SessionState.self, from: JSONCoding.encoder.encode(warming))
            #expect(decoded.warmingUpSince == noon)
        }
    }

    @Test func theLockScreenShowsTheWarmup() throws {
        let warming = try #require(state(warmingUp(.traditional(rules: TraditionalRules(), teams: teams))))
        let score = LiveScore.make(from: warming, display: DisplayPreferences())
        #expect(score.detail == "Warm-up")
        #expect(score.clockStart == noon)
        #expect(score.boards.isEmpty, "no score to show yet")
    }

    @Test func theTVShowsTheWarmup() throws {
        let warming = try #require(state(warmingUp(.tournament(americano))))
        let board = TVBoard.make(from: warming, lastResult: nil, display: DisplayPreferences())
        #expect(board.content == .warmup)
        #expect(board.clockStart == noon)
    }
}

@Suite("Warm-up in presets")
struct WarmupPresetTests {
    @Test func aPresetKeepsItsWarmup() throws {
        let preset = Preset(name: "Thursday", configuration: .traditional(rules: TraditionalRules(), teams: teams), warmsUp: true)
        let decoded = try JSONCoding.decoder.decode(Preset.self, from: JSONCoding.encoder.encode(preset))
        #expect(decoded.warmsUp)
    }

    @Test func aPresetSavedBeforeWarmupsExistedStillReads() throws {
        let preset = Preset(name: "Thursday", configuration: .traditional(rules: TraditionalRules(), teams: teams))
        var fields = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(preset)) as? [String: Any]
        )
        #expect(fields.removeValue(forKey: "warmsUp") != nil, "the key is there to remove")

        let decoded = try JSONCoding.decoder.decode(Preset.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(!decoded.warmsUp)
        #expect(decoded.name == "Thursday")
    }
}
