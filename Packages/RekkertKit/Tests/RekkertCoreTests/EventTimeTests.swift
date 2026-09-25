import Foundation
import Testing
@testable import RekkertCore

private let phone = DeviceID(UUID(uuidString: "EEEEEEEE-0000-0000-0000-00000000000A")!)
private let noon = Date(timeIntervalSince1970: 1_700_000_000)
private func seconds(_ count: Double) -> Date { noon.addingTimeInterval(count) }

private let setup = SessionSetup.traditional(rules: TraditionalRules(), teams: BySide(a: .home, b: .away))

private func log() -> MatchLog {
    MatchLog(sessionID: UUID(uuidString: "55555555-0000-0000-0000-000000000000")!, createdAt: noon)
}

@Suite("When an event happened")
struct EventTimeTests {
    @Test func anEventWrittenBeforeTimesExistedStillDecodes() throws {
        var value = log()
        let event = value.append(.point(round: 0, court: 0, team: .a), from: phone, at: seconds(5))
        var fields = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(event)) as? [String: Any])
        #expect(fields.removeValue(forKey: "at") != nil)

        let legacy = try JSONCoding.decoder.decode(MatchEvent.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(legacy.id == event.id)
        #expect(legacy.kind == event.kind)
        #expect(legacy.at == nil)
    }

    /// Everything that appends without a time — every test, and an event relayed by an
    /// older build — has to go on meaning exactly the bytes it always did.
    @Test func anEventWithoutATimeEncodesAsItAlwaysDid() throws {
        var value = log()
        let event = value.append(.point(round: 0, court: 0, team: .a), from: phone)
        let fields = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(event)) as? [String: Any])
        #expect(Set(fields.keys) == ["id", "lamport", "kind"])
    }

    @Test func aTimeSurvivesTheTripExactly() throws {
        var value = log()
        value.append(.configure(setup, at: noon), from: phone, at: MatchEvent.stamp(noon))
        value.append(.point(round: 0, court: 0, team: .a), from: phone, at: MatchEvent.stamp(seconds(12.345)))

        let decoded = try JSONCoding.decoder.decode(MatchLog.self, from: JSONCoding.encoder.encode(value))
        #expect(decoded.ordered.map(\.at) == value.ordered.map(\.at))
    }

    @Test func theStampKeepsATenthOfASecond() {
        let stamped = MatchEvent.stamp(seconds(12.345))
        #expect(abs(stamped.timeIntervalSince(seconds(12.3))) < 0.001)
        #expect(MatchEvent.stamp(stamped) == stamped)
    }

    @Test func aTimeCostsAFewBytesAnEvent() throws {
        var bare = log()
        var timed = log()
        for index in 0 ..< 50 {
            let team: TeamSide = index.isMultiple(of: 3) ? .b : .a
            bare.append(.point(round: 0, court: 0, team: team), from: phone)
            timed.append(.point(round: 0, court: 0, team: team), from: phone, at: MatchEvent.stamp(Date()))
        }
        let extra = try JSONCoding.encoder.encode(timed).count - JSONCoding.encoder.encode(bare).count
        #expect(extra <= 50 * 18)
    }

    @Test func thePlayedSpanRunsFromTheFirstEventToTheLast() {
        var value = log()
        value.append(.configure(setup, at: seconds(2)), from: phone, at: seconds(2))
        value.append(.point(round: 0, court: 0, team: .a), from: phone, at: seconds(40))
        value.append(.point(round: 0, court: 0, team: .b), from: phone, at: seconds(75))
        #expect(value.playedSpan == seconds(2) ... seconds(75))
    }

    @Test func aLogWithoutEventTimesFallsBackOnTheOnesItCarries() {
        var value = log()
        value.append(.configure(setup, at: seconds(3)), from: phone)
        value.append(.point(round: 0, court: 0, team: .a), from: phone)
        #expect(value.playedSpan == seconds(3) ... seconds(3))
        #expect(log().playedSpan == nil)
    }

    @Test func anUndonePointDoesNotStretchTheSpan() {
        var value = log()
        value.append(.configure(setup, at: seconds(1)), from: phone, at: seconds(1))
        value.append(.point(round: 0, court: 0, team: .a), from: phone, at: seconds(30))
        let late = value.append(.point(round: 0, court: 0, team: .a), from: phone, at: seconds(90))
        value.append(.undo(late.id), from: phone)
        #expect(value.playedSpan == seconds(1) ... seconds(30))
    }
}
