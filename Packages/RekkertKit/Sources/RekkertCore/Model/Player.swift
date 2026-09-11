import Foundation

public struct PlayerID: Hashable, Codable, Sendable, Comparable {
    public let raw: UUID

    public init(_ raw: UUID = UUID()) { self.raw = raw }

    public static func < (lhs: PlayerID, rhs: PlayerID) -> Bool {
        lhs.raw.uuidString < rhs.raw.uuidString
    }
}

public struct Player: Hashable, Codable, Sendable, Identifiable {
    public var id: PlayerID
    public var name: String

    public init(id: PlayerID = PlayerID(), name: String) {
        self.id = id
        self.name = name
    }
}
