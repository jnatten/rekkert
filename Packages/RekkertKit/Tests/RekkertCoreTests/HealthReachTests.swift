import Testing

@testable import RekkertCore

@Suite("Whether a device can record a workout")
struct HealthReachTests {
    @Test func everyCombinationLandsOnTheFirstReasonThatApplies() {
        for healthAvailable in [false, true] {
            for canPairWatch in [false, true] {
                for isPaired in [false, true] {
                    for watchAppInstalled in [false, true] {
                        let reach = HealthReach(
                            healthAvailable: healthAvailable,
                            canPairWatch: canPairWatch,
                            isPaired: isPaired,
                            watchAppInstalled: watchAppInstalled
                        )
                        let expected: HealthReach =
                            if !healthAvailable { .unavailable }
                            else if !canPairWatch { .cannotPair }
                            else if !isPaired { .noWatch }
                            else if !watchAppInstalled { .watchAppMissing }
                            else { .canRecord }
                        #expect(reach == expected)
                        #expect(
                            (reach == .canRecord) == (healthAvailable && canPairWatch && isPaired && watchAppInstalled)
                        )
                    }
                }
            }
        }
    }

    @Test func eachReasonSaysWhy() {
        #expect(HealthReach.canRecord.line == nil)
        #expect(HealthReach.unavailable.line == "Apple Health isn't available on this device, so Rekkert never uses it here.")
        #expect(
            HealthReach.cannotPair.line
                == "Workouts are recorded by an Apple Watch paired with an iPhone. Rekkert doesn't use Apple Health on iPad."
        )
        #expect(HealthReach.noWatch.line == "Recording a workout needs an Apple Watch paired with this iPhone.")
        #expect(HealthReach.watchAppMissing.line == "Install Rekkert on your Apple Watch to record workouts.")
    }
}
