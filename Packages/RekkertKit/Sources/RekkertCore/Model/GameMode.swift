public enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case traditional
    case pointCount
    case winnerCourt
    case friendly
    case americano
    case mexicano

    public var id: String { rawValue }

    public init(_ configuration: PresetConfiguration) {
        switch configuration {
        case .traditional: self = .traditional
        case .pointCount: self = .pointCount
        case .winnerCourt: self = .winnerCourt
        case .friendly: self = .friendly
        case .tournament(let format, _, _, _):
            switch format {
            case .americano: self = .americano
            case .mexicano: self = .mexicano
            case .winnerCourt: self = .winnerCourt
            }
        }
    }

    public var title: String {
        switch self {
        case .traditional: "Match"
        case .pointCount: "Points"
        case .winnerCourt: "Winner court"
        case .friendly: "Friendly"
        case .americano: "Americano"
        case .mexicano: "Mexicano"
        }
    }

    public var subtitle: String {
        switch self {
        case .traditional: "Games, sets and match"
        case .pointCount: "One round, counted 1, 2, 3 to a target"
        case .winnerCourt: "Games until the whistle, round after round"
        case .friendly: "Rotating teams, match after match"
        case .americano: "Everyone partners everyone"
        case .mexicano: "Re-paired by standings each round"
        }
    }

    public var symbol: String {
        switch self {
        case .traditional: "figure.tennis"
        case .pointCount: "number"
        case .winnerCourt: "arrow.up.arrow.down"
        case .friendly: "shuffle"
        case .americano: "arrow.triangle.2.circlepath"
        case .mexicano: "list.number"
        }
    }

    public var tournamentFormat: TournamentFormat? {
        switch self {
        case .traditional, .pointCount, .winnerCourt, .friendly: nil
        case .americano: .americano
        case .mexicano: .mexicano
        }
    }
}
