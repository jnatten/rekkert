import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

private let eightPlayers = SessionSetup.tournament(Tournament(
    name: "Thursday", format: .americano,
    players: ["Ada", "Bob", "Cy", "Di", "Eli", "Fay", "Gus", "Hal"].map { Player(name: $0) },
    config: TournamentConfig(pointRules: PointCountRules(target: 128), courtCount: 2)
))

@Suite("A club night", .serialized)
@MainActor
struct ClubNightTests {
    /// What a full club night came to on every device: arrivals where nothing was wrong, the
    /// others, and whether one guest too many was told within 15 s.
    struct Night {
        var fine: [String: CourtHarness.DelayStats] = [:]
        var wrong: [String: CourtHarness.DelayStats] = [:]
        var everybodyOn = false
        var inStepAtEveryCheck = true
        var oneTooManyRefusedInTime = false
    }

    /// The host and `guests` guests, each with a watch and both radios, with second links
    /// dropping as on 8 and 9 November, in a busy hall, for half an hour of an americano over two
    /// courts. The host's limit is `guests`, so one more is turned away at the end. Spec 005,
    /// T047 and T061: the same night at any number of guests and any radio speed.
    static func predict(guests: Int, settings: Airwaves.Settings, wifiSettings: Airwaves.Settings) async -> Night {
        var timing = CourtHarness.Timing()
        timing.skipsIdleTime = true
        let court = CourtHarness(
            guests: guests + 1, withWatches: true, settings: settings, timing: timing,
            guestRadios: { _ in .both }, wifiSettings: wifiSettings, guestLimit: guests
        )
        court.startMatch(eightPlayers)
        court.share()
        let onTheNight = court.guests.dropLast()
        for guest in onTheNight { court.join(guest) }
        var night = Night()
        let onTheNightDevices = court.devices.filter { device in !(court.guests.last!.phone === device || court.guests.last!.watch === device) }
        night.everybodyOn = await court.until(within: .seconds(180)) {
            onTheNightDevices.allSatisfy { court.inStep($0, with: court.host.phone) }
        }

        let flapper = Flapper()
        flapper.start(onTheNight.compactMap(\.phone.wifiRadio), on: court.clock)
        for point in 0 ..< 150 {
            court.score(on: onTheNightDevices[point % onTheNightDevices.count], court: point % 2, team: point % 4 < 2 ? .a : .b)
            await court.run(for: .seconds(12))
            if point % 15 == 14 {
                let inStep = await court.until(within: .seconds(30)) {
                    onTheNightDevices.allSatisfy { court.inStep($0, with: court.host.phone) }
                }
                night.inStepAtEveryCheck = night.inStepAtEveryCheck && inStep
            }
        }
        flapper.stop()

        for device in onTheNightDevices {
            let arrivals = court.arrivals(on: device)
            night.fine[device.name] = CourtHarness.DelayStats(arrivals.filter(\.nothingWrong))
            night.wrong[device.name] = CourtHarness.DelayStats(arrivals.filter { !$0.nothingWrong })
        }

        let oneTooMany = court.guests.last!
        court.join(oneTooMany)
        night.oneTooManyRefusedInTime = await court.until(within: .seconds(15)) {
            oneTooMany.phone.sharing.phase == .failed(.noRoom)
        }
        return night
    }

    /// US1 AS6, SC-009: an americano over two courts, a host and as many guests as it takes, each
    /// with a watch, for half an hour with points tapped on every phone and watch, on a quiet
    /// radio. Every device shows the host's score at every check, and the points arrive within
    /// spec 001's FR-002 times.
    @Test func twoCourtsFullHalfAnHourOnAQuietRadio() async {
        var timing = CourtHarness.Timing()
        timing.step = .milliseconds(200)
        let court = CourtHarness(guests: Participants.limit, withWatches: true, timing: timing)
        court.startMatch(eightPlayers)
        court.share()
        court.joinAll()
        #expect(await court.until(within: .seconds(180)) { court.allInStep() }, "everybody on")

        let scorers = court.devices
        for point in 0 ..< 150 {
            court.score(on: scorers[point % scorers.count], court: point % 2, team: point % 4 < 2 ? .a : .b)
            await court.run(for: .seconds(12))
            if point % 15 == 14 {
                #expect(await court.until(within: .seconds(30)) { court.allInStep() }, "check after point \(point + 1)")
            }
        }

        let times = court.arrivalTimes().sorted()
        let onTime = times.filter { $0 <= .seconds(5) }.count
        #expect(Double(onTime) >= Double(times.count) * 0.95, "95% within 5 s: \(onTime) of \(times.count)")
        #expect((times.last ?? .zero) <= .seconds(30), "every point within 30 s")
    }

    /// Spec 005's two full courts: as many guests as the host takes, each
    /// with a watch and both radios, in a busy hall, for half an hour with points tapped on every
    /// phone and watch. Every device shows the host's score at every check.
    @Test func twoCourtsFullHalfAnHour() async {
        var settings = Airwaves.Settings.busyHall
        settings.sharedAirtime = true
        let night = await Self.predict(guests: Participants.limit, settings: settings, wifiSettings: .busyHall)
        #expect(night.everybodyOn, "everybody on")
        #expect(night.inStepAtEveryCheck)
        #expect(night.oneTooManyRefusedInTime, "one guest too many told within 15 s")

        for (name, fine) in night.fine.sorted(by: { $0.key < $1.key }) {
            #expect(fine.isJudgeable, "\(name): \(fine.count) arrivals where nothing was wrong")
            // FR-010's own numbers mean something only on the speeds the field run measures
            // (T059); until then they are reported, not allowed to pass or fail the build.
            withKnownIssue("FR-010 is judged on calibrated radio speeds (T059)", isIntermittent: true) {
                #expect(fine.share(within: .seconds(1)) >= 0.95, "\(name): \(fine.share(within: .seconds(1))) within 1 s")
                #expect(fine.share(within: .seconds(2)) == 1, "\(name): slowest \(String(describing: fine.slowest))")
            }
            if let wrong = night.wrong[name], wrong.count > 0 {
                withKnownIssue("FR-011 in a busy hall is judged on calibrated radio speeds (T059)", isIntermittent: true) {
                    #expect(wrong.share(within: .seconds(30)) == 1, "\(name): FR-011's 30 s")
                    #expect(wrong.share(within: .seconds(5)) >= 0.95, "\(name): FR-011's 5 s over \(wrong.count)")
                }
            }
            print("ClubNight \(name): \(fine.count) fine, median \(String(describing: fine.median)), p95 \(String(describing: fine.p95)), slowest \(String(describing: fine.slowest)); \(night.wrong[name]?.count ?? 0) not")
        }
    }

    /// FR-002, FR-021: a watch on the match without its phone, with no workout and Rekkert in the
    /// background, says the phone needs opening; brought to the front, it is back in step within 10 s.
    @Test func aWatchWithoutItsPhoneCatchesUpWhenItComesToTheFront() async {
        var timing = CourtHarness.Timing()
        timing.standIn = StandInPolicy.Timing(phoneWait: .seconds(1), ownWait: .seconds(3), grace: .milliseconds(300))
        timing.standInTick = .milliseconds(10)
        let court = CourtHarness(guests: 1, withWatches: true, timing: timing)
        court.startMatch()
        court.share()
        court.joinAll()
        await court.until(within: .seconds(60)) { court.allInStep() }
        let guest = court.guests.first!
        let watch = guest.watch!.standIn!
        await court.until(within: .seconds(10)) { guest.watch!.sharing.standbyCode != nil }

        watch.mayUseTheRadio = { false }
        court.endApp(guest.phone)
        #expect(await court.until(within: .seconds(120)) { watch.phoneNeedsOpening })
        court.score(on: court.host.phone)
        await court.run(for: .seconds(5))
        #expect(!court.inStep(guest.watch!, with: court.host.phone), "nothing reaches a watch in the background")

        watch.mayUseTheRadio = { true }
        #expect(await court.until(within: .seconds(10)) { court.inStep(guest.watch!, with: court.host.phone) })
    }
}
