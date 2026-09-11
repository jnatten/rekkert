public enum Sport: String, Codable, Sendable, Hashable, CaseIterable {
    case padel
    case tennis

    public var displayName: String {
        switch self {
        case .padel: "Padel"
        case .tennis: "Tennis"
        }
    }

    public var defaultRules: TraditionalRules {
        switch self {
        case .padel: TraditionalRules(sport: .padel)
        case .tennis: TraditionalRules(sport: .tennis)
        }
    }
}
