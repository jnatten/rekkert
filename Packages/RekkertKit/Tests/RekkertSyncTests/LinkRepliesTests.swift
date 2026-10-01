import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("What the links make of a reply")
struct LinkRepliesTests {
    /// The answer to a hello is everything the asker was missing. Over Bluetooth it can take
    /// longer to arrive than the asker waits, and was thrown away on arrival.
    @Test func aLateAnswerThatCarriesTheMatchIsHandedOn() throws {
        var log = MatchLog()
        let point = log.append(.point(round: 0, court: 0, team: .a), from: DeviceID())
        #expect(LinkReplies.isWorthHandingOn(late: try Wire.events(sessionID: log.sessionID, events: [point]).encoded()))
        #expect(LinkReplies.isWorthHandingOn(late: try Wire.snapshot(log).encoded()))
    }

    @Test func aLateAcknowledgementIsNot() throws {
        let hello = try Wire.hello(sessionID: UUID(), vector: VersionVector()).encoded()
        #expect(!LinkReplies.isWorthHandingOn(late: hello))
        #expect(!LinkReplies.isWorthHandingOn(late: Data("rubbish".utf8)))
    }

    /// A question nobody waits for any more is dropped unsent. An answer is handed on late all
    /// the same, so it is worth sending long after the asker gave up waiting for it.
    @Test func anAnswerOutlivesTheWaitForItsQuestion() throws {
        #expect(LinkReplies.patience(for: .oneway, replyTimeout: 4) == nil)
        #expect(LinkReplies.patience(for: .request, replyTimeout: 4) == 4)
        let answer = try #require(LinkReplies.patience(for: .reply, replyTimeout: 4))
        #expect(answer > 4)
    }
}

@Suite("Whether a peer is still there")
struct LinkHealthTests {
    @Test func threeUnansweredQuestionsInARowAreAPeerGone() {
        var health = LinkHealth()
        let verdicts = (0 ..< 3).map { _ in health.missed() }
        #expect(verdicts == [false, false, true], "the third in a row")
    }

    @Test func anAnswerInBetweenStartsTheCountAgain() {
        var health = LinkHealth()
        _ = health.missed()
        _ = health.missed()
        health.answered()
        let verdicts = (0 ..< 2).map { _ in health.missed() }
        #expect(verdicts == [false, false])
    }
}

@Suite("One listener, one browser")
struct SlotTests {
    private final class Thing {}

    /// The word that a cancelled listener is gone comes in after its replacement is up. Taken at
    /// its word, it let go of the replacement, which went on running where nothing could stop it.
    @Test func lateWordOfTheOldOneLeavesTheNewOneInPlace() {
        let slot = Slot<Thing>()
        let old = Thing(), new = Thing()
        slot.install(old)
        #expect(slot.install(new) === old, "handed back, to be stopped")

        #expect(!slot.clear(ifStill: old))
        #expect(slot.current === new)
        #expect(slot.clear(ifStill: new))
        #expect(slot.current == nil)
    }
}
