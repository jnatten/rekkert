import Foundation
import Testing
@testable import RekkertCore

@Suite("Notes on a finished session")
struct RecordNoteTests {
    private let record = HistoryRecord(
        title: "Us vs Them",
        state: .traditional(TraditionalSession(rules: TraditionalRules(), teams: BySide(a: .home, b: .away)))
    )

    @Test func aNoteIsTrimmed() {
        #expect(record.noted("  Court 3, windy \n").note == "Court 3, windy")
    }

    @Test func clearingANoteRemovesIt() {
        #expect(record.noted("Court 3").noted("   ").note == nil)
    }

    @Test func renamingKeepsTheNote() {
        let renamed = record.noted("Court 3").renamed(.sides(event: "Club final", teams: BySide(a: .home, b: .away)))
        #expect(renamed.note == "Court 3")
        #expect(renamed.title == "Club final")
    }

    @Test func aNoteSurvivesTheStore() throws {
        let store = SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.directory) }

        try store.archive(record.noted("Court 3, windy"))
        #expect(store.historyRecord(record.id)?.note == "Court 3, windy")
    }

    @Test func aRecordFiledBeforeNotesExistedStillDecodes() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(record.noted("Gone"))) as? [String: Any])
        #expect(json.removeValue(forKey: "note") != nil)
        let decoded = try JSONCoding.decoder.decode(HistoryRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.note == nil)
        #expect(decoded.id == record.id)
    }
}
