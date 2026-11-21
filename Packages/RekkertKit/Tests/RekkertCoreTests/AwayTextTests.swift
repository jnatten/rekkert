import Testing
@testable import RekkertCore

/// Spec 008, contracts/screens.md: every sentence about leaving and coming back.
@Suite("What the phone says about who has left")
struct AwayTextTests {
    @Test func theFooterNamesWhoHasLeft() {
        #expect(AwayText.awayFooter([]) == nil)
        #expect(AwayText.awayFooter(["Eve"]) == "Eve has left. The draw leaves Eve out.")
        #expect(AwayText.awayFooter(["Ada", "Eve"]) == "Ada and Eve have left. The draw leaves them out.")
        #expect(AwayText.awayFooter(["Ada", "Bob", "Eve"]) == "Ada, Bob and Eve have left. The draw leaves them out.")
    }

    @Test func theConfirmationAsksByName() {
        #expect(AwayText.leaveTitle("Eve") == "Has Eve left?")
        #expect(AwayText.leaveButton("Eve") == "Eve has left")
    }

    @Test func aStretchSaysWhenTheyLeft() {
        #expect(AwayText.stretches([]) == nil)
        #expect(AwayText.stretches([AwayStretch(firstMissed: 5)]) == "Left after round 4")
        #expect(AwayText.stretches([AwayStretch(firstMissed: 1)]) == "Left before round 1")
    }

    @Test func olderPhonesAreCounted() {
        #expect(AwayText.turnedAway(0) == nil)
        #expect(AwayText.turnedAway(1) == "1 phone on an older Rekkert will be taken off this tournament. It can join again once updated.")
        #expect(AwayText.turnedAway(2) == "2 phones on an older Rekkert will be taken off this tournament. They can join again once updated.")
    }
}
