public enum ServeCourt: String, Codable, Sendable, Hashable, CaseIterable {
    /// The server's right-hand half.
    case deuce
    /// The server's left-hand half.
    case ad

    public var displayName: String {
        switch self {
        case .deuce: "Deuce"
        case .ad: "Adv"
        }
    }

    /// Spelled out, for VoiceOver: "adv" is a label rather than a word.
    public var spokenName: String {
        switch self {
        case .deuce: "deuce"
        case .ad: "advantage"
        }
    }

    /// Which hand it is on, from behind the server looking at the net.
    public var sideName: String {
        switch self {
        case .deuce: "Right"
        case .ad: "Left"
        }
    }

    /// The same half of the court, named from the far end. The two players face each
    /// other, so the server's right is the receiver's left. This is a change of viewpoint,
    /// not a different service box: their deuce court is still their deuce court.
    public var seenFromTheOtherEnd: ServeCourt {
        switch self {
        case .deuce: .ad
        case .ad: .deuce
        }
    }
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
