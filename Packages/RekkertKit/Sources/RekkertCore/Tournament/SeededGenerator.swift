import Foundation

/// SplitMix64. Both devices must derive identical schedules from the same event log, so
/// every shuffle in the tournament engine runs through a seeded generator rather than
/// `SystemRandomNumberGenerator`.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public init(_ id: UUID, salt: UInt64 = 0) {
        var hasher = UInt64(0)
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hasher = (hasher ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
        }
        self.state = hasher ^ salt
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
