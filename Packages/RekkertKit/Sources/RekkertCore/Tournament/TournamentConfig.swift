public enum SitOutCompensation: Codable, Sendable, Hashable {
    case none
    case half
    case full
    case fixed(Int)

    public func points(target: Int) -> Int {
        switch self {
        case .none: 0
        case .half: target / 2
        case .full: target
        case .fixed(let value): max(0, value)
        }
    }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .half: "Half the target"
        case .full: "Full target"
        case .fixed(let value): "\(value) points"
        }
    }
}

public enum MexicanoPairing: String, Codable, Sendable, Hashable, CaseIterable {
    /// 1+4 vs 2+3 — the usual club rule.
    case topWithBottom
    /// 1+3 vs 2+4.
    case topWithThird

    public var displayName: String {
        switch self {
        case .topWithBottom: "1+4 vs 2+3"
        case .topWithThird: "1+3 vs 2+4"
        }
    }
}

/// How long a tournament is meant to run. Never ends one by itself: it only says when to ask.
public enum TournamentLength: Codable, Sendable, Hashable {
    /// Until everybody has partnered everybody. Americano only.
    case fullRotation
    /// This many rounds that count; a cancelled one does not.
    case rounds(Int)
}

public struct TournamentConfig: Codable, Sendable, Hashable {
    public var pointRules: PointCountRules
    public var courtCount: Int
    public var sitOutCompensation: SitOutCompensation
    public var mexicanoPairing: MexicanoPairing
    public var ladder: LadderRules?
    /// Nil plays on until somebody finishes it.
    public var length: TournamentLength?

    public init(
        pointRules: PointCountRules = PointCountRules(),
        courtCount: Int = 1,
        sitOutCompensation: SitOutCompensation = .half,
        mexicanoPairing: MexicanoPairing = .topWithBottom,
        ladder: LadderRules? = nil,
        length: TournamentLength? = nil
    ) {
        self.pointRules = pointRules
        self.courtCount = courtCount
        self.sitOutCompensation = sitOutCompensation
        self.mexicanoPairing = mexicanoPairing
        self.ladder = ladder
        self.length = length
    }

    private enum CodingKeys: String, CodingKey {
        case pointRules, courtCount, sitOutCompensation, mexicanoPairing, ladder, length
    }

    /// A length this build does not know reads as open rather than losing the whole tournament.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pointRules = try container.decode(PointCountRules.self, forKey: .pointRules)
        courtCount = try container.decode(Int.self, forKey: .courtCount)
        sitOutCompensation = try container.decode(SitOutCompensation.self, forKey: .sitOutCompensation)
        mexicanoPairing = try container.decode(MexicanoPairing.self, forKey: .mexicanoPairing)
        ladder = try container.decodeIfPresent(LadderRules.self, forKey: .ladder)
        length = (try? container.decodeIfPresent(TournamentLength.self, forKey: .length)) ?? nil
    }
}
