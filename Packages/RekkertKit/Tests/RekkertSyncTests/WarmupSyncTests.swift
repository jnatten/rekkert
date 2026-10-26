import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let match = SessionSetup.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))

private func clock(_ store: MatchStore) -> Date? {
    store.state.flatMap { ScoreboardSnapshot.make(from: $0) }?.clockStart
}

@Suite("Warm-up across devices", .serialized)
@MainActor
struct WarmupSyncTests {
    private func pair() -> (MatchStore, MatchStore) {
        let (one, two) = LoopbackTransport.pair()
        let phone = MatchStore(device: DeviceID(), transport: one, snapshotInterval: 0)
        let watch = MatchStore(device: DeviceID(), transport: two, snapshotInterval: 0, keepsHistory: false)
        return (phone, watch)
    }

    @Test func theWatchWarmsUpWithThePhoneAndStartsTheGameForBoth() async throws {
        let (phone, watch) = pair()
        let tasks = [Task { await phone.run() }, Task { await watch.run() }]
        defer { tasks.forEach { $0.cancel() } }

        phone.configure(match, warmup: true)
        let since = try #require(phone.state?.warmingUpSince)
        await eventually { watch.state?.warmingUpSince != nil }
        #expect(watch.state?.warmingUpSince == since)

        watch.endWarmup()
        await eventually { phone.state?.warmingUpSince == nil }
        #expect(phone.state?.warmingUpSince == nil)
        let started = try #require(clock(phone))
        #expect(started >= since)
        await eventually { clock(watch) == started }
        #expect(clock(watch) == started, "one clock, from the moment the game started")
    }

    @Test func aPresetStartsWithItsWarmup() {
        let (phone, _) = pair()
        phone.start(Preset(name: "Thursday", configuration: .traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)), warmsUp: true))
        #expect(phone.state?.warmingUpSince != nil)

        phone.start(Preset(name: "Friday", configuration: .traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))))
        #expect(phone.state?.warmingUpSince == nil)
    }

    @Test func endingAWarmupThatIsNotThereRecordsNothing() {
        let (phone, _) = pair()
        phone.configure(match)
        let before = phone.log.events.count
        phone.endWarmup()
        #expect(phone.log.events.count == before)
    }
}
