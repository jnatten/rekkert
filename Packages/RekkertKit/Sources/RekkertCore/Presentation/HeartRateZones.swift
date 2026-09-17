import Foundation

/// The five bands a working heart rate falls into, so a number on a watch face can say what
/// it means as well as what it is.
///
/// Placed along the reserve — what is left between resting and maximum — rather than as flat
/// percentages of the maximum. That is the Karvonen method, and it is what makes zone 2 mean
/// roughly the same effort for two people whose hearts idle at very different rates. Health
/// knows the resting rate for most wrists; where it does not, `resting` is nil, the reserve
/// becomes the whole of the maximum, and this collapses to the plain percentages.
///
/// Ours rather than Apple's. The Workout app's own boundaries are private, and a number here
/// claiming to be the same one would quietly stop being true the first time they moved it.
public struct HeartRateZones: Sendable, Hashable {
    /// Where zone 5 tops out.
    public var maximum: Double
    /// The floor the reserve is measured up from, when Health knows it.
    public var resting: Double?

    public static let count = 5

    /// Lower edge of each zone, as a fraction of the reserve.
    private static let edges: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]

    public init?(maximum: Double, resting: Double? = nil) {
        guard maximum > 0, maximum > (resting ?? 0) else { return nil }
        self.maximum = maximum
        self.resting = resting
    }

    /// The back-of-an-envelope ceiling, which is the only one available without a lab. The
    /// range is a sanity check on the birthday rather than a claim about who may play.
    public static func estimatedMaximum(forAge years: Int) -> Double? {
        guard (10 ... 120).contains(years) else { return nil }
        return 220 - Double(years)
    }

    private var floorRate: Double { resting ?? 0 }
    private var reserve: Double { maximum - floorRate }

    /// Beats per minute at which a zone begins. Zones are numbered 1 through 5.
    public func lowerBound(of number: Int) -> Double {
        let index = min(max(number, 1), Self.count) - 1
        return (floorRate + reserve * Self.edges[index]).rounded()
    }

    /// The last beat that still counts as this zone. Nil for zone 5, which has no ceiling —
    /// the estimated maximum is an estimate, and hearts go past it.
    public func upperBound(of number: Int) -> Double? {
        guard number < Self.count else { return nil }
        return lowerBound(of: number + 1) - 1
    }

    /// Where a reading sits, or nil when it is still under zone 1 — which is most of what a
    /// padel court asks of you, and not a thing to dress up as a zone.
    public func number(for beatsPerMinute: Double) -> Int? {
        (1 ... Self.count).last { beatsPerMinute >= lowerBound(of: $0) }
    }

    /// How far up the reserve a reading is, clamped, for drawing a bar.
    public func fraction(for beatsPerMinute: Double) -> Double {
        min(max((beatsPerMinute - floorRate) / reserve, 0), 1)
    }
}
