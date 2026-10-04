import Foundation

public enum MatchMoment: Equatable, Sendable {
    /// Started, resumed or joined on this device. Its pair only hears `inPlay` for it.
    case began(UUID)
    /// On the board here from any source, including the pair, a take-back or a replacement.
    case inPlay(UUID)
    /// Won, finished, called off, ended by its host, or stepped off.
    case ended(UUID)
}
