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

    private func preview(courts: (Int, Int), bench: (Int, Int), from round: Int = 7, short: Bool = false) -> AwayPreview {
        AwayPreview(
            player: PlayerID(), isAway: true, fromRound: round,
            courtsBefore: courts.0, courtsAfter: courts.1, benchBefore: bench.0, benchAfter: bench.1,
            redrawsRoundInPlay: false, stoppingCourt: nil, isShortOfPlayers: short
        )
    }

    @Test func theShapeOfTheEveningIsSaidOnlyWhenItChanges() {
        #expect(AwayText.shape(preview(courts: (2, 2), bench: (2, 1))) == "From round 7: 2 courts, 1 sits out each round.")
        #expect(AwayText.shape(preview(courts: (2, 1), bench: (0, 3))) == "From round 7: 1 court, 3 sit out each round.")
        #expect(AwayText.shape(preview(courts: (1, 2), bench: (3, 0))) == "From round 7: 2 courts, nobody sits out.")
        #expect(AwayText.shape(preview(courts: (2, 2), bench: (1, 0))) == "Nobody sits out from round 7.")
        #expect(AwayText.shape(preview(courts: (2, 2), bench: (1, 1))) == nil)
        #expect(AwayText.shape(preview(courts: (1, 0), bench: (0, 3), short: true)) == "Fewer than four are left, so no more rounds can be drawn.")
    }

    @Test func theCourtsScreenSaysWhenNoRoundCanBeDrawn() {
        #expect(AwayText.shortOfPlayers == "Fewer than four players are here, so no more rounds can be drawn.")
    }

    @Test func historySaysWhoMissedARound() throws {
        #expect(AwayText.awayInRound([]) == nil)
        #expect(AwayText.awayInRound(["Eve", "Ada"]) == "Away: Eve, Ada")

        var tournament = try TournamentFixture.drawing(TournamentFixture.make(.americano, players: 9, courts: 2), rounds: 2)
        tournament = TournamentEngine.settingAway(TournamentFixture.playerID(2), isAway: true, after: 1, placed: nil, in: tournament)
        tournament = try TournamentFixture.drawing(tournament, rounds: 2)
        #expect(tournament.missing(inRound: 1).isEmpty)
        #expect(tournament.missing(inRound: 2).map(\.name) == ["P2"])
    }
}
