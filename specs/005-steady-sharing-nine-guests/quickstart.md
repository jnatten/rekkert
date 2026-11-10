# Quickstart: Proving Sharing Is Steady, Measured and Room for Two Courts

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Decisions**: [research.md](research.md)

There are five levels, fastest first:

- levels 1 and 2 run on every push;
- level 3 uses the Simulator;
- level 4 is the small field run before release;
- level 5 is the first two-court evening after release.

Suites marked *(new)* are added by this feature's tasks.

## Prerequisites

- Xcode 27 and the toolchain from `mise.toml` (`mise install`).
- For level 4: four iPhones and four Apple Watches on the same TestFlight build. Wi-Fi is on,
  not joined to any network, on the host and at least two guests, and off on one guest.
- For level 5: ten iPhones with watches on the released build.

## 1. Device-free tests (every push)

```bash
swift test --package-path Packages/RekkertKit
```

Expected: the whole package passes, with the existing sync suites unchanged (Principle II). The
new and changed suites:

| Suite | Requirement | Passes when |
|---|---|---|
| `ClockBoundsTests` *(new)* | FR-006 | Bounds from t₁/t₂/t₄, ageing at 50 ppm, composing two hops, and `unknown` past 0.1 s all hold |
| `ClockOffsetTests` *(new)* | FR-006 | With every simulated device's clock offset by up to ±3 s and drifting, every recorded delay is within 0.1 s of the true one, or reads `unknown` |
| `LinkRecordTests` | FR-001, FR-002 | New kinds, radios and drop details round-trip, and an older export parses unchanged |
| `SharingSummaryTests` *(new)* | FR-003, SC-007 | Stint boundaries, shares within 1 s and 2 s, drops per radio, unreachable time and battery per hour come out right |
| `WireCompatibilityTests` *(new)* | FR-015 | Every changed message decodes with and without its new fields, in both directions |
| `ArrivalConditionsTests` *(new)* | FR-010 | "Nothing is wrong" is decided right for phones, the host, and watches following their phones |
| `DropDetailTests` *(new)* | FR-002, FR-004 | Every platform error maps to one code from the fixed set, and none carries the error's own text |
| `RecordPrivacyTests` *(new)* | FR-004 | An exported record from a named, coded match holds no name, code, share id or score |
| `LinkRepliesTests` | Principle III | `LinkHealth.observe(_:)`: answers reset the count, timeouts are misses, failed sends count as neither |
| `BatteryNoteTests` *(new)* | FR-019 | Battery is noted at the start and end of sharing, and otherwise at most every 10 minutes |
| `LimitReachesWatchTests` *(new)* | FR-013, FR-014 | The host's watch and a turned-away guest's phone and watch all hold the limit |
| `WifiFirstTests` *(new, only if needed)* | FR-010, D-8 | Only if the nine-guest prediction misses: Wi-Fi first, Bluetooth after 400 ms, convergence unchanged |
| `NoEchoTests` *(new)* | FR-008 | A guest on both links never sends the host's points back to it, and Bluetooth chunks per point are about half of today's |
| `LinkChangeTrafficTests` *(new)* | FR-008 | A second link dropping and coming back sends one hello on that link, and nothing on the others |
| `BusyHallTests` *(new)* | FR-008, FR-010, FR-011, SC-002 | A host and four guests, each on both links with the second dropping on the field schedule, in a busy hall for 60 simulated minutes, with a second match on the next court. On every device, where nothing was wrong: at least 95% of points within 1 s, and all within 2 s. Otherwise: spec 001's times |
| `HostRadioRestartTests` *(new)* | FR-009, SC-004 | The host's Bluetooth off for 2 s and on again: every guest is back in step within 10 s |
| `WristFullTests` *(new)* | FR-013 | A wrist join to a full match shows "No room on this match" within 15 s, whichever half heard it |
| `CapacityTests` | FR-012, FR-013 | Parameterised on `Participants.limit`: that many get on, and the next is told within 15 s |
| `CalibrationTests` *(new)* | FR-017, SC-006 | Replaying the level-4 record with `Airwaves.Settings.calibrated` gives a 95th-percentile delay within 25% of the real one |
| `ClubNightTests` | FR-011, FR-012, FR-016, FR-020 | A two-court americano with a host and as many guests as the limit (nine once raised), each with a watch and two links, busy hall, 30 simulated minutes: FR-010 on every device, and spec 001's times where something was wrong. `predict(guests: 9)` runs it at nine before the limit is raised |

`CalibrationTests` and the nine-guest `ClubNightTests` run after level 4 has produced its record.
Until then, `ClubNightTests` runs at seven with today's settings, and the limit stays 7
(FR-016).

## 2. The gate (every push)

```bash
scripts/verify.sh
```

Expected:

- package tests, project generation, both app builds and every Info.plist assertion pass;
- the package step stays within the CI job's time;
- no new Info.plist key is expected: battery level needs none. If one is added, `verify.sh`
  asserts it.

## 3. Simulators: screens and the Wi-Fi path

```bash
scripts/share.sh --keep
```

Check against [contracts/screens.md](contracts/screens.md):

1. The host's share sheet and Home row say "1 of M joined" and "1 of M on". The watch card says
   "Sharing · 1 of M".
2. Settings → Sharing record on each phone shows a stint header with "within 1 s", the drop
   counts and battery. Rows show `wifi` after the device name. Bluetooth does not run in the
   Simulator.
3. A point scored on the host shows a `pointArrived(…s)` row on the guest in this build, which
   is not a debug-only build.

## 4. Small field run (before release)

Run it on the TestFlight build that has the record and the steadier links: D-1 to D-7 and
D-12.

1. **Set up.** A host and three guests, each with a watch, in a hall with other people about.
   Wi-Fi is on, unjoined, on the host and at least two guests, and off on one guest. Note each
   device's model and battery level.
2. **Share.** Host shares, guests join, and phones go in bags with watches on.
3. **Play.** Play at least an hour, tapping points on watches and phones across all four
   people.
4. **Burst.** Partway through, two guests walk out of range for about two minutes while play
   goes on, then come back.
5. **Battery comparison.** Play a further hour with sharing off and workouts on, on the same
   devices.
6. **Venue Wi-Fi, if there is one.** Play 15 minutes with all four joined to the hall's
   network. If there is none, note that case as untested in `validation.md`.
7. **Export.** Export the sharing record on every phone, with each watch in touch first so its
   half is merged.
8. **Cold read (SC-007).** A tester other than the developer reads one export and says whether
   points were on time and which connection dropped. Note whether that matches the numbers.

Expected, read from each phone's summary:

| Check | Requirement | Pass |
|---|---|---|
| Points within 1 s / 2 s | FR-010, SC-002 | ≥ 95% / 100% of timed points, on every phone and watch |
| Timed points | FR-006 | Few `unknown`. If more than 10% are unknown, the clock bounds need a look before the numbers count |
| Wi-Fi drops per guest per hour | FR-007, SC-003 | ≤ 5. If more, read the drop details, which starts D-7's time box |
| Back after the burst | FR-011 | The walkers catch up within spec 001's FR-002 times |
| Battery per hour with and without sharing | FR-019, SC-005 | Reported in `validation.md`, with no limit |

Then:

- trim the host's record (drop the header line), add it as the `CalibrationTests` fixture, and
  pin `Airwaves.Settings.calibrated` (D-11);
- run `ClubNightTests` at nine guests;
- **if it passes**, the limit becomes 9 in the release (FR-016);
- **if it does not**, the limit stays 7, the rest ships, and the numbers go back to the
  assessment for a decision between Options B and C.

## 5. First two-court evening after release

1. **Set up.** A host and nine guests with watches, on two side-by-side courts, with an
   americano or two matches.
2. **Play.** Play the evening as usual, and export every phone's record at the end.

Expected:

| Check | Requirement | Pass |
|---|---|---|
| Everyone gets on; nobody told the match is full | SC-001 | All nine guests on, "9 of 9 on" on the host's phone and watch |
| Points within 1 s / 2 s on every device | FR-010, SC-002 | As in level 4 |
| The simulation agreed | FR-018, SC-006 | The 95th-percentile delay is within 25% of `ClubNightTests`' prediction |
| Battery | SC-005 | Reported |

**If it falls short**, the next release lowers the limit to the largest number that met
FR-010 that evening (FR-016).

Results from levels 4 and 5 go in `validation.md`. The raw records stay with the requester.
