import Foundation

/// The bands a working heart rate falls into, so a number on a watch face can say what it
/// means as well as what it is.
///
/// Nothing but boundaries: the beat each zone above the first begins at, lowest first. Where
/// they came from is not this type's business, which is what lets the same drawing serve the
/// ones Health hands over and the ones worked out here when it will not.
///
/// The count is not fixed at five. Five is what the system generates, but the zones can be
/// set by hand in Health Settings and a person who has done that may have any number of
/// them.
///
/// Both ends are open. Zone 1 has no floor — being under it would mean being under your own
/// resting rate — and the top zone has no ceiling, because whatever maximum the boundaries
/// were derived from is an estimate, and hearts go past it.
public struct HeartRateZones: Sendable, Hashable {
    /// Strictly increasing, one shorter than the number of zones.
    public let boundaries: [Double]

    public init?(boundaries: [Double]) {
        let sorted = boundaries.sorted()
        guard let first = sorted.first, first > 0 else { return nil }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        self.boundaries = sorted
    }

    public var count: Int { boundaries.count + 1 }

    /// The first beat that counts as this zone, or nil for zone 1.
    public func lowerBound(of number: Int) -> Double? {
        guard number > 1, number <= count else { return nil }
        return boundaries[number - 2]
    }

    /// The last beat that still counts as this zone, or nil for the top one.
    public func upperBound(of number: Int) -> Double? {
        guard number < count else { return nil }
        return lowerBound(of: number + 1).map { $0 - 1 }
    }

    /// Where a reading sits. Always somewhere: a heart that is beating at all is in zone 1.
    public func number(for beatsPerMinute: Double) -> Int {
        (boundaries.firstIndex { beatsPerMinute < $0 } ?? boundaries.count) + 1
    }

    // MARK: - When Health will not say

    /// The bands the system would have generated, for the watchOS versions that cannot be
    /// asked for the real ones.
    ///
    /// Measured along the reserve — what is left between resting and maximum — which is the
    /// Karvonen method and what Apple documents using. Four equal tenths of it from 60%,
    /// which reproduces the boundaries a real wrist reports: resting 62 and maximum 182 give
    /// zone 1 under 134 and zone 2 at 134–145, exactly as the Health app shows them. Where
    /// Health has no resting rate the reserve becomes the whole of the maximum, which
    /// collapses to the plain percentages.
    public static func estimated(maximum: Double, resting: Double? = nil) -> HeartRateZones? {
        guard maximum > 0, maximum > (resting ?? 0) else { return nil }
        let floorRate = resting ?? 0
        let reserve = maximum - floorRate
        return HeartRateZones(
            boundaries: [0.6, 0.7, 0.8, 0.9].map { (floorRate + reserve * $0).rounded() }
        )
    }

    /// The back-of-an-envelope ceiling, which is the only one available without a lab. The
    /// range is a sanity check on the birthday rather than a claim about who may play.
    public static func estimatedMaximum(forAge years: Int) -> Double? {
        guard (10 ... 120).contains(years) else { return nil }
        return 220 - Double(years)
    }
}
