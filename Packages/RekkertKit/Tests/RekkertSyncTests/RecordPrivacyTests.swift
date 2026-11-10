import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

/// Spec 005, FR-004: the record's new lines hold seconds, percentages, radios and short codes,
/// never a player's name, the code or a score.
@Suite("Nothing personal in the record", .serialized)
@MainActor
struct RecordPrivacyTests {
    @Test func anExportedRecordHoldsNoNameCodeOrScore() async {
        let names = ["Ada", "Bob", "Cy", "Di", "Eli", "Fay", "Gus", "Hal"]
        let court = CourtHarness(guests: 2, guestRadios: { _ in .both })
        court.startMatch(.tournament(Tournament(
            name: "Thursday", format: .americano,
            players: names.map { Player(name: $0) },
            config: TournamentConfig(pointRules: PointCountRules(target: 32), courtCount: 2)
        )))
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(90)) { court.allInStep() })
        for index in 0 ..< 20 {
            court.score(on: court.devices[index % court.devices.count], court: index % 2)
            await court.run(for: .seconds(5))
        }
        court.guests.first!.phone.wifiRadio!.walkAway()
        await court.run(for: .seconds(5))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let allowed = DropDetail.all.union(["older"])
        for player in court.players {
            let record = player.phone.recorder.read()
            let text = record.export(
                LinkRecord.Header(app: "1.2 (80)", phoneSystem: "iOS 27.0", phone: player.phone.id),
                now: court.wallClock, in: calendar
            )
            #expect(text.contains("pointArrived("), "\(player.phone.name) recorded no delays")
            for name in names { #expect(!text.contains(name), "\(player.phone.name): \(name)") }
            #expect(!text.contains(court.code.description.filter(\.isNumber)), "\(player.phone.name): the code")
            #expect(record.entries.allSatisfy { $0.detail.map(allowed.contains) ?? true })
        }
    }
}
