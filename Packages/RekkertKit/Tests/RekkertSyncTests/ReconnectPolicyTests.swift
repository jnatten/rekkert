import Testing
@testable import RekkertSync

/// The decision on its own, with no socket anywhere near it.
@Suite("What a dropped link means")
struct ReconnectPolicyTests {
    @Test func aRefusalBeforeAnythingWorkedMeansTheCodeIsWrong() {
        let loss = ReconnectPolicy.loss(.init(everGotThere: false, hasEverJoined: false))
        #expect(loss == .refused)
    }

    @Test func aLinkThatOnceWorkedIsNeverARefusal() {
        for refusable in [true, false] {
            let loss = ReconnectPolicy.loss(
                .init(everGotThere: true, hasEverJoined: true, refusable: refusable)
            )
            #expect(loss == .keepLooking, "refusable: \(refusable)")
        }
    }

    /// The host's phone locked, the guest redialled the advertisement it could still see, and
    /// that dial failed. Answering "wrong code" to this is what took people out of a match
    /// they were already scoring.
    @Test func aDialThatMissesAfterTheMatchWasFoundIsNotARefusal() {
        let loss = ReconnectPolicy.loss(.init(everGotThere: false, hasEverJoined: true))
        #expect(loss == .keepLooking)
    }

    @Test func aCancelledLinkIsNeverARefusal() {
        for joined in [true, false] {
            let loss = ReconnectPolicy.loss(
                .init(everGotThere: false, hasEverJoined: joined, refusable: false)
            )
            #expect(loss != .refused, "hasEverJoined: \(joined)")
        }
    }

    @Test func aHostNeverReportsARefusal() {
        for gotThere in [true, false] {
            for joined in [true, false] {
                for remain in [true, false] {
                    let loss = ReconnectPolicy.loss(.init(
                        everGotThere: gotThere, hasEverJoined: joined,
                        isHosting: true, linksRemain: remain
                    ))
                    #expect(loss == .carryOn, "\(gotThere) \(joined) \(remain)")
                }
            }
        }
    }

    @Test func losingOneOfSeveralLinksChangesNothing() {
        let loss = ReconnectPolicy.loss(
            .init(everGotThere: false, hasEverJoined: false, linksRemain: true)
        )
        #expect(loss == .carryOn, "the others are still on the match")
    }
}
