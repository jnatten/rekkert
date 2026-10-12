public enum LadderPartners: String, Codable, Sendable, Hashable, CaseIterable {
    /// Pairs stay together all evening, taken from the list two at a time.
    case fixed
    /// The two pairs that meet on a court are split up, so last round's partners face each other.
    case split

    public var displayName: String {
        switch self {
        case .fixed: "Fixed pairs"
        case .split: "Split after each round"
        }
    }
}

public enum LadderStart: String, Codable, Sendable, Hashable, CaseIterable {
    case random
    case asListed

    public var displayName: String {
        switch self {
        case .random: "Random"
        case .asListed: "As listed"
        }
    }
}

/// How a winner-court ladder is played: courts in a row, winners up and losers down.
public struct LadderRules: Codable, Sendable, Hashable {
    /// The sport and the 40–40 rule, and in a match round the sets and games too.
    public var rules: TraditionalRules
    /// How long a timed round runs. `nil` plays a match on every court instead.
    public var roundMinutes: Int?
    public var partners: LadderPartners
    public var start: LadderStart

    public static let defaultRoundMinutes = 12

    public init(
        rules: TraditionalRules = TraditionalRules(setsToWin: 1, deuceRule: .goldenPoint),
        roundMinutes: Int? = LadderRules.defaultRoundMinutes,
        partners: LadderPartners = .fixed,
        start: LadderStart = .random
    ) {
        self.rules = rules
        self.roundMinutes = roundMinutes
        self.partners = partners
        self.start = start
    }

    public var isTimed: Bool { roundMinutes != nil }

    public var scoring: TraditionalRules {
        isTimed ? .endless(deuceRule: rules.deuceRule, sport: rules.sport) : rules
    }

    private enum CodingKeys: String, CodingKey { case rules, roundMinutes, partners, start }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decodeIfPresent(TraditionalRules.self, forKey: .rules)
            ?? TraditionalRules(setsToWin: 1, deuceRule: .goldenPoint)
        roundMinutes = try container.decodeIfPresent(Int.self, forKey: .roundMinutes)
        partners = (try? container.decodeIfPresent(LadderPartners.self, forKey: .partners)) ?? .fixed
        start = (try? container.decodeIfPresent(LadderStart.self, forKey: .start)) ?? .random
    }
}
