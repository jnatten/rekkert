public enum ServeCourt: String, Codable, Sendable, Hashable, CaseIterable {
    /// The server's right-hand half.
    case deuce
    /// The server's left-hand half.
    case ad

    public var displayName: String {
        switch self {
        case .deuce: "Deuce"
        case .ad: "Ad"
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

/// Where the rotation starts and, per side, whether the partners take their turns the other
/// way round from how `ServeRotation.order` names them. Two plain fields rather than one
/// canonical form, so a score filed before the second existed still reads.
public struct ServeOrder: Codable, Sendable, Hashable {
    public var firstServerIndex: Int
    public var serversSwapped: BySide<Bool>

    public init(firstServerIndex: Int = 0, serversSwapped: BySide<Bool> = BySide(both: false)) {
        self.firstServerIndex = firstServerIndex
        self.serversSwapped = serversSwapped
    }

    /// The other team starts, each side keeping its own first server. Moving the start on by
    /// one also reverses the turns of the side that was starting, so that flag flips back.
    public func swappingTeams() -> ServeOrder {
        var next = self
        next.serversSwapped[ServeRotation.slot(at: firstServerIndex).team].toggle()
        next.firstServerIndex = (firstServerIndex + 1) % ServeRotation.order.count
        return next
    }

    public func swappingPlayers(of team: TeamSide) -> ServeOrder {
        var next = self
        next.serversSwapped[team].toggle()
        return next
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

    /// The same slot with the partners of a swapped side taking their turns the other way round.
    public static func slot(at index: Int, swapping swapped: BySide<Bool>) -> ServeSlot {
        var slot = slot(at: index)
        if swapped[slot.team] { slot.playerIndex = 1 - slot.playerIndex }
        return slot
    }

    /// Americano/Mexicano: every player serves `servesPerTeam` consecutive points, which
    /// makes service alternate between the teams at the same interval.
    public static func pointCountingSlot(
        totalPointsPlayed: Int,
        servesPerTeam: Int,
        startIndex: Int = 0,
        swapping swapped: BySide<Bool> = BySide(both: false)
    ) -> ServeSlot {
        let stride = max(1, servesPerTeam)
        return slot(at: startIndex + totalPointsPlayed / stride, swapping: swapped)
    }
}
