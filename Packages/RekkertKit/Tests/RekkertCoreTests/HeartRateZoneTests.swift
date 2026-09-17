import Foundation
import Testing

@testable import RekkertCore

@Suite("Heart rate zones")
struct HeartRateZoneTests {
    /// What a real wrist reports: zone 1 under 134, then 134–145, 146–157, 158–169, 170 up.
    private let zones = HeartRateZones(boundaries: [134, 146, 158, 170])!

    @Test func aZoneRunsFromItsOwnBoundaryToTheNext() {
        #expect(zones.count == 5)
        #expect(zones.lowerBound(of: 2) == 134)
        #expect(zones.upperBound(of: 2) == 145)
        #expect(zones.lowerBound(of: 3) == 146)
        #expect(zones.upperBound(of: 4) == 169)
        #expect(zones.lowerBound(of: 5) == 170)
    }

    /// A heart cannot be under zone 1, and the top zone has no ceiling — whatever maximum
    /// the boundaries came from is an estimate that hearts go past.
    @Test func theOutermostZonesHaveNoOuterEdge() {
        #expect(zones.lowerBound(of: 1) == nil)
        #expect(zones.upperBound(of: 5) == nil)
        #expect(zones.upperBound(of: 1) == 133)
    }

    @Test func aReadingLandsInTheZoneItReaches() {
        #expect(zones.number(for: 133) == 1)
        #expect(zones.number(for: 134) == 2)
        #expect(zones.number(for: 145) == 2)
        #expect(zones.number(for: 146) == 3)
        #expect(zones.number(for: 158) == 4)
        #expect(zones.number(for: 170) == 5)
        #expect(zones.number(for: 205) == 5)
    }

    /// Standing at the back of the court between points, and sitting down afterwards. Zone 1
    /// has no floor, so both are in it rather than in nothing.
    @Test func aRestingHeartIsStillInZoneOne() {
        #expect(zones.number(for: 62) == 1)
        #expect(zones.number(for: 40) == 1)
    }

    /// Health Settings will take any boundaries a person cares to type, so five is what the
    /// system generates rather than what this can be handed.
    @Test func anySetOfBoundariesIsDrawable() throws {
        let three = try #require(HeartRateZones(boundaries: [120, 160]))

        #expect(three.count == 3)
        #expect(three.number(for: 119) == 1)
        #expect(three.number(for: 160) == 3)
        #expect(three.upperBound(of: 3) == nil)
    }

    @Test func boundariesAreSortedAndNonsenseIsRefused() throws {
        #expect(try #require(HeartRateZones(boundaries: [170, 134, 158, 146])).boundaries
            == [134, 146, 158, 170])
        #expect(HeartRateZones(boundaries: []) == nil)
        #expect(HeartRateZones(boundaries: [0, 140]) == nil)
        #expect(HeartRateZones(boundaries: [140, 140]) == nil)
    }

    // MARK: - The fallback, for the watchOS that cannot be asked

    /// The whole point of the estimate: on watchOS 26 it has to land on the same numbers the
    /// Health app shows, and for a resting rate of 62 and a maximum of 182 it does.
    @Test func theEstimateReproducesWhatHealthReports() throws {
        let estimated = try #require(HeartRateZones.estimated(maximum: 182, resting: 62))

        #expect(estimated == zones)
    }

    /// The common case on a wrist Health has no resting rate for: the reserve becomes the
    /// whole of the maximum, which is the plain percentage scheme everybody else uses.
    @Test func withoutARestingRateTheEdgesArePercentagesOfTheMaximum() throws {
        let estimated = try #require(HeartRateZones.estimated(maximum: 180))

        #expect(estimated.boundaries == [108, 126, 144, 162])
    }

    @Test func nonsenseIsRefusedRatherThanDrawn() {
        #expect(HeartRateZones.estimated(maximum: 0) == nil)
        #expect(HeartRateZones.estimated(maximum: 120, resting: 130) == nil)
        #expect(HeartRateZones.estimatedMaximum(forAge: 5) == nil)
        #expect(HeartRateZones.estimatedMaximum(forAge: 200) == nil)
    }

    @Test func theMaximumIsTheUsualEstimate() {
        #expect(HeartRateZones.estimatedMaximum(forAge: 38) == 182)
        #expect(HeartRateZones.estimatedMaximum(forAge: 12) == 208)
    }
}
