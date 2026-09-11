public enum ServeCourt: String, Codable, Sendable, Hashable {
    case deuce
    case ad
}

public struct ServeSlot: Codable, Sendable, Hashable {
    public var team: TeamSide
    public var playerIndex: Int

    public init(team: TeamSide, playerIndex: Int) {
        self.team = team
        self.playerIndex = playerIndex
    }
}

public struct ServeState: Codable, Sendable, Hashable {
    public var slot: ServeSlot
    public var court: ServeCourt

    public init(slot: ServeSlot, court: ServeCourt) {
        self.slot = slot
        self.court = court
    }
}

public enum ServeRotation {
    /// Padel service order: one player from each team alternating, so partners never serve
    /// back to back.
    public static let order: [ServeSlot] = [
        ServeSlot(team: .a, playerIndex: 0),
        ServeSlot(team: .b, playerIndex: 0),
        ServeSlot(team: .a, playerIndex: 1),
        ServeSlot(team: .b, playerIndex: 1),
    ]

    public static func slot(at index: Int) -> ServeSlot {
        let count = order.count
        return order[((index % count) + count) % count]
    }

    /// Americano/Mexicano: every player serves `servesPerTeam` consecutive points, which
    /// makes service alternate between the teams at the same interval.
    public static func pointCountingSlot(totalPointsPlayed: Int, servesPerTeam: Int, startIndex: Int = 0) -> ServeSlot {
        let stride = max(1, servesPerTeam)
        return slot(at: startIndex + totalPointsPlayed / stride)
    }
}
