import Foundation

/// How the scoreboard is drawn. It travels between the devices so either can set it.
///
/// Mirroring is acted on by the phone alone — it says where you are standing relative to
/// that screen, so flipping it must not move the watch. Which side is blue is not about
/// standing anywhere, so both devices follow it.
///
/// The value is absolute rather than a "flip it" command: a duplicate delivery of a toggle
/// would cancel itself out, where a duplicate of "mirrored: true" is simply true again.
public struct DisplayPreferences: Codable, Sendable, Hashable {
    public var isMirrored: Bool
    /// A tournament draw decides which side you are on from one round to the next, so
    /// staying the blue one takes a preference of its own.
    public var areColorsSwapped: Bool
    /// Ordered by a counter rather than the clock. Two devices' clocks agree closely but
    /// not exactly, and a flip pressed a moment after one on the other device could
    /// otherwise carry an earlier timestamp and be thrown away.
    public var revision: UInt64
    public var updatedAt: Date

    public init(
        isMirrored: Bool = false,
        areColorsSwapped: Bool = false,
        revision: UInt64 = 0,
        updatedAt: Date = .distantPast
    ) {
        self.isMirrored = isMirrored
        self.areColorsSwapped = areColorsSwapped
        self.revision = revision
        self.updatedAt = updatedAt
    }

    public var hasBeenSet: Bool { revision > 0 }

    public func setting(mirrored: Bool, at date: Date = Date()) -> DisplayPreferences {
        DisplayPreferences(
            isMirrored: mirrored,
            areColorsSwapped: areColorsSwapped,
            revision: revision + 1,
            updatedAt: date
        )
    }

    public func setting(colorsSwapped: Bool, at date: Date = Date()) -> DisplayPreferences {
        DisplayPreferences(
            isMirrored: isMirrored,
            areColorsSwapped: colorsSwapped,
            revision: revision + 1,
            updatedAt: date
        )
    }

    public func adopting(_ other: DisplayPreferences) -> DisplayPreferences {
        if other.revision != revision { return other.revision > revision ? other : self }
        // Same revision from both at once: settle it the same way on both devices rather
        // than letting them disagree.
        return other.updatedAt > updatedAt ? other : self
    }

    private enum CodingKeys: String, CodingKey { case isMirrored, areColorsSwapped, revision, updatedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isMirrored = try container.decode(Bool.self, forKey: .isMirrored)
        areColorsSwapped = try container.decodeIfPresent(Bool.self, forKey: .areColorsSwapped) ?? false
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
