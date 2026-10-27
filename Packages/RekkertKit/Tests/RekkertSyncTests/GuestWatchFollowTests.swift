import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let counting = SessionSetup.pointCount(
    rules: PointCountRules(target: 64),
    teams: BySide(a: .home, b: .away)
)

/// A guest's phone, its watch with a match of the watch's own, and the host the phone joins.
@MainActor
private final class GuestWithWatch {
    let phone: MatchStore
    let watch: MatchStore
    let host: MatchStore
    let phoneToWatch: LoopbackTransport
    let watchToPhone: LoopbackTransport
    let history: SessionStore
    private var tasks: [Task<Void, Never>] = []

    init() {
        let (phoneToWatch, watchToPhone) = LoopbackTransport.pair()
        let (hostToPhone, phoneToHost) = LoopbackTransport.pair()
        self.phoneToWatch = phoneToWatch
        self.watchToPhone = watchToPhone
        history = SessionStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("follow-\(UUID().uuidString)", isDirectory: true))

        let phoneFan = FanOutTransport()
        phoneFan.attach(phoneToWatch, as: .pairedDevice)
        phoneFan.attach(phoneToHost, as: .sharedSession)
        phone = MatchStore(device: DeviceID(), transport: phoneFan, store: history, snapshotInterval: 0)
        // What `AppModel` does with a request from the wrist.
        phone.onSharing = { [phone] signal in if case .followPhone = signal { phone.offerToThePair() } }

        let watchFan = FanOutTransport()
        watchFan.attach(watchToPhone, as: .pairedDevice)
        watch = MatchStore(device: DeviceID(), transport: watchFan, snapshotInterval: 0, keepsHistory: false)

        let hostFan = FanOutTransport()
        hostFan.attach(hostToPhone, as: .sharedSession)
        var hosted = MatchLog(createdAt: .now.addingTimeInterval(-3 * 3600))
        hosted.append(.configure(counting), from: DeviceID())
        host = MatchStore(
            device: DeviceID(), transport: hostFan, session: ActiveSession(log: hosted, role: .host), snapshotInterval: 0
        )
        tasks = [phone, watch, host].map { store in Task { await store.run() } }
    }

    func stop() { tasks.forEach { $0.cancel() } }

    /// The watch on a match of its own, and the phone a guest on the host's without the watch
    /// having heard a word of it: nothing live either way, and nothing either queues let through.
    func joinBehindTheWatchsBack() async {
        for end in [phoneToWatch, watchToPhone] {
            end.setSwallowing(true)
            end.setHoldingQueue(true)
        }
        // A question the watch asked a moment ago, answered after the phone has moved on, would
        // carry the new match across.
        await waitOutAnswers(phoneToWatch, watchToPhone)
        phone.beginJoining()
        await eventually { self.phone.role == .guest }
        await quietPeriod()
        phoneToWatch.setSwallowing(false)
        watchToPhone.setSwallowing(false)
    }
}

@Suite("A guest's watch follows its phone", .serialized)
@MainActor
struct GuestWatchFollowTests {
    /// RW-2: the host's match was made hours before the watch's warm-up, and the clocks alone
    /// would keep the warm-up. The phone saying it is a guest settles it, with no point scored.
    @Test func aWatchWarmingUpTakesItsGuestPhonesMatchAtOnce() async {
        let pair = GuestWithWatch()
        defer { pair.stop() }
        pair.watch.configure(counting, warmup: true)
        await eventually { pair.phone.log.sessionID == pair.watch.log.sessionID }
        await pair.joinBehindTheWatchsBack()
        #expect(pair.watch.log.sessionID != pair.host.log.sessionID)

        // The phone's snapshot, as the application context carries it, and nothing else.
        pair.phoneToWatch.publishSnapshot(try! Wire.snapshot(pair.phone.log, role: pair.phone.role).encoded())
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID }
        #expect(pair.watch.log.sessionID == pair.host.log.sessionID)
    }

    @Test func thePhonesSnapshotSaysWhatItIsOn() async {
        let pair = GuestWithWatch()
        defer { pair.stop() }
        pair.phone.beginJoining()
        await eventually { pair.phone.role == .guest }
        await eventually { pair.watch.pairsSharedMatch == pair.host.log.sessionID }
        #expect(pair.watch.pairsSharedMatch == pair.host.log.sessionID)
    }

    /// FR-015: what the watch had on goes to the phone's History, the only one it has.
    @Test func theWatchsOwnMatchIsKeptInThePhonesHistory() async {
        let pair = GuestWithWatch()
        defer { pair.stop() }
        pair.watch.configure(counting)
        pair.watch.tap(team: .a)
        pair.watch.tap(team: .b)
        let own = pair.watch.log.sessionID
        await eventually { pair.phone.log.sessionID == own }

        pair.phone.beginJoining()
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID }
        await eventually { pair.history.historyRecord(own) != nil }
        #expect(pair.history.historyRecord(own) != nil)
    }

    /// The role on its own, with nothing else from the phone getting through, is enough for the
    /// watch to ask, and be handed the match.
    @Test func aRoleArrivingOnItsOwnBringsTheWatchRound() async {
        let pair = GuestWithWatch()
        defer { pair.stop() }
        pair.watch.configure(counting)
        pair.watch.tap(team: .a)
        await eventually { pair.phone.log.sessionID == pair.watch.log.sessionID }
        await pair.joinBehindTheWatchsBack()
        #expect(pair.watch.log.sessionID != pair.host.log.sessionID, "nothing has told it yet")

        // What the phone queued on joining: its role, and who may do what.
        pair.phoneToWatch.setHoldingQueue(false)
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID }
        #expect(pair.watch.log.sessionID == pair.host.log.sessionID)
    }

    /// "Get on it": the phone offers its match again, saying it is a guest on it.
    @Test func followingThePhoneHandsTheWatchItsMatch() async {
        let pair = GuestWithWatch()
        defer { pair.stop() }
        pair.watch.configure(counting)
        pair.watch.tap(team: .a)
        await eventually { pair.phone.log.sessionID == pair.watch.log.sessionID }
        await pair.joinBehindTheWatchsBack()
        #expect(pair.watch.log.sessionID != pair.host.log.sessionID)

        #expect(await pair.watch.followThePhone())
        await eventually { pair.watch.log.sessionID == pair.host.log.sessionID }
        #expect(pair.watch.log.sessionID == pair.host.log.sessionID)
    }

    /// FR-030: asked first exactly while its phone is a guest.
    @Test func startingItsOwnMatchTakesThePhoneOffOnlyWhileThePhoneIsAGuest() async {
        let pair = GuestWithWatch()
        defer { pair.stop() }
        #expect(!pair.watch.startingOwnMatchTakesPhoneOff)

        pair.phone.beginJoining()
        await eventually { pair.watch.startingOwnMatchTakesPhoneOff }
        #expect(pair.watch.startingOwnMatchTakesPhoneOff)
        #expect(!pair.phone.startingOwnMatchTakesPhoneOff, "a phone has no phone to take off")

        pair.phone.leaveSharedSession()
        await eventually { !pair.watch.startingOwnMatchTakesPhoneOff }
        #expect(!pair.watch.startingOwnMatchTakesPhoneOff)
    }
}
