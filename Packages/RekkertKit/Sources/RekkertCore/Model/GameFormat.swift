public enum TournamentFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case americano
    case mexicano

    public var displayName: String {
        switch self {
        case .americano: "Americano"
        case .mexicano: "Mexicano"
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
