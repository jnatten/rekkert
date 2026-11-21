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

    @Test func midRoundSaysWhatHappensToTheRoundInPlay() {
        #expect(AwayText.redraws(round: 6, name: "Eve", isAway: true) == "Round 6 hasn't started, so it's drawn again without Eve.")
        #expect(AwayText.stops(court: 2, at: BySide(a: 9, b: 7)) == "Court 2 stops at 9–7 and counts as it stands.")
        #expect(AwayText.stops(court: 1, at: BySide(a: 0, b: 0)) == "Court 1 stops at 0–0 and counts as it stands.")
        #expect(AwayText.stillOnCourt(court: 2, round: 6) == "Still drawn on court 2 in round 6.")
        #expect(AwayText.takeOff("Eve", round: 6) == "Take Eve off round 6")
    }

    @Test func theConfirmationListsWhatTheEngineWillDo() throws {
        var tournament = try TournamentFixture.draw(TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 2))
        let unstarted = try #require(tournament.currentRound)
        let first = unstarted.matches[0].teams.a[0]
        let redraw = try #require(TournamentEngine.awayPreview(first, isAway: true, in: tournament))
        #expect(AwayText.inPlay(redraw, name: "Eve", roundInPlay: 3) == ["Round 3 hasn't started, so it's drawn again without Eve."])

        tournament.rounds[2].matches[0].state.points = BySide(a: 6, b: 5)
        let stop = try #require(TournamentEngine.awayPreview(first, isAway: true, in: tournament))
        #expect(stop.fromRound == 4)
        #expect(AwayText.inPlay(stop, name: "Eve", roundInPlay: 3) == ["Court 1 stops at 6–5 and counts as it stands."])
    }
}
