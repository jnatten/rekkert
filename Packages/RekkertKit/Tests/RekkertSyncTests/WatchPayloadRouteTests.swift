import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("What fits between a phone and its watch")
struct WatchPayloadRouteTests {
    /// Four courts, ten rounds, every point tapped: the evening's americano. Its whole log is more
    /// than twice what WatchConnectivity will carry as a message or on its queue, and was refused
    /// there without a word — the watch never heard the match it was handed.
    @Test func anEveningsAmericanoGoesAsAFile() throws {
        let host = DeviceID(), guest = DeviceID()
        var log = MatchLog()
        log.append(.configure(.tournament(Tournament(
            name: "Thursday", format: .americano,
            players: (0 ..< 16).map { Player(name: "Player \($0)") },
            config: TournamentConfig(pointRules: PointCountRules(target: 24), courtCount: 4)
        ))), from: host)
        for round in 0 ..< 10 {
            log.append(.nextRound(after: round - 1, at: Date()), from: host)
            for court in 0 ..< 4 {
                for point in 0 ..< 24 {
                    log.append(
                        .point(round: round, court: court, team: point % 3 == 0 ? .b : .a),
                        from: point.isMultiple(of: 2) ? host : guest, at: MatchEvent.stamp()
                    )
                }
            }
        }
        let snapshot = try Wire.snapshot(log).encoded()

        #expect(WatchPayloadRoute.forMessage(snapshot.count) == .file)
        #expect(WatchPayloadRoute.forContext(snapshot.count) == .inline, "while the context still takes it")
    }

    @Test func aPointGoesAsAMessage() throws {
        var log = MatchLog()
        let point = log.append(.point(round: 0, court: 0, team: .a), from: DeviceID())
        let push = try Wire.events(sessionID: log.sessionID, events: [point]).encoded()
        #expect(WatchPayloadRoute.forMessage(push.count) == .inline)
    }

    @Test func theLimitsSitUnderWatchConnectivitysOwn() {
        #expect(WatchPayloadRoute.forMessage(65_536) == .file)
        #expect(WatchPayloadRoute.forContext(262_144) == .file)
    }
}
