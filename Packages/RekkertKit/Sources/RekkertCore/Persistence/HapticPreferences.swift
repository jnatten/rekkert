import Foundation

/// When the watch buzzes, and what the buzz says.
///
/// It travels between a phone and its own watch so either can set it, and it is the watch
/// alone that acts on it — the phone is propped at the side of the court with nobody holding
/// it, and a buzz there is a buzz nobody feels.
///
/// Unlike the scoreboard's preferences this one is never reset. Which way round the board
/// reads answers a question about today's match; how much you want your wrist tapped does
/// not, and somebody who set it in March should find it still set in June.
public struct HapticPreferences: Codable, Sendable, Hashable {
    public var mode: HapticMode
    /// Skips the points scored on this device. The watch already taps when its own scoreboard
    /// is tapped, so the point you have just pressed is the one you least need telling about.
    public var onlyWhenSomeoneElseScores: Bool
    public var strength: HapticStrength
    /// Ordered by a counter rather than the clock, for the reason the scoreboard's own
    /// preferences are: two devices' clocks agree closely but not exactly, and a press made a
    /// moment after one on the other device could otherwise carry an earlier timestamp and be
    /// thrown away.
    public var revision: UInt64
    public var updatedAt: Date

    public init(
        mode: HapticMode = .off,
        onlyWhenSomeoneElseScores: Bool = true,
        strength: HapticStrength = .medium,
        revision: UInt64 = 0,
        updatedAt: Date = .distantPast
    ) {
        self.mode = mode
        self.onlyWhenSomeoneElseScores = onlyWhenSomeoneElseScores
        self.strength = strength
        self.revision = revision
        self.updatedAt = updatedAt
    }

    /// Whether anybody has said anything about it yet, which is what decides if there is
    /// something worth telling the other device on a reconnect.
    public var hasBeenSet: Bool { revision > 0 }

    /// The whole value, carried as the next revision, so it outranks whatever the other
    /// device is still holding. Absolute rather than "turn it up one": a duplicate delivery
    /// of a step would apply twice, where a duplicate of "medium" is simply medium again.
    public func setting(
        mode: HapticMode? = nil,
        onlyWhenSomeoneElseScores: Bool? = nil,
        strength: HapticStrength? = nil,
        at date: Date = Date()
    ) -> HapticPreferences {
        HapticPreferences(
            mode: mode ?? self.mode,
            onlyWhenSomeoneElseScores: onlyWhenSomeoneElseScores ?? self.onlyWhenSomeoneElseScores,
            strength: strength ?? self.strength,
            revision: revision + 1,
            updatedAt: date
        )
    }

    public func adopting(_ other: HapticPreferences) -> HapticPreferences {
        if other.revision != revision { return other.revision > revision ? other : self }
        // Same revision from both at once: settle it the same way on both devices rather
        // than letting them disagree.
        return other.updatedAt > updatedAt ? other : self
    }

    /// What the wrist should feel for a point, or nothing at all.
    ///
    /// The whole judgement of the feature, kept here rather than on the watch so it can be
    /// tested: a buzz leaves no trace a screenshot can catch.
    public func buzz(forTeam team: TeamSide, mine: TeamSide, scoredHere: Bool) -> Buzz? {
        guard mode != .off else { return nil }
        guard !(onlyWhenSomeoneElseScores && scoredHere) else { return nil }
        let isTheirs = mode == .byTeam && team != mine
        return Buzz(taps: isTheirs ? 2 : 1, strength: strength)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, onlyWhenSomeoneElseScores, strength, revision, updatedAt
    }

    /// Hand-rolled so a file written before any one of these existed still reads. A decoder
    /// that throws does not report anything: the preference is simply dropped and comes back
    /// as the default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(HapticMode.self, forKey: .mode) ?? .off
        onlyWhenSomeoneElseScores = try container
            .decodeIfPresent(Bool.self, forKey: .onlyWhenSomeoneElseScores) ?? true
        strength = try container.decodeIfPresent(HapticStrength.self, forKey: .strength) ?? .medium
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

public enum HapticMode: String, Codable, Sendable, Hashable, CaseIterable {
    case off
    case everyPoint
    case byTeam

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .everyPoint: "Every point"
        case .byTeam: "You and them"
        }
    }

    /// The next one round, for the watch's cycling row — it is a column of buttons rather
    /// than a form, and there are only three to walk past.
    public var next: HapticMode {
        let all = HapticMode.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// What the wrist is being told, in the words somebody would use for it.
    public var explanation: String {
        switch self {
        case .off: "The watch stays still."
        case .everyPoint: "One tap whenever a point goes on."
        case .byTeam: "One tap for your point, two for theirs."
        }
    }
}

/// How hard the tap lands.
///
/// A choice among the watch's own patterns rather than a level, because watchOS has no level
/// to set: its one haptic call takes a named pattern and nothing else, and Core Haptics — the
/// framework that would give an amplitude — is not on the watch at all. Each of these is a
/// single tap, so that one buzz and two stay tellable apart at any of them.
public enum HapticStrength: String, Codable, Sendable, Hashable, CaseIterable {
    case light
    case medium
    case strong

    public var displayName: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }
}

/// A point, as the thing that wants announcing rather than as the event that carried it.
public struct ScoredPoint: Equatable, Sendable {
    public var team: TeamSide
    public var round: Int
    public var court: Int
    /// The match it was played in, taken before the board was redrawn — a point that wins a
    /// match takes the session with it, and the wrist still has to know which one it was.
    public var session: UUID
    /// Which device it was entered on. Every event carries its author for good, so this
    /// survives being relayed through somebody else's phone.
    public var scoredBy: DeviceID

    public init(team: TeamSide, round: Int, court: Int, session: UUID, scoredBy: DeviceID) {
        self.team = team
        self.round = round
        self.court = court
        self.session = session
        self.scoredBy = scoredBy
    }
}

/// A tap, or two taps, at a strength. What the watch is asked to play.
public struct Buzz: Equatable, Sendable {
    public var taps: Int
    public var strength: HapticStrength

    public init(taps: Int, strength: HapticStrength) {
        self.taps = taps
        self.strength = strength
    }
}
