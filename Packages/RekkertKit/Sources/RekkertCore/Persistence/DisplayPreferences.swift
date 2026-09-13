import Foundation

/// How the phone draws its scoreboard. It travels between the devices so the watch can
/// flip it from the wrist, but only the phone acts on it — the watch is a remote control
/// here, not a second screen to keep in step.
///
/// The value is absolute rather than a "flip it" command: a duplicate delivery of a toggle
/// would cancel itself out, where a duplicate of "mirrored: true" is simply true again.
public struct DisplayPreferences: Codable, Sendable, Hashable {
    public var isMirrored: Bool
    public var updatedAt: Date

    public init(isMirrored: Bool = false, updatedAt: Date = .distantPast) {
        self.isMirrored = isMirrored
        self.updatedAt = updatedAt
    }

    public func setting(mirrored: Bool, at date: Date = Date()) -> DisplayPreferences {
        DisplayPreferences(isMirrored: mirrored, updatedAt: date)
    }

    public func adopting(_ other: DisplayPreferences) -> DisplayPreferences {
        other.updatedAt > updatedAt ? other : self
    }
}
