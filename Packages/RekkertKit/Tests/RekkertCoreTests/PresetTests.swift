import Foundation
import Testing
@testable import RekkertCore

private func tournamentPreset(_ name: String = "Thursday") -> Preset {
    Preset(name: name, configuration: .tournament(
        format: .americano,
        name: "Thursday night",
        players: ["Jonas", "Ada", "Kim", "Sam"].map { Player(name: $0) },
        config: TournamentConfig(pointRules: PointCountRules(target: 21), courtCount: 1)
    ))
}

private func friendlyPreset(_ name: String = "Thursday mix") -> Preset {
    Preset(name: name, configuration: .friendly(
        name: "Thursday night",
        players: ["Jonas", "Ada", "Kim", "Sam", "Ola"].map { Player(name: $0) },
        rules: TraditionalRules(setsToWin: 1, gamesPerSet: 4)
    ))
}

@Suite("Presets")
struct PresetTests {
    @Test func startingFromATournamentPresetMintsAFreshTournament() {
        let preset = tournamentPreset()
        guard case .tournament(let one) = preset.configuration.makeSetup(),
              case .tournament(let two) = preset.configuration.makeSetup()
        else {
            Issue.record("not a tournament")
            return
        }
        #expect(one.id != two.id, "two evenings from one preset are two tournaments")
        #expect(one.config.pointRules.target == 21, "but the settings carry over")
        #expect(one.players.map(\.name) == ["Jonas", "Ada", "Kim", "Sam"])
        #expect(Set(one.players.map(\.id)).isDisjoint(with: Set(two.players.map(\.id))),
                "and the players are fresh too, so standings never bleed across")
    }

    @Test func startingFromAFriendlyPresetMintsAFreshSession() {
        let preset = friendlyPreset()
        guard case .friendly(let one) = preset.configuration.makeSetup(),
              case .friendly(let two) = preset.configuration.makeSetup()
        else {
            Issue.record("not a friendly")
            return
        }
        #expect(one.id != two.id, "a fresh id, so the draw does not repeat last week's")
        #expect(one.rules.gamesPerSet == 4, "but the settings carry over")
        #expect(one.players.map(\.name) == ["Jonas", "Ada", "Kim", "Sam", "Ola"])
        #expect(Set(one.players.map(\.id)).isDisjoint(with: Set(two.players.map(\.id))))
    }

    @Test func onlyTheRotatingModesNeedARoundDrawn() {
        #expect(tournamentPreset().configuration.drawsRounds)
        #expect(friendlyPreset().configuration.drawsRounds)
        #expect(!PresetConfiguration.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)).drawsRounds)
        #expect(!PresetConfiguration.winnerCourt(rules: WinnerCourtRules(), teams: BySide(a: .home, b: .away)).drawsRounds)
    }

    @Test func aFriendlyPresetSaysWhatItIs() {
        #expect(friendlyPreset().configuration.summary == "Friendly · 5 players · first to 4")
        #expect(PresetConfiguration.friendly(
            name: "", players: [], rules: TraditionalRules(setsToWin: 2)
        ).summary == "Friendly · 0 players · best of 3")
    }

    @Test func savingReplacesAPresetWithTheSameIdentity() {
        var library = PresetLibrary()
        var preset = tournamentPreset()
        library.save(preset)
        preset.name = "Renamed"
        library.save(preset)

        #expect(library.presets.count == 1)
        #expect(library.presets[0].name == "Renamed")
    }

    @Test func theOneYouUsedLastComesFirst() {
        var library = PresetLibrary()
        let old = tournamentPreset("Old")
        let recent = tournamentPreset("Recent")
        library.save(old)
        library.save(recent)

        library.markUsed(old.id, at: Date(timeIntervalSince1970: 100))
        library.markUsed(recent.id, at: Date(timeIntervalSince1970: 200))

        #expect(library.ordered.map(\.name) == ["Recent", "Old"])
    }

    @Test func unusedPresetsFallBackToAlphabeticalOrder() {
        var library = PresetLibrary()
        library.save(tournamentPreset("Zebra"))
        library.save(tournamentPreset("Alpha"))
        #expect(library.ordered.map(\.name) == ["Alpha", "Zebra"])
    }

    @Test func theNewerLibraryWinsWholesale() {
        var mine = PresetLibrary()
        mine.save(tournamentPreset("Mine"), at: Date(timeIntervalSince1970: 100))

        var theirs = PresetLibrary()
        theirs.save(tournamentPreset("Theirs"), at: Date(timeIntervalSince1970: 200))

        #expect(mine.adopting(theirs).presets.map(\.name) == ["Theirs"])
        #expect(theirs.adopting(mine).presets.map(\.name) == ["Theirs"], "a stale copy does not win")
    }

    @Test func aDeletionIsNotResurrectedByAStaleCopy() {
        var phone = PresetLibrary()
        let preset = tournamentPreset()
        phone.save(preset, at: Date(timeIntervalSince1970: 100))
        let watchCopy = phone

        phone.remove(preset.id, at: Date(timeIntervalSince1970: 200))

        #expect(watchCopy.adopting(phone).isEmpty, "the watch takes the deletion")
        #expect(phone.adopting(watchCopy).isEmpty, "and does not get it back")
    }

    @Test func survivesARoundTripThroughTheStore() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "rekkert-presets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)

        #expect(store.loadPresets().isEmpty)

        var library = store.loadPresets()
        library.save(tournamentPreset())
        try store.save(library)

        #expect(store.loadPresets().presets.map(\.name) == ["Thursday"])
    }
}

@Suite("Display preferences")
struct DisplayPreferenceTests {
    @Test func settingOneLeavesTheOtherAlone() {
        let flipped = DisplayPreferences().setting(mirrored: true)
        let both = flipped.setting(colorsSwapped: true)

        #expect(both.isMirrored, "the flip survives the colour swap")
        #expect(both.areColorsSwapped)
        #expect(both.revision == 2, "and each change is its own revision")
    }

    @Test func aStoredValueFromBeforeTheColourSwapStillReads() throws {
        let legacy = #"{"isMirrored":true,"revision":4,"updatedAt":0}"#
        let decoded = try JSONCoding.decoder.decode(DisplayPreferences.self, from: Data(legacy.utf8))

        #expect(decoded.isMirrored)
        #expect(decoded.revision == 4)
        #expect(decoded.areColorsSwapped == false, "defaulting to the colours it was drawn in")
    }

    @Test func theNewerRevisionWinsWhicheverFieldChanged() {
        let mine = DisplayPreferences().setting(mirrored: true)
        let theirs = mine.setting(colorsSwapped: true)

        #expect(mine.adopting(theirs) == theirs)
        #expect(theirs.adopting(mine) == theirs)
    }
}
