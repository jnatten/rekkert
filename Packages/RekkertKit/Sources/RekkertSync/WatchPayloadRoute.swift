import Foundation

/// Which WatchConnectivity channel a payload fits on.
///
/// `sendMessage`, its reply and `transferUserInfo` refuse anything over 64 KB, and the application
/// context anything over 256 KB — and a whole match log is past the first of those by the middle
/// of an evening's americano. Refused, it is not an error anybody sees: the live send comes back
/// with nothing, the queued one is dropped, and the watch never hears of the match it was sent.
/// What will not fit goes as a file, which has no such limit and is delivered like the queue.
nonisolated enum WatchPayloadRoute: Equatable {
    case inline
    case file

    /// A little under each limit, for the dictionary the payload travels in.
    static let messageLimit = 60_000
    static let contextLimit = 250_000

    static func forMessage(_ size: Int) -> Self { size <= messageLimit ? .inline : .file }
    static func forContext(_ size: Int) -> Self { size <= contextLimit ? .inline : .file }
}
