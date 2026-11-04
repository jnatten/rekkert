# Validation: Rekkert on Apple Watch SE (1st generation)

**Feature**: `003-apple-watch-se-support` | Steps from [quickstart.md](quickstart.md)

## On the SE (1st generation) (quickstart § 3)

| | |
|---|---|
| Watch | Apple Watch SE (1st generation), _size_ |
| watchOS | _10.x_ |
| iPhone | _model_, iOS _version_ |
| Build | _Xcode run / TestFlight build N_ |
| Date | _date_ |

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Watch app on the watch | | |
| 2 | Every screen at the watch's size | | |
| 3 | Best-of-three tapped on the watch (≤ 2 s to the phone) | | |
| 4 | Taps and undo on the phone | | |
| 5 | Every mode | | |
| 6 | Tap → wrist ≤ 0.5 s, at the start and after 20 rounds | | |
| 7 | iPhone out of reach, scoring over Bluetooth | | |
| 8 | Convergence across the SE, a current watch and two phones | | |
| 9 | First workout: explanation, request without effort, start | | |
| 10 | Workout started from the phone | | |
| 11 | An hour with the wrist lowered | | |
| 12 | Three workouts of 30+ minutes in Apple Health and on the phone | | |
| 13 | Ratings in the Workouts list, none in Apple Health | | |
| 14 | Effort row on the phone's Apple Health page | | |
| 15 | Time-up buzz within 2 s of a current watch, app in front | | |
| 16 | Time-up notification, wrist lowered | | |
| 17 | Rings again after time is added | | |
| 18 | Battery after 2 hours with a workout (≥ 40%) | | Start: _%_, end: _%_ |

## Automated (quickstart § 1)

| Check | Result | Notes |
|---|---|---|
| `swift test --package-path Packages/RekkertKit` | Pass | 2026-11-04: 495 + 790 tests. `HealthDisclosureTests` covers the watchOS 10 lists and the new effort wording. |
| `scripts/verify.sh` | Pass | 2026-11-04: the new step prints `ok: "MinimumOSVersion" => "10.0"`. The embedded watch app's `Info.plist` has `MinimumOSVersion` 10.0. |
| SC-008: floor raised to 11.0 on a scratch change | Pass | 2026-11-04: package tests passed, then the gate stopped with `FAIL: the watch app's minimum is 11.0, not watchOS 10.0 — it would no longer install on Apple Watch SE (1st generation), Series 4 or Series 5`. The change was abandoned. A first attempt was cut short by an unrelated flake in `RekkertSyncTests` (`tapsMadeWhileDisconnectedArriveOnReconnect`, `SyncTests.swift:120`). |

## Simulator (quickstart § 2, T015, T022)

Run on a dedicated pair made for this: iPhone 17 Pro on iOS 26.0, and Apple Watch SE 3 (40 mm) on watchOS 26.0.

| Check | Result | Notes |
|---|---|---|
| T022: Effort row on the phone's Apple Health page | Pass | 2026-11-04, `-rekkert-demo-settings -rekkert-demo-apple-health`. Under "Saved to Apple Health", Effort reads "How hard you rated it, on the 1–10 scale. From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health." |
| T015: time-up on the fallback path (`-rekkert-observation-fallback`) | Pass | 2026-11-04, iPhone, `-rekkert-demo ladder -rekkert-demo-minutes 1`. After the minute the countdown shows "+0:10" and the orange "Time" label. That label comes only from the follower, and the demo seeds the round *after* `follow(_:)` starts, so the fallback delivered a change, not only the first value. |
| T015: time-up on the `Observations` path (no flag) | Pass | Same setup: "+0:09" and "Time", the same as the fallback. |
| T015: the watch on the fallback path | Pass (smoke) | The watch app was launched with the ladder demo and the fallback flag. It ran past the round's end ("+0:11" in orange) and was still running. The haptic cannot be seen on a simulator. |
| T015: rings again after time is added | Not run | Needs a tap on "Add time". |
| § 2: scoring, workout and rating, timed round on a current watch | Partly | Timed round: as above. Scoring and workout with a rating: not run, because they need taps. |

## Documents (quickstart § 4)

| Check | Result | Notes |
|---|---|---|
| README names watchOS 10 and the SE (1st generation) | Pass | Second paragraph. |
| Privacy page: effort sentence qualified, date updated | Pass | "Last updated 4 November 2026". |
| Review notes: effort sentence qualified, under 4000 characters | Pass | 3960 characters. |
| App Store compatibility line reads watchOS 10.0 | | After the next upload. |
