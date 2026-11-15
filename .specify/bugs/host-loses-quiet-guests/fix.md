# Bug Fix: The host marks guests out of reach between points, though their links are up

- **Slug**: host-loses-quiet-guests
- **Fixed**: 2026-11-15
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The host no longer waits for a quiet guest to speak up.

- **The host asks.** After 12 s without hearing a guest, and with nothing already on its way to it, the host asks the guest something on one of its links, Bluetooth first. A guest on this build is asked the time; a guest on 1.1 is sent a hello. Its answer counts as hearing it.
- **Clock answers count.** Any answer to the host asking the time now counts as hearing that guest.

A guest whose phone is in a bag is heard again between points. That includes a guest on 1.1, which answers a hello like every build.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift` | modified | `askQuietGuests()` runs on the host's once-a-second participant check. `heardAnswer(on:)` counts a clock answer as hearing the guest. A test-only counter, `quietGuestsAsked` |
| `Packages/RekkertKit/Tests/RekkertSyncTests/QuietGuestTests.swift` | added test | Shaped like 14 Nov: the host's watch scores every 20 s, one guest on this build and one acting as 1.1, and no guest taps anything |
| `Packages/RekkertKit/Tests/RekkertSyncTests/Wakefulness.swift` | added | The harness's phone in a bag. Each event on its radio wakes it for 10 s, and its timers and waits are held until the next wake meanwhile |
| `Packages/RekkertKit/Tests/RekkertSyncTests/SimulatedRadio.swift` | modified | A radio wakes its device on every event it delivers, and its timers run through that device's `Wakefulness` |
| `Packages/RekkertKit/Tests/RekkertSyncTests/CourtHarness.swift` | modified | Each `Device` has a `Wakefulness`, and its stores' waits go through it. A device never put in a bag behaves as before |
| `scripts/package-tests.sh` | modified | `QuietGuestTests` joins the long court simulations that run on their own |
| `README.md` | modified | "How syncing works": the host asks a guest it hasn't heard from for twelve seconds |

## Diff Highlights

```swift
private func askQuietGuests() {
    let moment = now()
    for participant in participants.all {
        let asked = quietGuestAskedAt[participant.id].map { moment.timeIntervalSince($0) } ?? .infinity
        guard moment.timeIntervalSince(participant.lastHeard) >= Self.quietGuestWait, asked >= Self.quietGuestWait else { continue }
        let links = farEnds.filter { participant.devices.contains($0.value) && !departedLinks.contains($0.key) }
        guard !links.keys.contains(where: { !(delivering[$0]?.isEmpty ?? true) }),
              let (link, far) = links.first(where: { linkRadios[$0.key] != .wifi }) ?? links.first
        else { continue }
        ...
        Task {
            if currentDevices.contains(far) { return await askTheTime(on: link) }
            guard let payload = try? ownHello.encoded(), let reply = await sendLive(payload, on: link) else { return }
            handle(InboundPacket(payload: reply, link: link))
        }
    }
}
```

- **12 s, not 10.** A guest whose app is running says hello by itself after 10 quiet seconds, so the host only asks the guests that can't, such as a phone in a bag. It still leaves 3 s for the answer before the 15 s limit.
- **The smallest question the guest understands.** A guest on this build gets the one-chunk `clock` question, which also gives the host a clock sample. A 1.1 guest gets a hello, since it must never be sent `clock` (wire-protocol contract).
- **Nothing on its way.** No asking while a push of points to that guest is still in flight: its answer will say the guest is there. Without this rule, a backed-up Bluetooth queue made guests look quiet, the host asked them, and the queue backed up further.
- **Bluetooth first.** Links are tried in the order "not Wi-Fi" first, not "labelled Bluetooth". A real Bluetooth link has no radio label until `BluetoothTransport` passes `radio(of:)` on (a separate bug, found in the same game). Bluetooth is what wakes a phone in a bag.

## Tests Added or Updated

- **`QuietGuestTests.guestsThatOnlyFollowAreNeverOutOfReach(radios:)`**, on Bluetooth and on both radios, with phones running freely. Neither guest goes out of reach over 15 points 20 s apart. This passes on the old code too, and stays as a check that phones running freely don't flicker.
- **`QuietGuestTests.guestsWithTheirPhonesInABagAreNeverOutOfReach`**, with both guests' phones in a bag.
  - **Old code: failed.** The guest on this build went out of reach 10 times and the guest acting as 1.1 15 times, in 15 points. That is the field's pattern: out of reach about 15.9 s after each point, and back at the next.
  - **With the fix:** neither goes out of reach.
- **`QuietGuestTests.aQuietBreakKeepsEveryoneInReachWithoutFloodingTheRadio`**: phones in a bag, two minutes with nobody scoring.
  - **Old code: failed**, with 4 and 1 times out of reach.
  - **With the fix:** nobody goes out of reach, and the host asks each guest at most once every 12 s (at most 20 asks for 2 guests).
- **Real absences:** `WhoIsOnTests.theHostSeesAGuestGoAndComeBack` and `aGuestOutOfRangeIsTheLinkBetweenItAndTheHost` still say a guest that has gone is out of reach within 15 s.

## Local Verification

- **`QuietGuestTests`.** Before the fix, with the bag model: 2 of 3 failed, as above. After: 3 of 3 pass.
- **`scripts/package-tests.sh`** with the first version of the fix (10 s, a hello to everyone): all passed. 592 sync tests in 101 suites and 869 core tests, then 14 long tests with 56 known issues.
- **Final version (in-flight rule, debug print removed):**
  - everything but the long simulations: passed, 592 sync tests in 101 suites and 869 core tests;
  - `QuietGuestTests`: 3 of 3 pass, 50 s.

  The long simulations last ran with this version in the club-night runs below. `BusyHallTests` last ran with the version just before the in-flight rule, which only ever asks less.

### The cost to FR-010's numbers

FR-010's numbers in `BusyHallTests` and `ClubNightTests` are recorded as known issues, so a pass does not show they held. The commit before the fix was run beside the fix for comparison.

**Busy hall**, p95 per guest:

| Run | host | guest1 | guest2 | guest3 | guest4 | Known issues |
|---|---|---|---|---|---|---|
| Before, run 1 | 0.75 | 1.21 | 1.35 | 1.80 | 1.30 | 14 |
| Before, run 2 | 0.91 | 1.36 | 1.45 | 1.70 | 1.40 | 14 |
| First fix (10 s, a hello to everyone) | 0.80 | 1.32 | 1.40 | 2.41 | 1.45 | 18 |
| Final fix (12 s, the time or a hello), before the in-flight rule | 0.80 | 1.31 | 1.40 | 1.60 | 1.40 | 14 |

The final fix is within the spread of the two runs before.

**Club night**, the 30-minute test, mean guest p95:

| Run | Mean guest p95 | Slowest | Host asks | Known issues | Notes |
|---|---|---|---|---|---|
| Before, run 1 | 3.07 s | 7.7 s | — | 30 | |
| Before, run 2 | 6.32 s | 48 s | — | 40 | run beside another simulation |
| First fix | 6.4 s | 33 s | not counted | 38 | |
| Final fix, no in-flight rule | 6.05 s | 20 s | not counted | 36 | |
| Final fix, run 1 | 3.90 s | 14.7 s | 6 | 36 | |
| Final fix, run 2 | 7.30 s | 54 s | 14 | 42 | `inStepAtEveryCheck` failed; run beside another simulation |
| Final fix, run 3 | 6.82 s | 33 s | 17 | 40 | run alone |
| Final fix, run 4 | 4.95 s | 23 s | 5 | 44 | run alone |

What this shows:
- **Club night varies too much between runs to show a cost either way.** The same code before the fix gave 3.07 s and 6.32 s. The court harness waits a millisecond or two of real time between radio steps, so how busy the machine is changes the result.
- **The final fix adds little traffic.** It asked 5–17 times in a 30-minute night: too few to move these numbers.
- **One check failed once, unexplained.** `inStepAtEveryCheck` failed in one run of six, a final-fix run sharing the machine with another simulation. The two final-fix runs alone passed. It isn't proven to be noise. Watch it on CI.

## Deviations from Assessment

- **The harness had to model a phone in a bag first.** As the assessment warned, the first version of `QuietGuestTests` passed on the old code, because simulated phones never paused. `Wakefulness` was added (a file the assessment did not list) to model what iOS does with an app in the background on Bluetooth: it runs for a while after each radio event. With it, the old code fails in the field's pattern.
- **The host asks at 12 s with the smallest question, not at 10 s with a hello.** The assessment proposed a hello at 10 s. Measured in the busy hall, that asked every guest between every pair of points, cost up to 0.6 s at the 95th percentile, and added 4 known issues. Each hello answer was also handled like a hello, which sent a guest that was behind its missing points a second time.
- **The in-flight rule is new.** The assessment's "not while a push to them is in flight" is now enforced in code, for the reason above.
- **Part 2 of the root-cause hypothesis is confirmed only in part.** In the harness, a guest on this build with its phone running freely never flickered, so the clock answers did not on their own push its own message past 15 s there. It flickered only with its phone in a bag, less often than the 1.1 guest, as in the field.
- **The guest acting as 1.1 joins from its phone in the test, not from its wrist.** In the harness, joining from the wrist left the watch on the match itself: the host listed only the watch, and the phone never took over. The watch never pauses, so that guest was always heard. Amandus's phone took over within a second. The test joins from the phone to get the same end state.
- **`scripts/package-tests.sh` gained `QuietGuestTests`** among the suites that run on their own. Each case holds the main actor for 15–30 s, which is what the script's comment says such suites are kept apart for.

## Follow-ups

- **`BluetoothTransport.radio(of:)`**: pass it on to `RadioCore`, so Bluetooth links are labelled in real records and the host's "Bluetooth first" is by label rather than by "not Wi-Fi". Needed for FR-002, the summaries' drop counts and `Calibration.measure`.
- **`ClubNightTests` varies too much between runs** for its FR-010 numbers to judge a change by one run (3.1–6.3 s mean guest p95 on the same code). Before calibration (T060) leans on it, look at how much its real-time waits between steps contribute.
- **Joining from the wrist in the harness** leaves the watch on the match and never lets the phone take over (see Deviations). Check that against what the stand-in policy means to do. In the field, the phone took over within a second.
- **Waking the phone over WatchConnectivity** is not modelled in the harness. A watch's message wakes its paused phone on iOS, and `LoopbackTransport` doesn't do that, so in this respect the harness pauses a phone more than iOS would.
- **Field check**: the next TestFlight game with a guest on 1.1 and phones in bags. Count `guest … outOfReach` on the host. It should be near zero, apart from real walk-offs.
- **Records from before this fix** still overstate absences: the summary's "unreachable", `Calibration.measure`'s absences, and `ArrivalConditions`. T060 should not calibrate from them as they are.
