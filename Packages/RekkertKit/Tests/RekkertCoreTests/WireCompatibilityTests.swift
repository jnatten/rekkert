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

/// Spec 005, contracts/wire-protocol.md: every change is an optional field, so 1.1 reads what
/// this release sends and this release reads what 1.1 sends.
@Suite("The wire stays readable both ways")
struct WireAcrossVersionsTests {
    /// The cases as 1.1 declares them, to decode with the synthesised rules 1.1 itself uses.
    private enum OlderWire: Codable {
        case hello(sessionID: UUID, vector: VersionVector, from: DeviceID? = nil)
        case events(sessionID: UUID, events: [MatchEvent])
        case noRoom(sessionID: UUID)
    }

    private struct OlderHostingStatus: Codable {
        var isSharing: Bool
        var participants: [ParticipantSummary]
        var canShare: Bool
    }

    private struct OlderGuestCard: Codable {
        var device: DeviceID
        var name: String?
        var pairedTo: DeviceID?
        var leaving: Bool?
    }

    private let session = UUID()
    private let device = DeviceID()
    private let clock = Date(timeIntervalSince1970: 1_800_000_000.25)

    @Test func aHelloWithAClockAndProtocolRoundTrips() throws {
        let hello = Wire.hello(sessionID: session, vector: VersionVector(), from: device, clock: clock, protocol: Wire.sharingProtocol)
        #expect(try Wire.decode(hello.encoded()) == hello)
    }

    @Test func olderBuildsReadTheNewHello() throws {
        let hello = Wire.hello(sessionID: session, vector: VersionVector(), from: device, clock: clock, protocol: 2)
        guard case .hello(let id, _, let from) = try JSONCoding.decoder.decode(OlderWire.self, from: hello.encoded()) else {
            Issue.record("not a hello")
            return
        }
        #expect(id == session)
        #expect(from == device)
    }

    @Test func thisBuildReadsAnOlderHello() throws {
        let older = try JSONCoding.encoder.encode(OlderWire.hello(sessionID: session, vector: VersionVector(), from: device))
        #expect(try Wire.decode(older) == .hello(sessionID: session, vector: VersionVector(), from: device))
    }

    @Test func eventsWithOffsetsRoundTripAndOlderBuildsReadThem() throws {
        let offsets = [device: ClockSpan(lower: 100, upper: 140)]
        let events = Wire.events(sessionID: session, events: [], offsets: offsets)
        #expect(try Wire.decode(events.encoded()) == events)
        guard case .events(let id, _) = try JSONCoding.decoder.decode(OlderWire.self, from: events.encoded()) else {
            Issue.record("not events")
            return
        }
        #expect(id == session)
    }

    @Test func thisBuildReadsOlderEvents() throws {
        let older = try JSONCoding.encoder.encode(OlderWire.events(sessionID: session, events: []))
        #expect(try Wire.decode(older) == .events(sessionID: session, events: []))
    }

    @Test func aGuestCardCarriesItsProtocolAndOlderBuildsReadIt() throws {
        let card = GuestCard(device: device, name: "Ada", protocol: 2)
        let data = try JSONCoding.encoder.encode(card)
        #expect(try JSONCoding.decoder.decode(GuestCard.self, from: data) == card)
        #expect(try JSONCoding.decoder.decode(OlderGuestCard.self, from: data).name == "Ada")
        let older = try JSONCoding.encoder.encode(OlderGuestCard(device: device, name: "Ada"))
        #expect(try JSONCoding.decoder.decode(GuestCard.self, from: older).protocol == nil)
    }

    @Test func needsUpdateRoundTrips() throws {
        let wire = Wire.needsUpdate(sessionID: session)
        #expect(try Wire.decode(wire.encoded()) == wire)
    }

    @Test func noRoomSaysHowManyFitAndOlderBuildsReadIt() throws {
        let wire = Wire.noRoom(sessionID: session, limit: 9)
        #expect(try Wire.decode(wire.encoded()) == wire)
        guard case .noRoom(let id) = try JSONCoding.decoder.decode(OlderWire.self, from: wire.encoded()) else {
            Issue.record("not noRoom")
            return
        }
        #expect(id == session)
        let older = try JSONCoding.encoder.encode(OlderWire.noRoom(sessionID: session))
        #expect(try Wire.decode(older) == .noRoom(sessionID: session))
    }

    @Test func theHostsWatchHearsTheLimitAndOlderBuildsReadIt() throws {
        let status = HostingStatus(isSharing: true, canShare: true, limit: 9)
        let data = try JSONCoding.encoder.encode(status)
        #expect(try JSONCoding.decoder.decode(HostingStatus.self, from: data) == status)
        #expect(try JSONCoding.decoder.decode(OlderHostingStatus.self, from: data).isSharing)
        let older = try JSONCoding.encoder.encode(OlderHostingStatus(isSharing: true, participants: [], canShare: true))
        #expect(try JSONCoding.decoder.decode(HostingStatus.self, from: older).limit == nil)
    }

    @Test func aClockQuestionAndAnswerRoundTrip() throws {
        #expect(try Wire.decode(Wire.clock().encoded()) == .clock())
        #expect(try Wire.decode(Wire.clock(reading: clock).encoded()) == .clock(reading: clock))
    }

    /// One radio chunk each way is the point of it: Bluetooth's smallest carries 20 bytes, a
    /// negotiated one 180 and more.
    @Test func aClockQuestionAndAnswerAreSmall() throws {
        #expect(try Wire.clock().encoded().count <= 40)
        #expect(try Wire.clock(reading: Date()).encoded().count <= 60)
    }

    @Test func offsetsTravelAsTwoWholeMillisecondsEach() throws {
        let data = try JSONCoding.encoder.encode([device: ClockSpan(lower: -2_701, upper: -2_690)])
        #expect(String(decoding: data, as: UTF8.self).contains("[-2701,-2690]"))
    }
}
