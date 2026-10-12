public enum TournamentFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case americano
    case mexicano
    case winnerCourt

    public var displayName: String {
        switch self {
        case .americano: "Americano"
        case .mexicano: "Mexicano"
        case .winnerCourt: "Winner court"
        }
    }

    public var symbol: String {
        switch self {
        case .americano: "arrow.triangle.2.circlepath"
        case .mexicano: "list.number"
        case .winnerCourt: "arrow.up.arrow.down"
        }
    }
}

public enum GameFormat: Codable, Sendable, Hashable {
    case traditional(TraditionalRules)
    case tournament(TournamentFormat)

    public var isTournament: Bool {
        if case .tournament = self { return true }
        return false
    }
}
