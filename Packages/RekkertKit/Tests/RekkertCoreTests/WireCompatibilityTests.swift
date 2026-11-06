import Foundation
import Testing
@testable import RekkertCore

@Suite("Wire compatibility")
struct WireCompatibilityTests {
    private func roundTrips(_ wire: Wire) throws -> Bool {
        try Wire.decode(wire.encoded()) == wire
    }

    @Test func everyNewMessageRoundTrips() throws {
        let code = SessionCode("482915")!
        let status = HostingStatus(
            isSharing: true, code: code, joinLink: code.joinLink, qr: Data([1, 2, 3]),
            participants: [
                ParticipantSummary(id: DeviceID(), name: "Ada", state: .inStep),
                ParticipantSummary(id: DeviceID(), name: nil, state: .outOfReach(since: Date(timeIntervalSince1970: 1_000))),
            ],
            canShare: true, failure: .noRoom
        )
        #expect(try roundTrips(.sharingStopped(sessionID: UUID())))
        #expect(try roundTrips(.sharing(.hostingStatus(status))))
        #expect(try roundTrips(.sharing(.startHosting)))
        #expect(try roundTrips(.sharing(.stopHosting)))
        #expect(try roundTrips(.sharing(.followPhone)))
        #expect(try roundTrips(.sharing(.state(.failed(.noRoom)))))
        #expect(try roundTrips(.sharing(.standby(SharingStandby(code: code, isThrough: true, share: UUID(), startedAt: Date(timeIntervalSince1970: 2_000))))))
        #expect(try roundTrips(.guestCard(GuestCard(device: DeviceID(), name: "Bob", pairedTo: DeviceID()))))
        #expect(try roundTrips(.snapshot(MatchLog(), role: .guest)))
        #expect(try roundTrips(.snapshot(MatchLog(), role: .guest, access: ShareAccessTable(standard: .score, hostName: "Ada"))))
        #expect(try roundTrips(.sharing(.standby(SharingStandby(code: code, isThrough: true, issuedAt: Date(timeIntervalSince1970: 3_000))))))
        #expect(try roundTrips(.sharingStopped(sessionID: UUID(), reason: .idle)))
        #expect(try roundTrips(.sharing(.hostStoppedSharing(host: "Ada", reason: .idle))))
        #expect(try roundTrips(.sharing(.answered(BetweenMatchesAnswer(session: UUID(), choice: .stay)))))
        #expect(try roundTrips(.sharing(.newMatch(NewMatchNotice(session: UUID(), hostName: "Ada", arrivedAt: Date(timeIntervalSince1970: 4_000))))))
        var ended = status
        ended.endedBy = .idle
        #expect(try roundTrips(.sharing(.hostingStatus(ended))))
    }

    @Test func aCardWithoutLeavingIsAnOrdinaryCard() throws {
        let device = DeviceID()
        let card = try JSONCoding.encoder.encode(Wire.guestCard(GuestCard(device: device, name: "Ada")))
        #expect(!String(decoding: card, as: UTF8.self).contains("leaving"))
        guard case .guestCard(let read) = try Wire.decode(card) else { Issue.record("not a card"); return }
        #expect(read.leaving == nil)
        #expect(try roundTrips(.guestCard(GuestCard(device: device, name: "Ada", leaving: true))))
    }

    @Test func aStopFromAnOlderBuildReadsAsTheHosts() throws {
        let session = UUID()
        let stop = try Wire.sharingStopped(sessionID: session).encoded()
        #expect(!String(decoding: stop, as: UTF8.self).contains("reason"))
        guard case .sharingStopped(let id, let reason) = try Wire.decode(stop) else { Issue.record("not a stop"); return }
        #expect(id == session)
        #expect(reason == nil)
        let told = try Wire.sharing(.hostStoppedSharing(host: "Ada")).encoded()
        guard case .sharing(.hostStoppedSharing(let host, let why)) = try Wire.decode(told) else { Issue.record("not a notice"); return }
        #expect(host == "Ada")
        #expect(why == nil)
        let status = try Wire.sharing(.hostingStatus(HostingStatus(isSharing: false, canShare: true))).encoded()
        #expect(!String(decoding: status, as: UTF8.self).contains("endedBy"))
        guard case .sharing(.hostingStatus(let read)) = try Wire.decode(status) else { Issue.record("not a status"); return }
        #expect(read.endedBy == nil)
    }

    @Test func aCardFromAnOlderBuildStillReads() throws {
        let device = DeviceID()
        let old = try JSONCoding.encoder.encode(Wire.guestCard(GuestCard(device: device, name: "Ada")))
        #expect(!String(decoding: old, as: UTF8.self).contains("pairedTo"))
        guard case .guestCard(let card) = try Wire.decode(old) else { Issue.record("not a card"); return }
        #expect(card.device == device)
        #expect(card.pairedTo == nil)
    }

    @Test func aStandbyFromAnOlderBuildStillReads() throws {
        let code = SessionCode("482915")!
        let old = try JSONCoding.encoder.encode(Wire.sharing(.standby(SharingStandby(code: code, isThrough: false))))
        guard case .sharing(.standby(let standby?)) = try Wire.decode(old) else { Issue.record("not a standby"); return }
        #expect(standby.code == code)
        #expect(standby.share == nil)
        #expect(standby.startedAt == nil)
        #expect(standby.issuedAt == nil)
    }

    @Test func aSnapshotWithoutARoleReadsAsBefore() throws {
        let payload = try Wire.snapshot(MatchLog()).encoded()
        #expect(!String(decoding: payload, as: UTF8.self).contains("role"))
        #expect(!String(decoding: payload, as: UTF8.self).contains("access"))
        guard case .snapshot(_, let role, let access) = try Wire.decode(payload) else { Issue.record("not a snapshot"); return }
        #expect(role == nil)
        #expect(access == nil)
    }

    @Test func aSharingSignalFromANewerBuildFailsToReadRatherThanTrapping() {
        let newer = Data(#"{"sharing":{"somethingNewer":{}}}"#.utf8)
        #expect(throws: (any Error).self) { try Wire.decode(newer) }
    }
}
