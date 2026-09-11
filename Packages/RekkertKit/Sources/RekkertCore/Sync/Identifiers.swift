import Foundation

public struct DeviceID: Hashable, Codable, Sendable, Comparable {
    public let raw: UUID

    public init(_ raw: UUID = UUID()) { self.raw = raw }

    public static func < (lhs: DeviceID, rhs: DeviceID) -> Bool {
        lhs.raw.uuidString < rhs.raw.uuidString
    }
}

public struct EventID: Hashable, Codable, Sendable, Comparable {
    public let device: DeviceID
    public let seq: UInt32

    public init(device: DeviceID, seq: UInt32) {
        self.device = device
        self.seq = seq
    }

    public static func < (lhs: EventID, rhs: EventID) -> Bool {
        (lhs.device, lhs.seq) < (rhs.device, rhs.seq)
    }
}
