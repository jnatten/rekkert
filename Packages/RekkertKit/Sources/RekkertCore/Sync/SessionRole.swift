/// Which end of a shared session a device is on.
///
/// Not derivable from the log: a guest's log *is* the host's log, and the device that first
/// appears in one is true on both of them for their own separate sessions — which is exactly
/// when the two have to decide between them. So it is local, explicit, and persisted.
public enum SessionRole: String, Codable, Sendable, Hashable {
    /// Not shared with anybody else's phone. The pair works out between itself which of the
    /// two holds the newer session, which is what it has always done.
    case solo
    /// Opened this session to other phones. Never taken over by one offered from outside,
    /// and the only end that may finish or discard it.
    case host
    /// Joined somebody else's. Scores, corrects and undoes like anyone, but leaves rather
    /// than ends: the match belongs to the people who started it.
    case guest
}
