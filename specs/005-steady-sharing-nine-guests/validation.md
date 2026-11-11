# Validation: Steadier, Measurable Sharing for Two Full Courts

**Feature**: [spec.md](spec.md) · **Steps**: [quickstart.md](quickstart.md) · **Tasks**: [tasks.md](tasks.md)

## Baseline

On `e6b11594`, before any change (T001):

| Check | Result |
|---|---|
| `swift test --package-path Packages/RekkertKit`, local (Apple Swift 6.4.2, macOS 27.2) | Pass. 817 core tests in 71 suites, and every sync suite. 2 min 25 s wall clock |
| `twoCourtsSevenGuestsHalfAnHour` | Pass, 82.3 s local. CI on `main`, run 42770464561 (2026-11-10): 155.5 s |
| `deliveryDoesNotSnowball` | Pass, 50.3 s local. CI, same run: 101.5 s |
| RekkertSync suites, CI | 271 s. Whole job about 8 min of its 60 min limit |
| `scripts/verify.sh` | Not re-run locally for the baseline. The latest CI run on `main` (run 42770464561), which runs it, is green |

## After Phase 2

| Check | Result |
|---|---|
| Whole package, local | Pass. 557 sync tests in 82 suites, and 826 core tests in 72 suites, including the 9 new `ArrivalConditions` tests. 1 min 38 s wall clock |
| `twoCourtsSevenGuestsHalfAnHour`, local | Pass, 74.4 s (baseline 82.3 s) |
| `deliveryDoesNotSnowball`, local | Pass, 44.8 s (baseline 50.3 s) |
| New harness tests | Pass: two links per guest, a guest on the Wi-Fi stand-in alone, per-device arrivals, a point that never arrives, idle skipping |

## Simulated results

| Suite | Result |
|---|---|
| Fails on today's code? (T015) | Yes, on every device. 95th percentile 1.0–7.3 s, slowest 13–83 s, with second links dropping 64–69 times an hour |
| `NoEchoTests`, `LinkChangeTrafficTests` on today's code | Fail for the stated reasons: the host heard its own points back, and a second link dropping ran rounds of `synchronise()` |
| `BusyHallTests` after User Story 1 (T022) | Passes, with FR-010's own numbers recorded as known issues until calibration (T059). Host: 95th percentile 0.95 s, slowest 1.55 s. Guests whose second link drops every minute: 95th percentile 1.25–1.35 s, slowest 1.9 s. One-link guests (Bluetooth only, Wi-Fi stand-in only): 95th percentile 1.3–1.4 s, slowest 12–15 s. FR-008 holds: a dropping second link costs its guest no time against a guest on one link |
| Harness change found on the way (R-8) | The stores' and fan-out's waits now run on the radio's clock in the harness, at the app's own timings (6 s send timeout, 4 s retry, 1 s participant tick). On real time they stretched whenever the machine was busy, which made `deliveryDoesNotSnowball` fail under load and hid the 1-second delays. Busy-hall losses are now link-layer re-sends, which arrive late, not never |
| `ClockOffsetTests` on D-2 as first planned (T043) | Every recorded delay within 0.1 s of the truth, but 62–90% unknown on every device, against FR-006's 10%. Clocks timed on pushes: no radio round trip under 130 ms, most 200–240 ms, so one hop was ±65–120 ms and guest to guest ±140–170 ms. Watches knew no clock but their phone's |
| `ClockOffsetTests` with the small `clock` exchange (D-2, revised) | Passes, with the cap now asserted. One hop ±21 ms, guest to guest ±42–49 ms. Unknown: 0–2 of 135 on each phone, 9–10 of 135 on each watch. Each watch's delays reach its phone's record and summary once the two are back in touch (FR-005). A clock set 5 s forward mid-run gives unknown, never wrong |
| `BusyHallTests` after User Story 2 | Before offsets were made compact, they cost guests 0.3–0.5 s at the 95th percentile. With `ClockSpan`: host 95th percentile 0.89 s, slowest 1.25 s. Guests whose second link drops every minute: 1.26–1.41 s, slowest 1.7–3.3 s. One-link guests: 1.4–1.8 s, with single outliers of 24–49 s on the guessed radio. FR-010's own numbers stay known issues until calibration (T059) |
| Whole package after User Story 2 (T043) | Pass. 582 sync tests in 91 suites with 14 known issues (FR-010's numbers in `BusyHallTests`), and 863 core tests in 75 suites. 4 min 19 s for the sync tests. The first run caught `BusyHallTests`' FR-011 share failing on 2 late arrivals out of 5. That share is held with FR-010's numbers until calibration (T077, after convergence T079 took out a 20-arrival minimum the spec does not have), and every such arrival must still come within 30 s |
| `OlderGuestTests`, `RecordPrivacyTests`, `DropDetailTests` | Pass. A guest acting as 1.1 is counted once, gets every point, and its delays read `unknown; older`. No export holds a name, the code or a score, and every drop detail is from the fixed set |
| `WristFullTests` on today's code (T045) | Failed both ways. The phone says "joined" when its radio link comes up, before the host has counted it, and the wrist took that as its answer; the host's `noRoom` 350 ms later was then ignored, and the search's own deadline turned the phone's "no room" into "not found" at 14.7 s |
| `WristFullTests`, `LimitReachesWatchTests` after T049–T050 | Pass. A wrist join on a full match ends as "no room" within 2 s, whether the phone heard it or the wrist did with the phone out of the host's reach, and never as "not found". The host's watch holds the limit and the count; a guest turned away holds the limit on phone and wrist |
| `twoCourtsFullHalfAnHour` at 7 guests, busy hall, guessed speed (T047) | Everybody on, in step at every check, and one guest too many refused within 15 s. FR-010 and FR-011 held as known issues: on the guessed busy-hall speed, guests' 95th percentile was 5.2–8.8 s and the host's 2.15 s, and one guest had 2 of 5 late arrivals past 30 s. 233 s to run. This is the shape of T061's prediction, and the reason it must run on calibrated speeds |
| `twoCourtsFullHalfAnHourOnAQuietRadio` | Spec 001's test, kept and parameterised on the limit. Passes: 95% within 5 s, all within 30 s. 47 s |
| `BatteryNoteTests` (T054) | Pass. A reading when sharing starts or stops, a join or a leave, otherwise at most every 10 minutes, with or without sharing |
| `CalibrationFitTests` (T056) | Pass. A record written by the harness at 25 ms and 3,000 B/s replays within 25% at the 95th percentile (0.99 s against 1.18 s). The fitted latency and speed differ from the ones that wrote it (78 ms, 18,609 B/s): the fastest points carry transfer time too, so the two trade off. T060's calibration should be read with that in mind |
| `scripts/verify.sh` after User Story 3 and T054–T056 (T053, T068) | All checks passed. 593 sync tests in 95 suites with 46 known issues, all of them FR-010's or FR-011's numbers on guessed radio speeds, and 866 core tests. The sync tests took 6 min locally, so the CI job stays well under 30 minutes and is not split |
| New Info.plist keys or entitlements (T070) | None. Battery level needs no key, and nothing else asked for one |
| Convergence (T071–T085) | Thirteen of fifteen done; T076 and T077 wait on calibration (T060). Links that end by timing out now count as drops in the summary and as down in the arrival rule. A Wi-Fi link that lost its path says `path unsatisfied` when it ends. A guest turned away on the phone is told on the wrist too, with the limit. A host's `needsUpdate` reads "Update Rekkert to join" on phone and watch. The calibration replays the record's own taps and absences, and fitted a known 3,000 B/s back as 3,308 B/s. A watch standing in is judged on its own link to the host: 95th percentile 1.1 s against 0.9 s for a guest's phone. New tests for a 1.1 host, a two-hour record, and the radio a join got through on. `scripts/verify.sh` passes: 602 sync tests with 54 known issues, 869 core tests. The first runs failed five real-time tests in other suites, every time: the two-hour record test wrote 1,200 entries on the main actor without a break, holding it for about 3 s. It now yields as it writes |
| `scripts/share.sh` (T069) | Not run to the end. On this Mac on 10 Nov the guest's Bonjour browse saw nothing in 10 s and the join failed at its first check, though the host's listener was ready and its service type was registered. `main`, built without this feature, fails at the same check, so it is the simulators' local network here. T069 stays open: the screens are still to be checked against contracts/screens.md |

## Level 4: small field run

| | |
|---|---|
| Date, place | _ |
| Devices (model, iOS/watchOS, build) | _ |
| Wi-Fi on (unjoined) | _ |
| Length, points | _ |

| Check | Requirement | Result |
|---|---|---|
| Points within 1 s / 2 s, per device | FR-010, SC-002 | _ |
| Share unknown, per device | FR-006 | _ |
| Drops per guest per hour | FR-007, SC-003 | _ |
| Drop details | D-7 | _ |
| Back after the burst | FR-011 | _ |
| Battery per hour, with and without sharing | FR-019, SC-005 | _ |
| Venue Wi-Fi segment | Edge Cases | _ |
| Another shared match nearby | Edge Cases | _ |
| Cold read of an export | SC-007 | _ |

## Calibration

| | |
|---|---|
| Fitted `latency`, `bytesPerSecond` | _ |
| Replay 95th percentile against the real one | _ (FR-017: within 25%) |
| Nine-guest prediction (`ClubNightTests.predict(guests: 9)`) | _ |

## Level 5: two-court evening

| Check | Requirement | Result |
|---|---|---|
| Everyone on, "9 of 9 on" | SC-001 | _ |
| Points within 1 s / 2 s on every device | FR-010, SC-002 | _ |
| Prediction error at the 95th percentile | FR-018, SC-006 | _ |
| Battery | SC-005 | _ |
