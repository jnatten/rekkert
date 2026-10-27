import Foundation
import Testing
@testable import RekkertSync

@Suite("Taking turns on the host's radio")
struct HubSchedulerTests {
    @Test func theTurnCarriesOnFromWhereTheLastOneStopped() {
        var turns = HubScheduler<String>()
        for peer in ["a", "b", "c"] { turns.join(peer) }
        #expect(turns.turns() == ["a", "b", "c"])
        turns.served("a")
        #expect(turns.turns() == ["b", "c", "a"])
        turns.served("b")
        turns.served("c")
        #expect(turns.turns() == ["a", "b", "c"])
    }

    @Test func oneSlotAtATimeStillReachesEveryPeerInTurn() {
        var turns = HubScheduler<Int>()
        for peer in 0 ..< 7 { turns.join(peer) }
        var served: [Int] = []
        // Every ready callback frees one slot: whoever is first in turn gets it.
        for _ in 0 ..< 14 {
            let first = turns.turns()[0]
            served.append(first)
            turns.served(first)
        }
        #expect(served == Array(0 ..< 7) + Array(0 ..< 7))
    }

    @Test func aPeerThatLeavesIsSkippedAndTheTurnStaysFair() {
        var turns = HubScheduler<String>()
        for peer in ["a", "b", "c"] { turns.join(peer) }
        turns.served("a")
        turns.leave("b")
        #expect(turns.turns() == ["c", "a"])
        turns.join("b")
        #expect(turns.turns() == ["c", "a", "b"])
    }

    @Test func aHandshakeGoesAheadOfWhatHasNotStarted() {
        let backlog: [(priority: HubScheduler<Int>.Priority, started: Bool)] = [
            (.live, false), (.catchUp, false),
        ]
        #expect(HubScheduler<Int>.position(for: .handshake, in: backlog) == 0)
        #expect(HubScheduler<Int>.position(for: .live, in: backlog) == 1)
        #expect(HubScheduler<Int>.position(for: .catchUp, in: backlog) == 2)
    }

    @Test func nothingGoesAheadOfAFrameAlreadyPartSent() {
        let backlog: [(priority: HubScheduler<Int>.Priority, started: Bool)] = [
            (.catchUp, true), (.catchUp, false),
        ]
        #expect(HubScheduler<Int>.position(for: .handshake, in: backlog) == 1)
        #expect(HubScheduler<Int>.position(for: .live, in: backlog) == 1)
    }

    @Test func aLongFrameIsCatchUpAndAShortOneIsLive() {
        #expect(HubScheduler<Int>.priority(chunks: 1) == .live)
        #expect(HubScheduler<Int>.priority(chunks: HubScheduler<Int>.liveChunks) == .live)
        #expect(HubScheduler<Int>.priority(chunks: HubScheduler<Int>.liveChunks + 1) == .catchUp)
    }
}
