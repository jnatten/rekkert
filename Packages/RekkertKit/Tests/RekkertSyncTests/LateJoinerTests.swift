import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let setup = SessionSetup.traditional(
    rules: TraditionalRules(),
    teams: BySide(a: .home, b: .away)
)

@Suite("Turning up late")
@MainActor
struct LateJoinerTests {
    /// The fan-out keeps the last snapshot so a phone joining mid-match sees the score at
    /// once. What is cached when a match ends is the farewell, and handing that to somebody
    /// who arrives afterwards would file a result for a game they never played.
    @Test func aPhoneArrivingAfterTheMatchEndedIsNotHandedIt() async throws {
        let links = FanOutTransport()
        let host = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let running = Task { await host.run() }
        defer { running.cancel() }

        let (firstHostSide, firstGuestSide) = LoopbackTransport.pair()
        links.attach(firstHostSide, as: .sharedSession)
        let early = MatchStore(device: DeviceID(), transport: firstGuestSide, snapshotInterval: 0)
        let earlyTask = Task { await early.run() }
        defer { earlyTask.cancel() }
        await quietPeriod()

        host.configure(setup)
        host.tap(team: .a)
        await eventually { inStep(early, host) }
        #expect(early.state != nil, "the one who was here got the match")

        host.finish()
        await eventually { host.state == nil && early.state == nil }
        #expect(host.state == nil, "and it is over")

        // Somebody wanders up afterwards.
        let (lateHostSide, lateGuestSide) = LoopbackTransport.pair()
        links.attach(lateHostSide, as: .sharedSession)
        let latecomer = MatchStore(device: DeviceID(), transport: lateGuestSide, snapshotInterval: 0)
        let lateTask = Task { await latecomer.run() }
        defer { lateTask.cancel() }
        await quietPeriod()

        #expect(latecomer.state == nil, "handed nothing, because there is nothing to play")
        #expect(latecomer.lastResult == nil, "and no result for a match they never played")
    }

    @Test func aPhoneArrivingMidMatchIsHandedTheScore() async throws {
        let links = FanOutTransport()
        let host = MatchStore(device: DeviceID(), transport: links, snapshotInterval: 0)
        let running = Task { await host.run() }
        defer { running.cancel() }
        await quietPeriod()

        host.configure(setup)
        host.tap(team: .b)
        await quietPeriod()

        let (hostSide, guestSide) = LoopbackTransport.pair()
        links.attach(hostSide, as: .sharedSession)
        let latecomer = MatchStore(device: DeviceID(), transport: guestSide, snapshotInterval: 0)
        let joining = Task { await latecomer.run() }
        defer { joining.cancel() }
        await eventually { inStep(latecomer, host) }

        guard case .traditional(let session)? = latecomer.state else {
            Issue.record("the latecomer should have been handed the match")
            return
        }
        #expect(session.score.points == BySide(a: 0, b: 1), "without waiting for a round trip")
    }
}
