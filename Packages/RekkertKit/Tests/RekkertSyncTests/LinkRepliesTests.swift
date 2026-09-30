import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("What the links make of a reply")
struct LinkRepliesTests {
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
