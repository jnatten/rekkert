import Testing

@testable import RekkertCore

@Suite("What Rekkert does with Apple Health")
struct HealthDisclosureTests {
    @Test func thePhoneOnlyAsksToSaveWorkouts() {
        #expect(HealthDisclosure.saved(on: .phone) == [.workout])
        #expect(HealthDisclosure.read(on: .phone) == [])
    }

    /// The sets both apps asked for before the disclosure existed. Changing them changes what
    /// Rekkert collects, which is a decision rather than a refactor.
    @Test func theWatchSavesAndReadsWhatItAlwaysDid() {
        #expect(HealthDisclosure.saved(on: .watch) == [.workout, .activeEnergy, .restingEnergy, .effort])
        #expect(
            HealthDisclosure.read(on: .watch)
                == [.heartRate, .activeEnergy, .restingEnergy, .restingHeartRate, .dateOfBirth, .workout, .effort]
        )
    }

    @Test func everyKindSaysWhatItIsAndWhy() {
        let expected: [HealthData: (title: String, reason: String)] = [
            .workout: ("Workouts", "The session you played, saved as indoor tennis"),
            .activeEnergy: ("Active energy", "What the session burned, saved with the workout and shown on it"),
            .restingEnergy: ("Resting energy", "Added to active energy for the total, as the Workout app does"),
            .effort: ("Effort", "How hard you rated it, on the 1–10 scale"),
            .heartRate: ("Heart rate", "Shown on your wrist while you play, and on the match afterwards"),
            .restingHeartRate: ("Resting heart rate", "To place your heart rate in zones"),
            .dateOfBirth: ("Date of birth", "Your age, to estimate the top of your zones"),
        ]
        #expect(Set(expected.keys) == Set(HealthData.allCases))
        for kind in HealthData.allCases {
            #expect(kind.title == expected[kind]?.title)
            #expect(kind.reason == expected[kind]?.reason)
        }
    }

    @Test func theSummaryIsTheOneSettingsShows() {
        #expect(
            HealthDisclosure.summary
                == "Rekkert can save the workouts your Apple Watch records to Apple Health, and reads your heart rate and energy while one is running. Nothing it reads leaves your iPhone and Apple Watch."
        )
        #expect(!HealthDisclosure.when.isEmpty)
        #expect(!HealthDisclosure.whereItGoes.isEmpty)
        #expect(!HealthDisclosure.changeAccess.isEmpty)
        #expect(HealthDisclosure.changeAccess.allSatisfy { !$0.isEmpty })
    }

    /// The access paths quote the system's own menus, which say "Health", so they only have to
    /// keep clear of the framework's name.
    @Test func itNeverSaysHealthOnItsOwn() {
        let words = HealthData.allCases.flatMap { [$0.title, $0.reason] }
            + [HealthDisclosure.summary, HealthDisclosure.when, HealthDisclosure.whereItGoes]
        for text in words {
            #expect(!text.replacing("Apple Health", with: "").contains("Health"), "\(text)")
        }
        for text in words + HealthDisclosure.changeAccess {
            #expect(!text.contains("HealthKit"), "\(text)")
        }
    }

    @Test func thePageListsEverythingAndNothingElse() {
        let touched = [HealthDevice.phone, .watch].flatMap { HealthDisclosure.saved(on: $0) + HealthDisclosure.read(on: $0) }
        #expect(Set(touched) == Set(HealthData.allCases))
    }
}
