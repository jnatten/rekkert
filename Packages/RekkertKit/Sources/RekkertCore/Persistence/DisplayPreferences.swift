import Foundation

/// How the phone draws its scoreboard. It travels between the devices so the watch can
/// flip it from the wrist, but only the phone acts on it — the watch is a remote control
/// here, not a second screen to keep in step.
///
/// The value is absolute rather than a "flip it" command: a duplicate delivery of a toggle
/// would cancel itself out, where a duplicate of "mirrored: true" is simply true again.
public struct DisplayPreferences: Codable, Sendable, Hashable {
    public var isMirrored: Bool
    /// Ordered by a counter rather than the clock. Two devices' clocks agree closely but
    /// not exactly, and a flip pressed a moment after one on the other device could
    /// otherwise carry an earlier timestamp and be thrown away.
    public var revision: UInt64
    public var updatedAt: Date

    public init(isMirrored: Bool = false, revision: UInt64 = 0, updatedAt: Date = .distantPast) {
        self.isMirrored = isMirrored
        self.revision = revision
        self.updatedAt = updatedAt
    }

    public var hasBeenSet: Bool { revision > 0 }

    public func setting(mirrored: Bool, at date: Date = Date()) -> DisplayPreferences {
        DisplayPreferences(isMirrored: mirrored, revision: revision + 1, updatedAt: date)
    }

    public func adopting(_ other: DisplayPreferences) -> DisplayPreferences {
        if other.revision != revision { return other.revision > revision ? other : self }
        // Same revision from both at once: settle it the same way on both devices rather
        // than letting them disagree.
        return other.updatedAt > updatedAt ? other : self
    }

    private enum CodingKeys: String, CodingKey { case isMirrored, revision, updatedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isMirrored = try container.decode(Bool.self, forKey: .isMirrored)
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
