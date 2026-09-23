import Foundation
import Testing
@testable import RekkertCore

/// A buzz leaves nothing behind for a screenshot to catch, so the whole of the judgement is
/// here rather than on the wrist.
@Suite("Buzzing for a point")
struct HapticTests {
    private func preferences(
        _ mode: HapticMode,
        onlyOthers: Bool = false,
        strength: HapticStrength = .medium
    ) -> HapticPreferences {
        HapticPreferences(mode: mode, onlyWhenSomeoneElseScores: onlyOthers, strength: strength)
    }

    @Test func offSaysNothingWhoeverScored() {
        let off = preferences(.off)
        for team in TeamSide.allCases {
            for here in [true, false] {
                #expect(off.buzz(forTeam: team, mine: .a, scoredHere: here) == nil)
            }
        }
    }

    @Test func everyPointIsOneTapWhoeverWonIt() {
        let every = preferences(.everyPoint)
        #expect(every.buzz(forTeam: .a, mine: .a, scoredHere: false)?.taps == 1)
        #expect(every.buzz(forTeam: .b, mine: .a, scoredHere: false)?.taps == 1, "theirs too")
    }

    @Test func oneTapForYoursAndTwoForTheirs() {
        let byTeam = preferences(.byTeam)
        #expect(byTeam.buzz(forTeam: .a, mine: .a, scoredHere: false)?.taps == 1)
        #expect(byTeam.buzz(forTeam: .b, mine: .a, scoredHere: false)?.taps == 2)
    }

    /// Which team is yours is the wearer's own answer, so the same point reads differently on
    /// two wrists on opposite sides of the net.
    @Test func theSamePointReadsBothWaysOnTwoWrists() {
        let byTeam = preferences(.byTeam)
        #expect(byTeam.buzz(forTeam: .b, mine: .a, scoredHere: false)?.taps == 2)
        #expect(byTeam.buzz(forTeam: .b, mine: .b, scoredHere: false)?.taps == 1)
    }

    @Test func theFilterSkipsWhatThisDeviceScoredItself() {
        for mode in [HapticMode.everyPoint, .byTeam] {
            let filtered = preferences(mode, onlyOthers: true)
            #expect(filtered.buzz(forTeam: .a, mine: .a, scoredHere: true) == nil)
            #expect(filtered.buzz(forTeam: .b, mine: .a, scoredHere: true) == nil, "theirs too")
            #expect(filtered.buzz(forTeam: .a, mine: .a, scoredHere: false) != nil)
        }
    }

    /// The combination the two settings exist for: somebody else tapped it, and the wrist
    /// still wants telling which way it went.
    @Test func theFilterStillSaysWhichTeamItWas() {
        let filtered = preferences(.byTeam, onlyOthers: true)
        #expect(filtered.buzz(forTeam: .a, mine: .a, scoredHere: false)?.taps == 1)
        #expect(filtered.buzz(forTeam: .b, mine: .a, scoredHere: false)?.taps == 2)
    }

    @Test func withoutTheFilterYourOwnTapsCountToo() {
        let unfiltered = preferences(.everyPoint, onlyOthers: false)
        #expect(unfiltered.buzz(forTeam: .a, mine: .a, scoredHere: true)?.taps == 1)
    }

    @Test func theStrengthIsCarriedThrough() {
        for strength in HapticStrength.allCases {
            let chosen = preferences(.everyPoint, strength: strength)
            #expect(chosen.buzz(forTeam: .a, mine: .a, scoredHere: false)?.strength == strength)
        }
    }

    // MARK: - The value itself

    @Test func nothingBuzzesUntilSomebodyAsksForIt() {
        #expect(HapticPreferences().mode == .off)
        #expect(HapticPreferences().hasBeenSet == false)
    }

    @Test func settingOneLeavesTheOthersAlone() {
        let loud = HapticPreferences().setting(strength: .strong)
        let both = loud.setting(mode: .byTeam)

        #expect(both.strength == .strong, "the strength survives the mode")
        #expect(both.mode == .byTeam)
        #expect(both.onlyWhenSomeoneElseScores, "and the default filter is untouched")
        #expect(both.revision == 2, "each change is its own revision")
    }

    @Test func theNewerRevisionWinsWhicheverFieldChanged() {
        let mine = HapticPreferences().setting(mode: .everyPoint)
        let theirs = mine.setting(strength: .light)

        #expect(mine.adopting(theirs) == theirs)
        #expect(theirs.adopting(mine) == theirs, "and both devices settle on the same one")
    }

    /// The counter rather than the clock decides, so a press made a moment later on a device
    /// running behind is not thrown away.
    @Test func aChangeIsNotLostToATrailingClock() {
        let earlier = HapticPreferences().setting(mode: .byTeam, at: Date())
        let later = earlier.setting(strength: .strong, at: earlier.updatedAt - 60)

        #expect(earlier.adopting(later) == later)
    }

    @Test func aStoredValueFromBeforeTheBuzzExistedStillReads() throws {
        let legacy = #"{"revision":3}"#
        let decoded = try JSONCoding.decoder.decode(HapticPreferences.self, from: Data(legacy.utf8))

        #expect(decoded.mode == .off, "staying quiet until somebody asks")
        #expect(decoded.strength == .medium)
        #expect(decoded.onlyWhenSomeoneElseScores)
        #expect(decoded.revision == 3)
    }

    @Test func aTournamentPlayerIsFoundOnTheirOwnCourtOnly() {
        let players = (0 ..< 9).map { Player(name: "\($0)") }
        let id = players.map(\.id)
        let round = Round(index: 0, matches: [
            CourtMatch(courtIndex: 0, teams: BySide(a: [id[0], id[1]], b: [id[2], id[3]])),
            CourtMatch(courtIndex: 1, teams: BySide(a: [id[4], id[5]], b: [id[6], id[7]])),
        ], sitOuts: [id[8]])
        let tournament = Tournament(format: .americano, players: players, rounds: [round])

        #expect(tournament.side(of: id[6], round: 0, court: 1) == .b)
        #expect(tournament.side(of: id[6], round: 0, court: 0) == nil, "not their court")
        #expect(tournament.court(of: id[6], round: 0) == 1)
        #expect(tournament.court(of: id[8], round: 0) == nil, "sitting out")
    }

    @Test func whoYouArePassesThroughTheOtherSettings() throws {
        let me = Me(session: UUID(), player: PlayerID())
        let chosen = HapticPreferences().setting(mode: .byTeam).choosing(me: me)
        #expect(chosen.setting(strength: .strong).me == me)
        #expect(chosen.revision == 2)

        let decoded = try JSONCoding.decoder.decode(
            HapticPreferences.self, from: JSONCoding.encoder.encode(chosen)
        )
        #expect(decoded == chosen)
    }
}
