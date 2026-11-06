import Foundation

/// SplitMix64. Both devices must derive identical schedules from the same event log, so
/// every shuffle in the tournament engine runs through a seeded generator rather than
/// `SystemRandomNumberGenerator`.
///
/// Deliberately not a `RandomNumberGenerator`. The stdlib's `shuffled(using:)` and
/// `Int.random(in:using:)` draw at the width of `Int`, which is 32 bits on an Apple Watch SE
/// (1st generation) and 64 on a phone, so the same seed put different teams on the watch.
/// Everything here draws in `UInt64` instead.
public struct SeededGenerator: Sendable {
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

    /// Lemire's nearly divisionless method, step for step as the stdlib's `next(upperBound:)`
    /// runs it for `UInt64`, so every draw a 64-bit device has made comes out the same.
    public mutating func next(below bound: UInt64) -> UInt64 {
        precondition(bound > 0, "bound cannot be zero")
        var product = next().multipliedFullWidth(by: bound)
        if product.low < bound {
            let threshold = (0 &- bound) % bound
            while product.low < threshold {
                product = next().multipliedFullWidth(by: bound)
            }
        }
        return product.high
    }
}

extension Array {
    /// The stdlib's Fisher–Yates walk from the front, drawing in `UInt64`: what
    /// `shuffled(using:)` gives on 64-bit hardware, on every device.
    public func shuffled(seededBy generator: inout SeededGenerator) -> [Element] {
        var result = self
        var remaining = count
        var current = 0
        while remaining > 1 {
            let offset = Int(generator.next(below: UInt64(remaining)))
            remaining -= 1
            result.swapAt(current, current + offset)
            current += 1
        }
        return result
    }
}
