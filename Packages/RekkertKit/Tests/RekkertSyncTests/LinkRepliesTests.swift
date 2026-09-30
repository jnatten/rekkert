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

    /// The guest gives the host ten seconds to prove itself, and the proof went out behind the
    /// whole match: with a long log over a slow link, the right host was written off.
    @Test func theHostsProofGoesAheadOfTheMatch() throws {
        let probe = Frame(kind: .oneway, payload: Data())
        let frames = LinkReplies.opening(snapshot: Data(repeating: 1, count: 100_000), probe: probe)
        #expect(frames.first == probe)
        #expect(frames.count == 2)
        #expect(LinkReplies.opening(snapshot: nil, probe: probe) == [probe])
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
