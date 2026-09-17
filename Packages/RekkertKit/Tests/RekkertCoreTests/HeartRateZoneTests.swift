import Foundation
import Testing

@testable import RekkertCore

@Suite("Heart rate zones")
struct HeartRateZoneTests {
    /// A forty-year-old with a resting rate of 60: maximum 180, reserve 120, so the edges
    /// land on round numbers and the arithmetic is readable by eye.
    private let zones = HeartRateZones(maximum: 180, resting: 60)!

    @Test func theEdgesAreMeasuredUpFromResting() {
        #expect(zones.lowerBound(of: 1) == 120)
        #expect(zones.lowerBound(of: 2) == 132)
        #expect(zones.lowerBound(of: 3) == 144)
        #expect(zones.lowerBound(of: 4) == 156)
        #expect(zones.lowerBound(of: 5) == 168)
    }

    @Test func aZoneEndsWhereTheNextOneBegins() {
        #expect(zones.upperBound(of: 1) == 131)
        #expect(zones.upperBound(of: 4) == 167)
        // Zone 5 has no ceiling: the maximum it is measured from is an estimate, and hearts
        // go past it.
        #expect(zones.upperBound(of: 5) == nil)
    }

    @Test func aReadingLandsInTheZoneItReaches() {
        #expect(zones.number(for: 120) == 1)
        #expect(zones.number(for: 131) == 1)
        #expect(zones.number(for: 132) == 2)
        #expect(zones.number(for: 150) == 3)
        #expect(zones.number(for: 168) == 5)
        // Past the estimate, which is a thing that happens rather than an error.
        #expect(zones.number(for: 205) == 5)
    }

    /// Standing at the back of the court between points. Saying "zone 1" for it would be
    /// flattery.
    @Test func aReadingBelowTheFirstEdgeIsInNoZoneAtAll() {
        #expect(zones.number(for: 119) == nil)
        #expect(zones.number(for: 62) == nil)
    }

    /// The common case on a wrist Health has no resting rate for: the reserve becomes the
    /// whole of the maximum, which is the plain percentage scheme everybody else uses.
    @Test func withoutARestingRateTheEdgesArePercentagesOfTheMaximum() throws {
        let zones = try #require(HeartRateZones(maximum: 180))

        #expect(zones.lowerBound(of: 1) == 90)
        #expect(zones.lowerBound(of: 3) == 126)
        #expect(zones.number(for: 145) == 4)
    }

    @Test func theBarFillsAcrossTheReserveAndStopsAtTheEnds() {
        #expect(zones.fraction(for: 60) == 0)
        #expect(zones.fraction(for: 120) == 0.5)
        #expect(zones.fraction(for: 180) == 1)
        #expect(zones.fraction(for: 40) == 0)
        #expect(zones.fraction(for: 220) == 1)
    }

    @Test func nonsenseIsRefusedRatherThanDrawn() {
        #expect(HeartRateZones(maximum: 0) == nil)
        #expect(HeartRateZones(maximum: 120, resting: 130) == nil)
        #expect(HeartRateZones.estimatedMaximum(forAge: 5) == nil)
        #expect(HeartRateZones.estimatedMaximum(forAge: 200) == nil)
    }

    @Test func theMaximumIsTheUsualEstimate() {
        #expect(HeartRateZones.estimatedMaximum(forAge: 40) == 180)
        #expect(HeartRateZones.estimatedMaximum(forAge: 12) == 208)
    }
}
