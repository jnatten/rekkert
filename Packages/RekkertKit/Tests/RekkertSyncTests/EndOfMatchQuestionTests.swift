import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let americano = SessionSetup.tournament(Tournament(
    name: "Thursday", format: .americano,
    players: ["Ada", "Bob", "Cy", "Di"].map { Player(name: $0) },
    config: TournamentConfig(pointRules: PointCountRules(target: 16), courtCount: 1)
))

@Suite("Asked at the end of a shared match", .serialized)
@MainActor
struct EndOfMatchQuestionTests {
    private func sharedCourt(
        guests: Int = 2, withWatches: Bool = true,
        setup: SessionSetup = .traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))
    ) async -> CourtHarness {
        let court = CourtHarness(guests: guests, withWatches: withWatches)
        court.startMatch(setup)
        court.share()
        court.joinAll()
        court.score(on: court.host.phone)
        await court.until(within: .seconds(60)) { court.allInStep() }
        #expect(court.allInStep())
        return court
    }

    private func history(of device: CourtHarness.Device, _ session: UUID) -> HistoryRecord? {
        SessionStore(directory: device.directory).historyRecord(session)
    }

    private func recorded(_ kind: LinkEvent, on device: CourtHarness.Device) -> Bool {
        device.recorder.read().entries.contains { $0.kind == kind }
    }

    // MARK: - The host

    @Test func hostIsAskedWithTheGuestCount() async {
        let court = await sharedCourt()
        let watch = court.host.watch!
        #expect(await court.until(within: .seconds(20)) { watch.standIn?.hosting?.participants.count == 2 })
        let ended = court.host.phone.store.log.sessionID
        court.finish(on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask?.session == ended)
        #expect(court.betweenMatches(of: court.host.phone).ask?.side == .host(guestsOn: 2))
        #expect(await court.until(within: .seconds(10)) {
            court.betweenMatches(of: watch).ask?.side == .host(guestsOn: 2)
        })
        #expect(recorded(.endOfMatchAsked, on: court.host.phone))
    }

    @Test func aHostWithNobodyOnIsAskedToo() async {
        let court = CourtHarness(guests: 0, withWatches: false)
        court.startMatch()
        court.share()
        court.finish(on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask?.side == .host(guestsOn: 0))
    }

    @Test func callingOffAsksToo() async {
        let court = await sharedCourt(guests: 1, withWatches: false)
        court.discard(on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask?.side == .host(guestsOn: 1))
    }

    @Test func aMatchThatWasNeverSharedAsksNothing() async {
        let court = CourtHarness(guests: 0, withWatches: true)
        court.startMatch()
        court.score(on: court.host.phone)
        court.finish(on: court.host.phone)
        await court.run(for: .seconds(2))
        #expect(court.betweenMatches(of: court.host.phone).ask == nil)
        #expect(court.betweenMatches(of: court.host.watch!).ask == nil)
    }

    @Test func aTournamentRoundDoesNotAsk() async {
        let court = await sharedCourt(guests: 1, withWatches: false, setup: americano)
        court.host.phone.store.nextRound()
        court.host.phone.store.nextRound()
        #expect(court.host.phone.store.state != nil)
        #expect(court.betweenMatches(of: court.host.phone).ask == nil)
        court.finish(on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask != nil)
    }

    @Test func stopFromTheQuestionTellsEveryGuest() async {
        let court = await sharedCourt(withWatches: false)
        let ended = court.host.phone.store.log.sessionID
        court.finish(on: court.host.phone)
        #expect(await court.until(within: .seconds(30)) { court.guests.allSatisfy { $0.phone.store.state == nil } })
        court.answer(.stopSharing, on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask == nil)
        #expect(!court.host.phone.sharing.isSharing)
        #expect(recorded(.endOfMatchAnswered(.stopSharing), on: court.host.phone))
        #expect(await court.until(within: .seconds(10)) {
            court.guests.allSatisfy { $0.phone.sharing.hostStoppedSharing }
        })
        for guest in court.guests {
            #expect(history(of: guest.phone, ended) != nil, "the finished match stays in History")
            #expect(guest.phone.keeper.read(now: court.wallClock) == nil, "the code is forgotten")
            #expect(guest.phone.store.role == .solo)
        }
    }

    @Test func keepChangesNothing() async {
        let court = await sharedCourt(withWatches: false)
        let ended = court.host.phone.store.log.sessionID
        await court.until(within: .seconds(20)) { court.host.phone.store.participantStates().count == 2 }
        let access = court.host.phone.store.accessTable
        court.finish(on: court.host.phone)
        court.answer(.keepSharing, on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask == nil)
        #expect(court.host.phone.sharing.code == court.code)
        #expect(court.host.phone.store.participantStates().count == 2)
        #expect(court.host.phone.store.accessTable?.standard == access?.standard)
        #expect(court.host.phone.store.accessTable?.keptSharingAfter == ended)
        #expect(court.guests.allSatisfy { $0.phone.store.role == .guest })
    }

    @Test func anAnswerOnTheWatchClosesThePhone() async {
        let court = await sharedCourt(guests: 1)
        let ended = court.host.phone.store.log.sessionID
        court.finish(on: court.host.phone)
        let watch = court.host.watch!
        #expect(await court.until(within: .seconds(10)) { court.betweenMatches(of: watch).ask != nil })
        court.answer(.keepSharing, on: watch)
        #expect(court.betweenMatches(of: watch).ask == nil)
        #expect(await court.until(within: .seconds(10)) { court.betweenMatches(of: court.host.phone).ask == nil })
        #expect(court.host.phone.store.accessTable?.keptSharingAfter == ended, "the watch's Keep reaches the guests")
    }

    @Test func stopOnTheWatchStopsSharing() async {
        let court = await sharedCourt(guests: 1)
        court.finish(on: court.host.phone)
        let watch = court.host.watch!
        #expect(await court.until(within: .seconds(10)) { court.betweenMatches(of: watch).ask != nil })
        court.answer(.stopSharing, on: watch)
        #expect(await court.until(within: .seconds(10)) { !court.host.phone.sharing.isSharing })
        #expect(await court.until(within: .seconds(10)) {
            court.betweenMatches(of: watch).ask == nil && court.betweenMatches(of: court.host.phone).ask == nil
        })
    }

    @Test func stopOnTheWatchWithThePhoneOutOfReachChangesNothing() async {
        let court = await sharedCourt(guests: 1)
        court.finish(on: court.host.phone)
        let watch = court.host.watch!
        #expect(await court.until(within: .seconds(10)) { court.betweenMatches(of: watch).ask != nil })
        court.separate(court.host)
        court.answer(.stopSharing, on: watch)
        #expect(await court.until(within: .seconds(10)) { watch.standIn?.hostingTrouble == .cannotReachPhone })
        #expect(court.betweenMatches(of: watch).ask != nil)
        #expect(court.host.phone.sharing.isSharing)
    }

    @Test func aRelaunchDoesNotAskAgain() async {
        let court = await sharedCourt(guests: 1, withWatches: false)
        court.finish(on: court.host.phone)
        court.answer(.keepSharing, on: court.host.phone)
        court.endApp(court.host.phone)
        court.relaunch(court.host.phone)
        await court.run(for: .seconds(5))
        #expect(court.betweenMatches(of: court.host.phone).ask == nil)
    }

    @Test func startingTheNextMatchCountsAsKeep() async {
        let court = await sharedCourt(guests: 1, withWatches: false)
        court.finish(on: court.host.phone)
        #expect(court.betweenMatches(of: court.host.phone).ask != nil)
        court.startMatch()
        #expect(court.betweenMatches(of: court.host.phone).ask == nil)
        #expect(court.host.phone.sharing.code == court.code)
        #expect(await court.until(within: .seconds(30)) { court.allInStep() })
    }
}
