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
