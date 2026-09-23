import Foundation

/// What losing a connection means, which is not something a socket can answer on its own.
///
/// A refused handshake and a host who walked off the court are the same observation from in
/// here: a connection that went away without ever having carried anything. The only thing that
/// tells them apart is whether anything ever worked. Before a link has once been ready, a
/// failure is the only evidence there is that the code was wrong; afterwards it is evidence of
/// nothing but a phone going into a pocket, and answering "wrong code" to that sends somebody
/// back to the keyboard in the middle of a match they are already on.
///
/// Kept apart from `LocalNetworkTransport` the way `Framing` and `ReplyFold` are, because that
/// type compiles to an inert stub everywhere the tests can run. The decision is the part that
/// was wrong, so the decision is the part worth being able to reach.
nonisolated enum ReconnectPolicy {
    enum Loss: Equatable {
        /// The code was wrong. Only ever said of a join that never once worked.
        case refused
        /// It worked and then it went. Go back to the browser and keep dialling.
        case keepLooking
        /// Nothing to answer: somebody else is still on, or this end is not the one asking.
        case carryOn
    }

    struct Circumstances: Equatable {
        /// Whether this link reached ready before it went.
        var everGotThere: Bool
        /// Whether any link has, since the code was typed in.
        var hasEverJoined: Bool
        var isHosting: Bool
        /// Whether other links survive this one.
        var linksRemain: Bool
        /// False for a cancelled connection. A wrong pre-shared key surfaces as a failure;
        /// a cancel is somebody hanging up, and usually it is us.
        var refusable: Bool

        init(
            everGotThere: Bool,
            hasEverJoined: Bool,
            isHosting: Bool = false,
            linksRemain: Bool = false,
            refusable: Bool = true
        ) {
            self.everGotThere = everGotThere
            self.hasEverJoined = hasEverJoined
            self.isHosting = isHosting
            self.linksRemain = linksRemain
            self.refusable = refusable
        }
    }

    static func loss(_ circumstances: Circumstances) -> Loss {
        // A host does not dial, so a connection failing on it says nothing about any code. It
        // is a guest giving up, and the answer is to go on advertising for the next one.
        if circumstances.isHosting { return .carryOn }
        // Once a link has carried something, what it can report is that it stopped — never
        // what the code was. This is the line the whole type exists to draw.
        if circumstances.everGotThere { return .keepLooking }
        if !circumstances.refusable { return .carryOn }
        // The match was found once on this code, so a dial that missed is a host that has gone
        // quiet for a moment rather than a code somebody mistyped six digits of.
        if circumstances.hasEverJoined { return .keepLooking }
        if circumstances.linksRemain { return .carryOn }
        return .refused
    }
}
