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

public struct TournamentConfig: Codable, Sendable, Hashable {
    public var pointRules: PointCountRules
    public var courtCount: Int
    public var sitOutCompensation: SitOutCompensation
    public var mexicanoPairing: MexicanoPairing

    public init(
        pointRules: PointCountRules = PointCountRules(),
        courtCount: Int = 1,
        sitOutCompensation: SitOutCompensation = .half,
        mexicanoPairing: MexicanoPairing = .topWithBottom
    ) {
        self.pointRules = pointRules
        self.courtCount = courtCount
        self.sitOutCompensation = sitOutCompensation
        self.mexicanoPairing = mexicanoPairing
    }
}
