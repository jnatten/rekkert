import Foundation
import RekkertCore
import Testing

@Suite("Between matches")
struct BetweenMatchesTests {
    private let evening = Date(timeIntervalSince1970: 1_800_000_000)
    private let ended = UUID()
    private let next = UUID()

    private func at(_ minutes: Double) -> Date { evening.addingTimeInterval(minutes * 60) }

    @Test func aPhoneIsAskedByItsOwnRole() {
        #expect(BetweenMatches.side(role: .host, pairedRole: .solo, isWatch: false) == .host)
        #expect(BetweenMatches.side(role: .guest, pairedRole: .solo, isWatch: false) == .guest)
        #expect(BetweenMatches.side(role: .solo, pairedRole: .guest, isWatch: false) == nil)
    }

    @Test func aWatchIsAskedByItsPhonesRole() {
        #expect(BetweenMatches.side(role: .solo, pairedRole: .host, isWatch: true) == .host)
        #expect(BetweenMatches.side(role: .solo, pairedRole: .guest, isWatch: true) == .guest)
        #expect(BetweenMatches.side(role: .solo, pairedRole: .solo, isWatch: true) == nil)
        // On a match by itself, with its phone out of the picture.
        #expect(BetweenMatches.side(role: .guest, pairedRole: .solo, isWatch: true) == .guest)
    }

    @Test func theEndOfASharedMatchAsksOnce() {
        var between = BetweenMatches()
        let result1 = between.matchEnded(session: ended, side: .host(guestsOn: 2), now: at(0))
        #expect(result1)
        #expect(between.ask == EndOfMatchAsk(session: ended, side: .host(guestsOn: 2), askedAt: at(0)))
        let result2 = between.answered(BetweenMatchesAnswer(session: ended, choice: .keepSharing))
        #expect(result2)
        #expect(between.ask == nil)
        let result3 = between.matchEnded(session: ended, side: .host(guestsOn: 2), now: at(1))
        #expect(!result3)
        #expect(between.ask == nil)
    }

    @Test func aMatchThatWasNotSharedAsksNothing() {
        var between = BetweenMatches()
        let result4 = between.matchEnded(session: ended, side: nil, now: at(0))
        #expect(!result4)
        #expect(between.ask == nil)
    }

    @Test func leaveWinsWhicheverOrderTheAnswersArrive() {
        for order: [BetweenMatchesAnswer.Choice] in [[.stay, .leave], [.leave, .stay]] {
            var between = BetweenMatches()
            between.matchEnded(session: ended, side: .guest(hostName: "Ada", hostKeepsSharing: false), now: at(0))
            for choice in order { between.answered(BetweenMatchesAnswer(session: ended, choice: choice)) }
            #expect(between.ask == nil)
        }
    }

    @Test func anAnswerForAnotherSessionClosesNothing() {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .host(guestsOn: 1), now: at(0))
        let result5 = between.answered(BetweenMatchesAnswer(session: next, choice: .keepSharing))
        #expect(!result5)
        #expect(between.ask != nil)
    }

    @Test func theIdleClockRunsFromTheEndOfAMatch() {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .host(guestsOn: 1), now: at(0))
        #expect(between.idleSince == at(0))
        #expect(!between.isIdleExpired(now: at(29.99), matchOn: false))
        #expect(between.isIdleExpired(now: at(30), matchOn: false))
        #expect(!between.isIdleExpired(now: at(45), matchOn: true))
    }

    @Test func aMatchPausesTheIdleClock() {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .host(guestsOn: 1), now: at(0))
        between.matchBegan()
        #expect(between.idleSince == nil)
        #expect(!between.isIdleExpired(now: at(90), matchOn: false))
    }

    @Test func stayingAndKeepingDoNotResetTheIdleClock() {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .guest(hostName: nil, hostKeepsSharing: false), now: at(0))
        between.answered(BetweenMatchesAnswer(session: ended, choice: .stay))
        #expect(between.idleSince == at(0))
        var host = BetweenMatches()
        host.matchEnded(session: ended, side: .host(guestsOn: 1), now: at(0))
        host.answered(BetweenMatchesAnswer(session: ended, choice: .keepSharing))
        #expect(host.idleSince == at(0))
    }

    @Test func sharingAgainKeepsAClockAlreadyRunning() {
        var between = BetweenMatches()
        between.sharingStarted(now: at(0))
        between.sharingStarted(now: at(10))
        #expect(between.idleSince == at(0))
        between.sharingEnded()
        between.sharingStarted(now: at(20))
        #expect(between.idleSince == at(20))
    }

    @Test func theHostsNextMatchClosesAnOpenQuestionAndOpensANotice() {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .guest(hostName: "Ada", hostKeepsSharing: false), now: at(0))
        let notice = NewMatchNotice(session: next, hostName: "Ada", arrivedAt: at(5))
        let result6 = between.hostsNextMatchArrived(notice)
        #expect(result6)
        #expect(between.ask == nil)
        #expect(between.newMatch == notice)
        #expect(between.idleSince == nil)
        #expect(between.blocksScoring)
        let result7 = between.matchEnded(session: ended, side: .guest(hostName: "Ada", hostKeepsSharing: false), now: at(6))
        #expect(!result7)
    }

    @Test func aNoticeAlreadyAnsweredOnTheOtherHalfDoesNotOpen() {
        var between = BetweenMatches()
        between.answered(BetweenMatchesAnswer(session: next, choice: .ok))
        let result8 = between.hostsNextMatchArrived(NewMatchNotice(session: next, hostName: nil, arrivedAt: at(1)))
        #expect(!result8)
        #expect(between.newMatch == nil)
        #expect(!between.blocksScoring)
    }

    @Test func okAndLeaveCloseTheNotice() {
        for choice: BetweenMatchesAnswer.Choice in [.ok, .leave] {
            var between = BetweenMatches()
            between.hostsNextMatchArrived(NewMatchNotice(session: next, hostName: nil, arrivedAt: at(0)))
            let result9 = between.answered(BetweenMatchesAnswer(session: next, choice: choice))
            #expect(result9)
            #expect(between.newMatch == nil)
            #expect(!between.blocksScoring)
        }
    }

    @Test func aStopEndsEverything() {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .guest(hostName: nil, hostKeepsSharing: true), now: at(0))
        between.sharingEnded()
        #expect(between.ask == nil)
        #expect(between.newMatch == nil)
        #expect(between.idleSince == nil)
    }

    @Test func aNotificationIsOnlyWantedWithNeitherInFront() {
        #expect(BetweenMatches.wantsNotification(appIsActive: false, watchReachable: false))
        #expect(!BetweenMatches.wantsNotification(appIsActive: true, watchReachable: false))
        #expect(!BetweenMatches.wantsNotification(appIsActive: false, watchReachable: true))
        #expect(!BetweenMatches.wantsNotification(appIsActive: true, watchReachable: true))
    }

    @Test func itSurvivesBeingWrittenDown() throws {
        var between = BetweenMatches()
        between.matchEnded(session: ended, side: .guest(hostName: "Ada", hostKeepsSharing: true), now: at(0))
        between.hostsNextMatchArrived(NewMatchNotice(session: next, hostName: "Ada", arrivedAt: at(3)))
        between.matchEnded(session: next, side: .host(guestsOn: 3), now: at(40))
        let data = try JSONCoding.encoder.encode(between)
        #expect(try JSONCoding.decoder.decode(BetweenMatches.self, from: data) == between)
        let answer = BetweenMatchesAnswer(session: next, choice: .leave)
        #expect(try JSONCoding.decoder.decode(BetweenMatchesAnswer.self, from: JSONCoding.encoder.encode(answer)) == answer)
    }
}
