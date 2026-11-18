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

## An early read: a friendly game, 14 November

Not the small field run (T058). It had a host and two guests, one of them on 1.1. Every point
was tapped on the host's watch, and there was no walk-out burst and no battery comparison. The
records are the host's, B701's and 255B's, exported on 15 November.

| | |
|---|---|
| Date | 2026-11-14, 10:01–12:00 |
| Devices (build) | Host 57FA on 1.2 (76), guest B701 on 1.2 (76), guest 255B on 1.1 (75), each with a watch |
| Length, points | 1 h 59 min, 264 points |

| Check | Requirement | Result |
|---|---|---|
| Drops per guest per hour | FR-007, SC-003 | B701: 48 on Wi-Fi, and 1 on Bluetooth, at the break. 255B: 29 on Wi-Fi. Target 5 |
| Drop details | D-7 | At the host, 153 Wi-Fi drops: 64 `path unsatisfied`, 49 `ECONNRESET`, 27 other, 4 `ETIMEDOUT`, 9 written off by the host's miss counter. Keepalive is not the cause, and the work stops there (research D-7, Finding; T059) |
| Drops cost nothing | FR-008 | Host's phone to B701's phone: typically 0.09 s, 95th percentile 0.24 s, slowest 0.54 s, with its Wi-Fi dropping 48 times an hour |
| Share unknown | FR-006 | Over the 10% cap everywhere: 22% on the host's phone, 37% on B701's, 86% on B701's watch. So FR-010 can't be judged on this game |

The same records found three bugs, fixed since on this branch:
- **The host lost guests between points.** It showed a guest out of reach whenever more than 15 s passed between points, worst for 1.1 guests (`.specify/bugs/host-loses-quiet-guests`).
- **Bluetooth links carried no radio label** in the record (`1540d035`).
- **No phone asked its own watch the time** (`1d9bb934`).

## On court: an Americano, 18 November

Neither the small field run (T058) nor the two-court evening (T065). Nine played on two courts,
but only the host and three guests shared, each with a watch, on three builds, one of them 1.1.
There was no walk-out burst and no hour without sharing, and nothing in the records says whether
phones were in bags. A one-minute share just before (`EB22…`, 17:49–17:50) ended with its match
and is left out. The records are the four phones', exported on 18 November.

| | |
|---|---|
| Date | 2026-11-18, 17:57–19:31 (`1848…`) |
| Devices (build) | Host 57FA on 1.2 (79), guest B701 on 1.2 (79), guest 7729 on 1.2 (78), guest 255B on 1.1 (75), each with a watch |
| Length, points | 1 h 34 min, 403 points arriving on each 1.2 phone |

| Check | Requirement | Result |
|---|---|---|
| Points within 1 s, per phone | FR-010, SC-002 | Met on every 1.2 phone, each judged on over 100 points by the "nothing is wrong" rule: host 135 of 135, B701 99.1% of 231, 7729 99.3% of 268. Typically 0.09 s on the host and 0.15–0.20 s on the guests. The host's slowest was 0.74 s |
| Points within 2 s, per phone | FR-010 | Missed on both 1.2 guests, by the same two points: 2.37 s and 2.54 s on B701, 2.32 s and 2.58 s on 7729, at 18:39:41 and 18:46:58. Each arrived as 7729's watch joined the host to stand in, and the host had it first on a link the watch had not yet named, so it was very likely tapped on that watch before its own link was up. FR-010 looks only at the receiving phone, where nothing was wrong, so both count |
| Share unknown | FR-006 | Host 2.2%, within the cap. Both guests over it as recorded, 26% on B701 and 24% on 7729, so their summaries read `too many unknown`. 80 of B701's 83 and 81 of 7729's 85 are the 1.1 guest's points relayed by the host: each lands about 0.15 s after one of the host's 81 `unknown; older` arrivals from 255B, but the guests write plain `unknown`. Left out as FR-006 says, they are 1.3% and 1.5% |
| Drops cost nothing | FR-008 | Met. On B701, points within 30 s after a Wi-Fi drop: typically 0.17 s, 95th percentile 0.71 s (98 points), against 0.15 s and 0.53 s otherwise. On 7729: 0.15 s and 0.41 s (43), against 0.21 s and 0.52 s |
| Drops per guest per hour | FR-007, SC-003 | B701: 49 on Wi-Fi, none on Bluetooth (14 Nov: 48). 7729: 23 on Wi-Fi and 1 on Bluetooth, and its watch's own link 13 more. 255B: Wi-Fi gave up after 6 drops in its first two minutes, then 8 on Bluetooth, each back within 3–10 s. About 27 an hour across the three. Target 5 |
| Drop details | D-7 | At the host, 119 Wi-Fi drops: 111 `ECONNRESET`, 6 `path unsatisfied`, 1 `ETIMEDOUT`, 1 written off. D-7 stays closed (T059) |
| Watch hops | FR-010a | Met only from B701's watch to its phone: 97% within 1 s, all within 1.7 s (87 hops). Host's watch to phone 60% within 1 s, slowest 16.2 s (183); host's phone to watch 76%, slowest 19.6 s (219). 7729's watch to phone 55%, slowest 4.1 s (44); 7729's phone to watch 14%, typically 12.1 s, slowest 103 s, and 158 of 342 untimed |
| Points on a following watch | FR-011 | Missed on 7729's watch: 52 hops took over 30 s, and a hop is only part of the time from the tap. Its link to its phone dropped about 200 times (125 an hour, against 1–5 on the other pairs), and it stood in 51 times. The host's watch: 94% of 107 timed points within 5 s, slowest 20.1 s |
| A guest on 1.1 | FR-015 | Consistent, not proven. 255B was on from 17:58 to the end, the host had 81 points from it, and never recorded it out of reach. 1.1 notes no arrivals, so the record can't show every point reaching it |
| The summary and the watch's half | FR-003, FR-005, SC-007 | Wrong three ways. 7729's record is cut into 25 stints, one per stand-in join of its watch, none with 100 timed points, so none can be judged. Its unreachable times include watch absences never closed when the watch stood down: one stint reads `unreachable 57FA 71:15`. B701's watch entries stop at 18:00:26, though the watch stayed in touch and handed its phone 87 points until 18:55, and the header doesn't say so |
| Battery per hour, sharing | FR-019, SC-005 | In 5% steps: host's phone 7%, host's watch 7%, B701's phone 3%, 7729's phone 3%, 7729's watch 10%. Nothing from 1.1, nor from B701's watch after 17:59. No hour without sharing to compare |
| Host Bluetooth restart, a full match, nine guests | FR-009, FR-012–FR-014, SC-001 | Not seen: no restart in the records, and three guests |

Verified on court by this session: FR-008, FR-010's 95% within 1 s on 1.2 phones, and FR-006
on the host's phone. FR-015 is consistent but not proven. The host no longer loses quiet guests
(`.specify/bugs/host-loses-quiet-guests/test.md`, On court). The rest of FR-010 waits for T058
and T065, which need one build on every device and the conditions this session lacked.

Contradicted, with follow-ups in tasks.md Phase 11:
- **FR-010's 2 s, a watch standing in as it joins** (T096).
- **FR-006, a 1.1 guest's points relayed to guests** read `unknown`, not `older` (T092).
- **FR-003 and SC-007**: stints cut by a watch's joins, and watch absences left open (T093, T094).
- **FR-005**: a watch in touch whose entries never reached its phone (T095).
- **FR-010a and FR-011** on the watch that kept losing its phone (T097).
- **FR-007** stays a target: no task, and D-7 stays closed with 1 `ETIMEDOUT` in 119.

The records could not show which round each device was on, whether every device drew the same
teams, what model or watchOS each watch had, or whether phones were in bags (T099–T101).

## Level 4: small field run

| | |
|---|---|
| Date, place | _ |
| Devices (model, iOS/watchOS, build) | _ |
| Wi-Fi on (unjoined) | _ |
| Length, points | _ |

| Check | Requirement | Result |
|---|---|---|
| Points within 1 s / 2 s, per phone | FR-010, SC-002 | _ |
| Watch hops within 1 s / 2 s, per watch and phone | FR-010a | _ |
| Share unknown, per phone, of the points FR-010 judges | FR-006 | _ |
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
| Points within 1 s / 2 s on every phone | FR-010, SC-002 | _ |
| Watch hops within 1 s / 2 s | FR-010a | _ |
| Prediction error at the 95th percentile | FR-018, SC-006 | _ |
| Battery | SC-005 | _ |
