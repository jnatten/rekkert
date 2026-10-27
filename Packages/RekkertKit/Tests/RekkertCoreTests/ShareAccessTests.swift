import Foundation
import Testing
@testable import RekkertCore

@Suite("What each phone on a shared match may do")
struct ShareAccessTests {
    private let phone = DeviceID()
    private let watch = DeviceID()

    @Test func eachLevelAllowsWhatItSays() {
        #expect(!ShareAccess.readOnly.canScore)
        #expect(!ShareAccess.readOnly.canRunRounds)
        #expect(ShareAccess.score.canScore)
        #expect(!ShareAccess.score.canRunRounds)
        #expect(ShareAccess.full.canScore)
        #expect(ShareAccess.full.canRunRounds)
    }

    @Test func aScorerTakesBackScoresButNotRounds() {
        #expect(ShareAccess.score.mayUndo(.point(round: 0, court: 0, team: .a)))
        #expect(ShareAccess.score.mayUndo(.setScore(round: 0, court: 0, points: BySide(a: 3, b: 1))))
        #expect(!ShareAccess.score.mayUndo(.nextRound(after: 0)))
        #expect(!ShareAccess.score.mayUndo(.endRound(round: 0)))
        #expect(!ShareAccess.score.mayUndo(.setRoundConfirmed(round: 0, isConfirmed: true)))
        #expect(!ShareAccess.readOnly.mayUndo(.point(round: 0, court: 0, team: .a)))
        #expect(ShareAccess.full.mayUndo(.nextRound(after: 0)))
    }

    @Test func anOverrideBeatsTheDefaultAndClearingItGoesBack() {
        let table = ShareAccessTable(standard: .score)
        #expect(table.access(for: [phone]) == .score)

        let overridden = table.setting(.readOnly, for: phone)
        #expect(overridden.access(for: [phone]) == .readOnly)
        #expect(overridden.access(for: [DeviceID()]) == .score, "nobody else's")

        let cleared = overridden.setting(nil, for: phone)
        #expect(cleared.access(for: [phone]) == .score)
        #expect(cleared.overrides.isEmpty)
    }

    @Test func aWatchGoesByItsPhone() {
        let table = ShareAccessTable(standard: .full).setting(.readOnly, for: phone)
        #expect(table.access(for: [watch, phone]) == .readOnly)
        #expect(table.access(for: [watch, nil]) == .full)
    }

    @Test func everyChangeIsNewer() {
        let table = ShareAccessTable(standard: .full)
        let changed = table.with(standard: .score)
        #expect(changed.supersedes(table))
        #expect(!table.supersedes(changed), "an older one arriving late changes nothing")
        #expect(!changed.supersedes(changed))
        #expect(table.supersedes(nil))
    }

    @Test func theHostsNameTravelsWithTheTableAndIsNewer() throws {
        let table = ShareAccessTable(standard: .full)
        let named = table.with(hostName: "Ada")
        #expect(named.supersedes(table))
        #expect(named.with(hostName: "Ada") == named, "the same name again is no change")
        #expect(try Wire.decode(Wire.access(named).encoded()) == .access(named))
    }

    /// A host from before names travelled sends a table without one, and it still reads.
    @Test func aTableWithoutANameStillReads() throws {
        let older = Data(#"{"id":"\#(UUID().uuidString)","revision":2,"standard":"score","overrides":[]}"#.utf8)
        let table = try JSONCoding.decoder.decode(ShareAccessTable.self, from: older)
        #expect(table.hostName == nil)
        #expect(table.standard == .score)
    }

    @Test func aFreshShareIsNotRefusedAsOlder() {
        let old = ShareAccessTable(standard: .full).with(standard: .score).with(standard: .readOnly)
        let fresh = ShareAccessTable(standard: .full)
        #expect(fresh.supersedes(old))
    }

    @Test func equalTablesEncodeToEqualBytes() throws {
        let other = DeviceID()
        let base = ShareAccessTable(id: UUID(), standard: .full)
        let one = base.setting(.score, for: phone).setting(.readOnly, for: other)
        let two = base.setting(.readOnly, for: other).setting(.score, for: phone)
        #expect(try JSONCoding.encoder.encode(one) == JSONCoding.encoder.encode(two))
    }

    @Test func bothMessagesRoundTrip() throws {
        let table = ShareAccessTable(standard: .score).setting(.readOnly, for: phone)
        #expect(try Wire.decode(Wire.access(table).encoded()) == .access(table))
        let card = GuestCard(device: phone, name: "Ada")
        #expect(try Wire.decode(Wire.guestCard(card).encoded()) == .guestCard(card))
    }

    @Test func aSessionSavedBeforeAccessStillLoads() throws {
        let saved = Data(#"{"log":\#(String(decoding: try JSONCoding.encoder.encode(MatchLog()), as: UTF8.self)),"outbox":{"pending":[]},"role":"guest"}"#.utf8)
        let session = try JSONCoding.decoder.decode(ActiveSession.self, from: saved)
        #expect(session.access == nil)
        #expect(session.guests.isEmpty)
        #expect(session.identity == nil)
    }

    @Test func theRememberedDefaultSurvivesARelaunch() throws {
        let store = SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        #expect(store.loadShareAccess() == .full, "nothing said yet is today's behaviour")
        try store.save(ShareAccess.readOnly)
        #expect(store.loadShareAccess() == .readOnly)
    }

    @Test func everyModeNamesItsPlayers() {
        let traditional = SessionState.traditional(TraditionalSession(
            rules: TraditionalRules(),
            teams: BySide(a: TeamInfo(name: "Us", players: ["Ada", "Bob"]), b: TeamInfo(name: "Them", players: ["Cy"]))
        ))
        #expect(traditional.playerNames == ["Ada", "Bob", "Cy"])

        let nobody = SessionState.traditional(TraditionalSession(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
        #expect(nobody.playerNames.isEmpty)
    }
}
