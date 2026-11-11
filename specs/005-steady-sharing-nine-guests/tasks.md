---

description: "Task list for Steadier, Measurable Sharing for Two Full Courts"
---

# Tasks: Steadier, Measurable Sharing for Two Full Courts

**Input**: Design documents from `specs/005-steady-sharing-nine-guests/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required. Principle III asks for engine tests first, and FR-020 asks that every
requirement be covered by a simulated test on every push.

- In every story the test tasks come first.
- Tests for a gap research found (R-3, R-4, R-6) **must fail for the stated reason before
  that story's implementation**.
- Tests for behaviour that already holds (FR-009) pin it.

**Organization**: Tasks are grouped by user story, in the spec's priority order. Two phases
are not stories:

- **Phase 6** holds the field run and calibration that User Story 4 describes.
- **Phase 7** is the gate that raises the limit (FR-016). Its tasks are labelled [US3],
  because the limit is that story's capability.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: The user story the task belongs to (US1–US4, as in spec.md)
- Paths are from the repository root. Some are shortened:

  | Short | Full path |
  |---|---|
  | `RekkertSync/` | `Packages/RekkertKit/Sources/RekkertSync/` |
  | `RekkertCore/` | `Packages/RekkertKit/Sources/RekkertCore/` |
  | `SyncTests/` | `Packages/RekkertKit/Tests/RekkertSyncTests/` |
  | `CoreTests/` | `Packages/RekkertKit/Tests/RekkertCoreTests/` |

- **References**:
  - `R-n` and `D-n` are the findings and decisions in research.md.
  - `MS:` is `RekkertSync/MatchStore.swift`, `FO:` is `RekkertSync/FanOutTransport.swift`,
    `LN:` is `RekkertSync/LocalNetworkTransport.swift`, and `RC:` is
    `RekkertSync/Radio/RadioCore.swift`.
  - Line numbers are as of `e6b11594` and drift as tasks land, so find the code by the function
    named.
- **New files need no project changes.** Tuist globs `App/Sources/**`, `WatchApp/Sources/**`
  and `Shared/**`, and SwiftPM picks up new files in existing targets.
- **UI text comes verbatim** from [contracts/screens.md](contracts/screens.md). Record rows
  come from [contracts/sharing-record.md](contracts/sharing-record.md), and wire fields from
  [contracts/wire-protocol.md](contracts/wire-protocol.md).
- **"Nothing is wrong" (FR-010, as clarified)** holds for a point when:
  - the device it arrived on had a connection up: to the host for a guest's phone; to the
    guest it came from for the host; and for a watch following its phone, to that phone, with
    the phone meeting the same condition;
  - and in the 30 seconds before the point arrived, the device had neither been out of reach
    (15 s unheard) nor caught up a batch of points.

  One rule implements it (T007), and both the summary and the simulated tests use it.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A known-good baseline, and somewhere to keep the evidence

- [X] T001 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh` on `e6b11594`, and confirm both pass. Any failure here is not this feature's, and is raised before going on. Create `specs/005-steady-sharing-nine-guests/validation.md` with four sections:
  - **Baseline**: the RekkertSync suite time, `twoCourtsSevenGuestsHalfAnHour` time and `deliveryDoesNotSnowball` time, from the latest `main` CI run (`gh run view --log`).
  - **Level 4: small field run.**
  - **Calibration.**
  - **Level 5: two-court evening.**

  Give the last three the tables from [quickstart.md](quickstart.md).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: A simulation that can show the problem (D-10), the one rule for "nothing is
wrong" (FR-010), and the two pieces of plumbing that tests need before any story's code lands:
per-device clocks and an injectable host limit. Every story's tests need these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [P] Add `nextDue` to `TestClock` in `SyncTests/TestClock.swift`: the earliest deadline of any scheduled run, or `nil`. Cover it in the same file's existing tests, or in a new `SyncTests/TestClockTests.swift`.
- [X] T003 Let `CourtHarness` jump over idle radio time, in `SyncTests/CourtHarness.swift` (the stepping at :280-285). With `Timing.skipsIdleTime` on, a step goes up to the clock's `nextDue` when that is further off than the step. It is opt-in, so every existing RekkertSync suite runs exactly as before, still at 50 ms steps.

  Depends on T002.
- [X] T004 [P] Add to `Airwaves.Settings` in `SyncTests/SimulatedRadio.swift` (D-10). All are seeded from the existing generator (:573-587):
  - `jitter: Duration`, added to each hop;
  - `busyAir: Double`, a factor on `bytesPerSecond`;
  - `burstLoss`, bursts of lost host→guest chunks;
  - `guestWriteLoss: Double`;
  - `sharedAirtime: Bool`: every host on the same airwaves draws on one byte budget, so a second shared match on the next court competes for the air;
  - a static `busyHall` preset with `jitter`, `busyAir`, `burstLoss` and `guestWriteLoss` on.
- [X] T005 [P] Create `SyncTests/Flapper.swift`. It drops and restores one guest's second link on a seeded schedule, from the field numbers in research.md D-10:
  - up for a median of 43 s (90th percentile 127 s);
  - down for a median of 4.1 s (90th percentile 10.9 s);
  - a third of drops shared with another guest within 1 s.

  It uses `walkAway`/`comeBack` on that guest's second radio (`SyncTests/SimulatedRadio.swift:488-496`).
- [X] T006 Give `CourtHarness` a second link per guest phone, in `SyncTests/CourtHarness.swift` (`boot`, :120-124).
  - The second link is a separate `Airwaves` standing in for Wi-Fi, with its own `SimulatedRadio` and `RadioCore`, attached as `.sharedSession`.
  - New options:
    - `radios` per guest:
      - `.bluetooth`: one core on the Bluetooth airwaves, as today;
      - `.wifi`: the guest's only core sits on the Wi-Fi airwaves with `wifiSettings`, so `SharedSession` joins through it unchanged;
      - `.both`: the Bluetooth core, plus a second core on the Wi-Fi airwaves that joins alongside.
    - `flapper: Flapper?`;
    - `wifiSettings: Airwaves.Settings`.
  - The host listens on both airwaves.
  - The real `LocalNetworkTransport` stays out of the harness, because it only builds for iOS. Field runs cover it (T058).

  Depends on T003 and T005.
- [X] T007 [P] Create the pure rule `ArrivalConditions.nothingWrong(arrivalAt:on:from:entries:pairEntries:)` in `RekkertCore/Sync/ArrivalConditions.swift`, as data-model.md defines it. It reads the device's `LinkRecordEntry`s (`proven`/`dropped` per link, `outOfReach`, `caughtUp`), plus its phone's entries for a watch following that phone, and returns true exactly as defined above (FR-010).
  - Pin it in `CoreTests/ArrivalConditionsTests.swift`:
    - one link up of two;
    - every link down;
    - out of reach 29 s before and 31 s before;
    - a `caughtUp` within 30 s;
    - the host's view of a guest;
    - a watch whose phone was fine, a watch whose phone had no link to the host, and a watch whose pair link was down.
- [X] T008 Add per-device arrivals to `CourtHarness` in `SyncTests/CourtHarness.swift` (replacing the pooled `arrivalTimes()` at :287-300):
  - `arrivals(by device:)` leaves out only the device that tapped (its paired phone or watch still counts, FR-010). It counts a point that never arrived as later than 2 s, and times point taps only, not undos;
  - each arrival is tagged with `ArrivalConditions.nothingWrong` over that device's recorder entries;
  - a `DelayStats` gives the median, 95th percentile, slowest, and the shares within 1 s and 2 s, and says whether the device is judgeable: at least 100 timed points, and at most 10% unknown, leaving out `older` points;
  - existing suites keep their pooled assertions through a compatibility helper.

  Depends on T006 and T007.
- [X] T009 Stamp taps with an injectable clock, so tests can give each device its own. Production behaviour is unchanged, because the store's `now()` is `Date()` outside tests.
  - In `RekkertSync/MatchStore.swift`, `tap()`/`record()` stamp with the store's `now()`, not `Date()` (MS:248-251, 1411-1414).
  - In `SyncTests/CourtHarness.swift`, each simulated device gets its own clock offset and drift (both zero by default), and the harness can report a point's true delay.
- [X] T010 Make the host's limit injectable. Production code always uses the constant.
  - `Participants.heard(…)` takes a `limit`, defaulting to `Participants.limit` (`RekkertCore/Sync/ParticipantState.swift:34, 75`). `Participants` itself, which is persisted, keeps its shape.
  - `MatchStore` takes an optional `guestLimit`, defaulting to the constant (`RekkertSync/MatchStore.swift`).
  - `CourtHarness` passes it through (`SyncTests/CourtHarness.swift`).
- [X] T011 Run all RekkertSync suites, and record in `specs/005-steady-sharing-nine-guests/validation.md` the suite time and `twoCourtsSevenGuestsHalfAnHour` time against the T001 baseline. If either is slower than the baseline, fix the stepping before going on.

**Checkpoint**: The simulation has two links per guest, a busy hall, per-device delays,
per-device clocks and an injectable host limit, and the one rule exists. Stories can begin, and
every story's tests can be written before its implementation.

---

## Phase 3: User Story 1 - Points show on every device within a second, even in a busy hall (Priority: P1) 🎯 MVP

**Goal**: A dropping second link costs no one time, and points reach every device within
1 s for 95% and within 2 s for all, when nothing is wrong (FR-007–FR-011).

**Independent Test**: `BusyHallTests`: a host and four guests on both links, the second
link dropping on the field schedule, a busy hall, 60 simulated minutes. Every device meets
FR-010 over the arrivals where nothing was wrong.

### Tests for User Story 1 ⚠️

> **Write these tests FIRST. T012 and T013 must FAIL for the stated reason before T017–T019.**

- [X] T012 [P] [US1] `SyncTests/NoEchoTests.swift` (R-4, fails first). A host and two guests on both links. Over 50 points scored on the host:
  - no guest sends a host point back to the host on either link: the host's `echoesHeard` (its own events arriving back over a link) stays 0;
  - the same holds the other way, for a guest that scores;
  - every device ends in step.
- [X] T013 [P] [US1] `SyncTests/LinkChangeTrafficTests.swift` (R-3, fails first). A host and three guests on both links:
  - when one guest's Wi-Fi link drops and comes back, no device runs a round of `synchronise()` (`synchroniseRounds` unchanged everywhere): the link gets one `hello` and its answer;
  - a point scored while the link was down still reaches that guest when it comes back;
  - the first proof of a new guest still exchanges `access` and `guestCard`;
  - every device ends in step.
- [X] T014 [P] [US1] `SyncTests/HostRadioRestartTests.swift` (FR-009, SC-004, pins today's behaviour). A host and four guests on Bluetooth: turn the host's radio off for 2 s and on again. Every guest is back in step within 10 s, with no input.
- [X] T015 [P] [US1] `SyncTests/BusyHallTests.swift` (FR-007, FR-008, FR-010, SC-002). Uses `Airwaves.Settings.busyHall` and a `Flapper` on every two-link guest:
  - **Main case**: a host and four guests on both links, 60 simulated minutes, points tapped on watches and phones across all five people. On every phone and watch, among arrivals where nothing was wrong, at least 95% within 1 s and all within 2 s.
  - **One radio**: one guest on `.bluetooth` only, and one on `.wifi` only (Story 1 scenario 4, Edge Cases); both meet the same times.
  - **Drops cost no time** (FR-008): no arrival after a second-link drop exceeds 2 s while another link was up.
  - **Something wrong** (FR-011): arrivals where nothing-wrong does not hold still meet spec 001's times: all within 30 s, and 95% within 5 s.
  - **The next court** (Edge Cases): with `sharedAirtime` on, a second host with two guests shares a separate match on the same airwaves. Build it as a second `CourtHarness` passed the first one's `air:`, with its own `code:` (`SyncTests/CourtHarness.swift:78`). Both matches still meet FR-010, and no device gets onto the other's match.
  - **Drop rate** (FR-007): drops per guest per hour are reported in the test output against the target of 5. They are not asserted, because FR-007 is a target.
  - Record whether this suite fails on today's code, and why, in `validation.md`.
- [X] T016 [P] [US1] Pin the Wi-Fi link's miss rule (Principle III) in `SyncTests/LinkRepliesTests.swift` (`LinkHealthTests`), for `LinkHealth.observe(_ outcome: ReplyOutcome) -> Bool`:
  - a reply counts as answered;
  - a reply timeout counts as a miss;
  - a send that failed before going out whole counts as neither;
  - three timeouts in a row mean the peer is gone.

  It fails until T020 adds `observe(_:)`.

### Implementation for User Story 1

- [X] T017 [US1] No echo (D-5) in `RekkertSync/MatchStore.swift`:
  - `push` (MS:1506-1513) leaves out every link whose far end, from `farEnds`, is the device the events came from, not only the link they came on;
  - events arriving on one link mark them held on every sibling link to the same device (where `heldOnLink` is updated, MS:1734-1736);
  - the hello still catches up anything missed (Principle II).
- [X] T018 [US1] Make the store's reaction to reachability proportionate (D-6), in `RekkertSync/MatchStore.swift` (`consumeReachability`). The fan-out keeps passing on every child's change, because the radio core uses that to nudge a quiet guest into its hello (`RadioCore.swift:299`). The store then runs a full `synchronise()` only when the device as a whole came or went: any link to the match up or not, or the pair. Otherwise a guest asks what it is missing, and the host does nothing, leaving the changed link to `greet` (T019).
- [X] T019 [US1] Greet only the changed link (D-6) in `RekkertSync/MatchStore.swift`:
  - a newly proven link gets one `hello` on that link only, with its catch-up;
  - `access` (host) and `guestCard` (guest) go out on the first proof of a device, or when they change, not on every re-proof (MS:651-671, 1251-1264, 1344-1360);
  - the nudge, retry and idle hello stay as they are.

  Depends on T018.
- [X] T020 [US1] Add the pure `LinkHealth.observe(_ outcome: ReplyOutcome) -> Bool` beside `LinkHealth` in `RekkertSync/LinkReplies.swift:41`, with `ReplyOutcome` as `answered`, `timedOut` or `notSent`, so that T016 passes. T021 then adds no rule of its own.
- [X] T021 [US1] Loosen the Wi-Fi link (D-7) in `RekkertSync/LocalNetworkTransport.swift`:
  - **TCP keepalive**: idle 5 s, interval 3 s, count 5 (LN:462-465);
  - **a miss counter**: each ready link keeps a `LinkHealth` and feeds it every request's outcome through `observe(_:)` (T020). When it reports the peer gone, the link closes with reason `timeout` (beside the reply timeout at LN:745-748). A guest on Wi-Fi alone then still notices a dead link.

  The adapter holds no rule of its own: the counting is `LinkHealth`'s, pinned by T016. It only builds for iOS. Prove the wiring with `scripts/share.sh` in T069, and in the field in T058.
- [X] T022 [US1] Make T012–T016 pass, and run the whole package: the convergence suites must pass unchanged. Record `BusyHallTests`' per-device numbers in `specs/005-steady-sharing-nine-guests/validation.md`.

**Checkpoint**: Points are fast and steady in the simulation. Story 1 can ship alone, though the
field run needs Story 2's record to prove it.

---

## Phase 4: User Story 2 - The sharing record says how late points were and which link dropped (Priority: P1)

**Goal**: Delays to within 0.1 s or `unknown` in every build, the radio on every link entry,
drop details, and a summary per stint (FR-001–FR-006, SC-007).

**Independent Test**: In `ClockOffsetTests`, with every device's clock offset and drifting,
every delay in every record is within 0.1 s of the truth or reads `unknown`. At most 10% of
any device's points are unknown, and each summary matches its entries.

### Tests for User Story 2 ⚠️

> **Write these tests FIRST. They fail until T032–T042 land.**

- [X] T023 [P] [US2] `CoreTests/ClockBoundsTests.swift` (FR-006, D-2). It pins:
  - the bounds from t₁/t₂/t₄, `estimate` (the midpoint) and `halfWidth`;
  - `aged(at:)` widening by 50 ppm;
  - `narrower(than:)`;
  - `composed(with:)`, where estimates and half-widths add;
  - `delay(arrivedAt:tappedAt:)` returning `nil` when `halfWidth + 0.005 > 0.1`.
- [X] T024 [P] [US2] `CoreTests/SharingSummaryTests.swift` (FR-003, D-4). It pins:
  - stint boundaries: `sharingStarted`, `sharingRestored` or `joined`, to `sharingStopped`, leaving, or the end of the file;
  - the median and slowest delay;
  - the shares within 1 s and 2 s, counted only over arrivals where `ArrivalConditions.nothingWrong` holds;
  - the share of unknown delays, leaving out `older` ones;
  - `judgeable`: false below 100 timed points, or above 10% unknown;
  - drops per radio, leaving out the host's own Bluetooth restarts, which `hostRestarts` counts instead;
  - unreachable time per far device, from `outOfReach` to `backInStep`;
  - battery per hour for phone and watch;
  - `watchUpTo`, when the watch has not been in touch since;
  - a stint with no points.
- [X] T025 [P] [US2] Extend `CoreTests/LinkRecordTests.swift` (FR-001, FR-002), per [contracts/sharing-record.md](contracts/sharing-record.md):
  - round trips for `pointArrived(0.412s)`, `pointArrived(unknown)`, `pointArrived(unknown; older)`, `battery(83%)`, a radio in the link column (`host 57FA wifi`, `guest 255B bt+wifi`) and a drop detail (`dropped(closedByPeer; ETIMEDOUT)`);
  - an export from today's format (no radios) parses unchanged;
  - summary lines are skipped by `parse`.
- [X] T026 [P] [US2] `CoreTests/WireCompatibilityTests.swift` (FR-015, D-14), per [contracts/wire-protocol.md](contracts/wire-protocol.md):
  - `hello` with and without `clock` and `protocol`;
  - `events` with and without `offsets`;
  - `GuestCard` with and without `protocol`;
  - the `needsUpdate` case;
  - a 1.1-shaped payload decoded by this release's decoder, and this release's payloads decoded with the new fields stripped, as a 1.1 decoder would see them.
- [X] T027 [P] [US2] Extend `CoreTests/EventTimeTests.swift` (D-1):
  - `MatchEvent.stamp` rounds to 0.01 s;
  - an event's `at` survives encode→decode bit for bit, so every device holds the same value (Principle II);
  - an event stamped by today's 0.1 s rule decodes unchanged.
- [X] T028 [US2] `SyncTests/ClockOffsetTests.swift` (FR-006, clarified). A host and four guests, each with a watch, on both links. Every device's clock is offset by up to ±3 s and drifts by up to 20 ppm (T009). Over 30 simulated minutes:
  - every recorded delay is within 0.1 s of the harness's true delay, or reads `unknown`;
  - no device has more than 10% unknown;
  - each watch's delay entries reach its phone's export and the phone's summary, once the two are in touch (FR-005);
  - when one guest's clock jumps 5 s forward mid-run, delays across the jump read unknown, never wrong (Edge Cases).

  Depends on T009.
- [X] T029 [US2] `SyncTests/OlderGuestTests.swift` (FR-015, clarified). A guest whose sent payloads have `clock`, `protocol` and `offsets` stripped, as 1.1 sends them, joins a host from this release:
  - it is counted once;
  - it receives every point;
  - the host records its points' delays as `unknown`, not as wrong numbers.
- [X] T030 [P] [US2] `SyncTests/DropDetailTests.swift` (FR-002, FR-004). For every platform error in data-model.md's `DropDetail` table, built as `NWError.posix(…)`, `.dns(…)` and `.tls(…)` on macOS:
  - it maps to the listed code;
  - anything else maps to `other`;
  - no mapped value contains text from the error's own description.
- [X] T031 [P] [US2] `SyncTests/RecordPrivacyTests.swift` (FR-004). Run a shared match in `CourtHarness` with named players and a known code, then export every phone's record. The export must not contain:
  - any player's name;
  - the code, or the share id;
  - any score.

  Every `detail` value must come from `DropDetail`'s fixed set.

### Implementation for User Story 2

- [X] T032 [P] [US2] Round `MatchEvent.stamp` to the hundredth in `RekkertCore/Sync/MatchEvent.swift:121-126` (D-1), and update its doc comment's reasoning.
- [X] T033 [P] [US2] Create `RekkertCore/Sync/ClockBounds.swift`, holding both `ClockBounds` and `ClockBook` (D-2), as data-model.md defines them:
  - `ClockBounds` has `lower`, `upper`, `sampledAt`, `estimate`, `halfWidth`, `aged(at:)`, `narrower(than:)`, `composed(with:)` and `delay(arrivedAt:tappedAt:)`;
  - `ClockBook` holds `[DeviceID: ClockBounds]`, keeping the narrower sample.

  Both are `Codable` and `Sendable`.
- [X] T034 [P] [US2] Extend `RekkertCore/Sync/LinkRecord.swift` (D-1, D-3, D-12):
  - `LinkRadio` (`bluetooth`, `wifi`);
  - optional `radios: [LinkRadio]?` and `detail: String?` on `LinkRecordEntry`;
  - `pointArrived(latency: TimeInterval?)`;
  - `battery(level: Double)`.

  The text forms and `parse` follow [contracts/sharing-record.md](contracts/sharing-record.md). Older lines decode with both fields absent.
- [X] T035 [US2] Add the optional wire fields (D-2, D-14) in `RekkertCore/Sync/Wire.swift` and `RekkertCore/Sync/ShareAccess.swift`:
  - `hello` gains `clock: Date?` and `protocol: Int?`, where `protocol` is `2`;
  - `events` gains `offsets: [DeviceID: ClockSpan]?`, whole milliseconds rounded outwards;
  - `GuestCard` gains `protocol: Int?`;
  - there is a new case `needsUpdate(sessionID:)`, which nothing sends;
  - there is a new case `clock(reading:)`, small enough for one radio chunk each way (D-2, revised);
  - the fan-out's exhaustive switches cover the new case (FO:49-64, 256-265).

  Depends on T033.
- [X] T036 [P] [US2] Create `RekkertSync/DropDetail.swift`: a pure mapping from the platform's connection error to one code, exactly as data-model.md's `DropDetail` table lists them. It never passes on the error's description text (FR-004).
- [X] T037 [US2] Name each link's radio, and keep drop details (D-3):
  - `RadioCore` reports `.bluetooth`, and `LocalNetworkTransport` reports `.wifi`;
  - `FanOutTransport` records each child's radio when a link comes up, and answers `radio(of: LinkID)`;
  - `MatchStore` caches the radio with `farEnds` at first proof, and puts it on every link entry it notes;
  - `LocalNetworkTransport` passes `DropDetail`'s code for the `NWError` as the drop's `detail` (LN:541-542, 687-690, 704, 707-708).

  Files: `RekkertSync/Radio/RadioCore.swift`, `RekkertSync/LocalNetworkTransport.swift`, `RekkertSync/FanOutTransport.swift`, `RekkertSync/MatchStore.swift`. Depends on T034 and T036.
- [X] T038 [US2] Measure delays in every build (D-1, D-2) in `RekkertSync/MatchStore.swift`:
  - **Time the round trip.** `deliver()` notes t₁ before `sendLive` and t₄ on the reply. Every `hello` the store writes carries `clock`. A reply's `clock` updates the store's `ClockBook`.
  - **Ask the time.** On each link to a device whose hello carried `protocol`, a `clock` question when the link is greeted and every 30 s while sharing (D-2, revised).
  - **Every sender passes on offsets.** It adds `offsets` for the recipient and each author to every `.events` push. A receiver learns from them on every push, even one whose points it already holds, composed with its own bounds on the sender.
  - **The watch does the same** over the pair link, with its phone as the first hop.
  - **Delays in every build.** Remove the `#if DEBUG` around `pointArrived` (MS:2143-2148), and note `pointArrived(latency:)` for point taps only, with the radio of the link the point came on. Note `nil` when `ClockBounds.delay` returns nil, with `detail: "older"` when the author or the relaying host never sent a `clock`, as a 1.1 device does (FR-006).
  - **A clock change** (`NSSystemClockDidChange`) clears the device's `ClockBook`, and delays noted in the next 60 s read unknown (Edge Cases). A sample that contradicts the kept one replaces it, because the far clock changed.
  - **The watch's hello keeps its clock** when `ReplyFold` folds a single reply, so the watch can time its phone.

  Depends on T009 (Phase 2) and T032–T037.
- [X] T039 [US2] Put the radios on reach entries:
  - the host's `outOfReach`/`backInStep` (MS:1266-1292) and the guest's (`RekkertSync/SharedSession.swift:660-684`) carry the radios that were up when noted;
  - both radios up is written `bt+wifi`.

  Depends on T037.
- [X] T040 [P] [US2] Create `RekkertCore/Sync/SharingSummary.swift`, and add `LinkRecord.summaries()` (D-4):
  - fields as in data-model.md, with the FR-010 shares counted over arrivals where `ArrivalConditions.nothingWrong` holds;
  - `export()` prints each stint's indented summary line before its rows, worded as in [contracts/sharing-record.md](contracts/sharing-record.md).

  Depends on T007 and T034.
- [X] T041 [US2] Show the stints in `App/Sources/Views/SharingRecordView.swift`:
  - group entries by stint, newest first, each with a header worded as in [contracts/screens.md](contracts/screens.md);
  - leave out header lines with no data;
  - the shared export includes the summaries;
  - it works with VoiceOver and larger text sizes.

  Depends on T040.
- [X] T042 [P] [US2] Make the watch send only day files that changed since they were last sent, in `RekkertSync/LinkRecorder.swift` (:59, 88-93). Pin it in `SyncTests/OwnWatchTests.swift` or a new `SyncTests/RecordTransferTests.swift`.
- [X] T043 [US2] Make T023–T031 pass, and run the whole package.

**Checkpoint**: Every build records delays, radios, drop details and a summary per stint.
Stories 1 and 2 together are what the small field run needs.

---

## Phase 5: User Story 3 - Two full courts and two sitting out, all on one match (Priority: P2)

**Goal**:

- everything a raised limit needs, except raising it (that is Phase 7, behind FR-016);
- the limit travels to the watch and to a turned-away guest;
- "N of M on" wherever the count shows;
- a full match ends a wrist join within 15 s.

**Independent Test**: `ClubNightTests` with as many guests as the limit allows, each with a
watch and two links, in a busy hall: FR-010 on every device, and the next guest refused
within 15 s. `WristFullTests` passes.

### Tests for User Story 3 ⚠️

> **Write these tests FIRST. T045 must FAIL for the stated reason before T050.**

- [X] T044 [P] [US3] Parameterise the tests on `Participants.limit`, so none says seven:
  - `SyncTests/CapacityTests.swift` (all four tests, :53-117);
  - `SyncTests/IncidentTests.swift` (:57-130);
  - `CoreTests/ParticipantStateTests.swift` (:44-58).

  They must still pass at 7.
- [X] T045 [P] [US3] `SyncTests/WristFullTests.swift` (R-6, FR-013, fails first). A match at its limit, and a guest joins from the wrist, once with the phone in reach and once with it in a bag. Whether the phone or the watch hears `noRoom`, the wrist's join ends as `.failed(.noRoom)` within 15 s, never `.notFound`.
- [X] T046 [P] [US3] Extend `CoreTests/WireCompatibilityTests.swift`: `noRoom` with and without `limit`, and `HostingStatus` with and without `limit`, decoded both ways.
- [X] T047 [US3] Rewrite `twoCourtsSevenGuestsHalfAnHour` in `SyncTests/ClubNightTests.swift` (:19-41) as `twoCourtsFullHalfAnHour`:
  - the host plus as many guests as the host's limit, each with a watch;
  - two links per guest, with a `Flapper`, in a busy hall;
  - an americano over two courts for 30 simulated minutes;
  - FR-010 on every device over arrivals where nothing was wrong;
  - spec 001's times (all within 30 s, 95% within 5 s) over arrivals where something was wrong (FR-011);
  - one more guest refused within 15 s.

  FR-010's and FR-011's numbers there are known issues until calibration (T059), since they depend on the guessed busy-hall speed. Today's test stays, parameterised, as `twoCourtsFullHalfAnHourOnAQuietRadio`, asserting spec 001's times firmly.

  Add `predict(guests:settings:)`, which runs the same setup at a given number of guests with the host's limit injected (T010), for Phase 6. Depends on T010.
- [X] T048 [P] [US3] `SyncTests/LimitReachesWatchTests.swift` (FR-013, FR-014). With an injected limit of 3:
  - the host's watch holds `HostingStatus.limit == 3`, and the count of who is on, through `WatchStandIn`;
  - a fourth guest's phone and watch both hold the limit from `noRoom`, and show the full-match status.

### Implementation for User Story 3

- [X] T049 [US3] Send the limit (D-13):
  - `noRoom` gains `limit: Int?` (`RekkertCore/Sync/Wire.swift:251`), set when refusing (MS:563-566, 1677-1685);
  - `HostingStatus` gains `limit: Int?` (`Wire.swift:132-165`), set in `RekkertSync/SharedSession.swift:858-866`;
  - the guest's store keeps the limit it was refused at as `noRoomLimit`, and the phone's `.state` signal to its watch carries it, so views can show it.

  Depends on T035 (same files).
- [X] T050 [US3] End a wrist join on a full match (D-13) in `RekkertSync/WatchStandIn.swift`:
  - a `noRoom` heard by either half of the pair ends the wrist's join at once as `.failed(.noRoom)`, instead of looking on the wrist or giving up as `.notFound` (:57-60, 491-495);
  - the wrist keeps the host's limit as `fullLimit`, from the phone's `.state(.failed(.noRoom), limit:)` or its own search. (`WatchStandIn.Status` is about a match the wrist is on, so a refused join needs no case there.)
- [X] T051 [P] [US3] Phone wording from [contracts/screens.md](contracts/screens.md), falling back to today's text when `M` is unknown. VoiceOver labels say the same words:
  - "N of M joined" in `App/Sources/Views/ShareCodeSheet.swift` (:113-119);
  - "N of M on" in `App/Sources/Views/SharingSection.swift` (:49-51) and `App/Sources/Views/RootView.swift` (:337-343);
  - the full-match advice from the limit in `App/Sources/Views/JoinMatchSheet.swift` (:256).
- [X] T052 [P] [US3] Watch wording from [contracts/screens.md](contracts/screens.md), with today's text as fallback:
  - "Sharing · N of M" in `WatchApp/Sources/Views/WatchSharingCard.swift` (:18);
  - "N of M on" in `WatchApp/Sources/Views/WatchRootView.swift` (:382) and `WatchApp/Sources/Views/WatchEndOfMatchQuestion.swift` (:53);
  - in `WatchApp/Sources/Views/WatchCourtPage.swift` (:75-76), the same count as everywhere else, everyone on in reach or not;
  - the title "N of M on" in `WatchApp/Sources/Views/WatchGuestsView.swift`;
  - the full-match advice and the `.full` status in `WatchApp/Sources/Views/WatchJoinView.swift` (:213).

  Everything must work on watchOS 10.
- [X] T053 [US3] Make T044–T048 pass at the current limit of 7, and run the whole package.

**Checkpoint**: Everything is ready for nine guests except the number itself.

---

## Phase 6: User Story 4 - Know before a club night whether sharing will hold up (Priority: P3)

**Goal**: Battery in the record, the small field run, calibration, and a trustworthy
nine-guest prediction (FR-017–FR-019, SC-005, SC-006).

**Independent Test**: `CalibrationTests` replays the field run's record, and its simulated
95th-percentile delay is within 25% of the real one. The nine-guest prediction is recorded
in `validation.md`.

- [X] T054 [P] [US4] `SyncTests/BatteryNoteTests.swift` (D-12, C2). Given levels handed to the recorder on an injected clock, `LinkRecorder` notes `battery(level:)`:
  - when sharing starts or a join completes, and when it stops or the guest leaves;
  - otherwise only when 10 minutes have passed since its last battery entry;
  - and never more often, however often it is handed a level.
- [X] T055 [US4] Battery readings in the record (D-12). Depends on T054.
  - **`RekkertSync/LinkRecorder.swift`** gains `offer(batteryLevel:)`. It decides whether to note `battery(level:)` on the `radio` link, by the rule T054 pins: due at once after the recorder notes a stint starting or ending, otherwise ten minutes after the last reading, with or without sharing, so the quickstart's hour with sharing off is read the same way.
  - **`Shared/AppModel.swift`** only reads the level. It turns on battery monitoring (`UIDevice.current.isBatteryMonitoringEnabled` on the phone, `WKInterfaceDevice.current().isBatteryMonitoringEnabled` on the watch) and hands the store a closure that reads it. The store offers it to the recorder on its existing participant tick. Neither holds a cadence rule (Principle I).
  - **RekkertSync stays free of UIKit and WatchKit.**
  - **`CoreTests/SharingSummaryTests.swift`** covers the per-hour drain (T024).
- [X] T056 [P] [US4] Create `SyncTests/Calibration.swift` (D-11):
  - it reads an exported record with `LinkRecord.parse`;
  - it fits `latency` from the fastest single-hop Bluetooth delays;
  - it fits `bytesPerSecond` by replaying the run in the harness until the simulated 95th percentile matches;
  - it returns `Airwaves.Settings`.

  `CalibrationFitTests` fits a record the harness wrote at a known speed, and replays it within 25% at the 95th percentile. Latency and speed trade off in that fit: the fastest points carry transfer time too, so it lands on a higher latency and a different speed than the ones that wrote the record.
- [ ] T057 [US4] Ship a TestFlight build containing Phases 2–5 and T055, with the limit still 7, through the `testflight` workflow. Describe the field run to testers in the build's notes.
- [ ] T058 [US4] Run the small field run (manual), [quickstart.md](quickstart.md) level 4. A host and three guests with watches in a hall, at least an hour, with:
  - Wi-Fi on but unjoined for the host and at least two guests, and off for one;
  - the walk-out burst;
  - a further hour with sharing off for battery;
  - if the hall has a Wi-Fi network everyone can join, 15 minutes with all four joined to it (Edge Cases). If not, note that case as untested in `validation.md`.

  Export every phone's record. In `validation.md`, record:
  - each summary;
  - FR-010 per device, within the 10% unknown cap;
  - drops per guest per hour against FR-007's target;
  - the drop details;
  - battery per hour with and without sharing;
  - whether another shared Rekkert match was running nearby (Edge Cases);
  - SC-007: a tester other than the developer reads one exported record, cold, and says whether points were on time and which connection dropped. Write down their answer and whether it matched the numbers.
- [ ] T059 [US4] The D-7 time box: at most two days after T058. Read the Wi-Fi drop details from the records.
  - If they show keepalive cutting paused links, tune `LocalNetworkTransport`'s keepalive (T021) and note it for the next build.
  - If not, stop there.

  Either way, write the finding into research.md D-7 and `validation.md`. FR-007 is a target, so this blocks nothing.
- [ ] T060 [US4] Calibrate from the field run (FR-017, SC-006):
  - add the host's record from T058 to `SyncTests/CalibrationFixture.swift` as a Swift string, with its header line holding full device ids removed;
  - pin the fitted settings as `Airwaves.Settings.calibrated` in `SyncTests/SimulatedRadio.swift`;
  - create `SyncTests/CalibrationTests.swift`, asserting that the replayed 95th-percentile delay is within 25% of the record's.

  Depends on T056 and T058.
- [ ] T061 [US4] Predict nine guests: run `ClubNightTests.predict(guests: 9, settings: .calibrated)` (T047) and record in `validation.md` whether FR-010 holds on every device. Depends on T047 and T060.
- [ ] T062 [US4] **Only if T061 misses FR-010**: write `SyncTests/WifiFirstTests.swift` first, and see it fail. For a guest with both links up:
  - a point goes on Wi-Fi alone when Wi-Fi answers within 400 ms;
  - it also goes on Bluetooth when Wi-Fi has not answered by then;
  - a guest on one link is sent as today;
  - every device ends in step (Principle II).
- [ ] T063 [US4] **Circuit breaker, only if T061 misses FR-010**:
  1. Implement D-8 in `RekkertSync/MatchStore.swift` (`push`/`deliver`): for a guest with both links up, send on Wi-Fi first, and on Bluetooth only when Wi-Fi has not answered within 400 ms. Make T062 pass, then re-run T061.
  2. If FR-010 still misses, stop here. The limit stays 7, and Phase 7 does not run. Write the numbers into `validation.md` and `.specify/assessments/session-sharing-limits/decision.md`, for a new decision between Options B and C.

**Checkpoint**: The nine-guest prediction is in hand, and so is the decision on Phase 7.

---

## Phase 7: Raising the limit (FR-016 gate)

**Purpose**: Nine guests, only when the calibrated prediction says nine fit. Confirmed after
release.

- [ ] T064 [US3] **Only if T061, or T063's re-run, passed**:
  - raise `Participants.limit` to 9 in `RekkertCore/Sync/ParticipantState.swift:34`;
  - confirm that `ClubNightTests.twoCourtsFullHalfAnHour` runs nine guests on `.calibrated` and passes, and that T044's suites pass at 9;
  - update the limit's wording in `README.md` (:745-746).
- [ ] T065 [US3] After release, the first two-court evening (manual), [quickstart.md](quickstart.md) level 5. Record in `validation.md` SC-001, FR-010 per device and the prediction's error (FR-018, SC-006). If it falls short, open a follow-up to lower the limit in the next release to the number that met FR-010 (FR-016).

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T066 [P] Update `README.md`:
  - "How syncing works" gains the record's delays, radios, drop details, summaries and battery, and the "N of M" counts;
  - the comment at MS:657 ("seven guests saying it at once") no longer names a number.
- [ ] T067 [P] Check every new or changed view with VoiceOver and the largest text sizes, on the phone and the watch (spec 001 FR-031). This covers the stint header in `SharingRecordView` and each "N of M" label.
- [X] T068 Run `scripts/verify.sh`. If the package step makes the CI job (`.github/workflows/test.yml`) take more than 30 minutes:
  - split the RekkertSync suites across parallel jobs, each running `verify.sh`'s package-test step with a `--filter` (D-10);
  - `verify.sh` stays the one definition of green (Principle IV).
- [ ] T069 Run `scripts/share.sh --keep` ([quickstart.md](quickstart.md) level 3), and check the screens against [contracts/screens.md](contracts/screens.md):
  - "1 of M" on the host's phone and watch;
  - the stint header;
  - Wi-Fi rows marked `wifi`;
  - `pointArrived(…s)` rows on the guest.
- [X] T070 Check whether any task added an Info.plist key or entitlement (none are expected: battery level needs none). If one did, add its assertion to `scripts/verify.sh`. Either way, say so in the PR description.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. Blocks every story.
- **User Story 1 (Phase 3)**: after Phase 2.
- **User Story 2 (Phase 4)**: after Phase 2.
  - Its `MatchStore` tasks (T037–T039) follow US1's (T017, T019), because they edit the same file.
  - Its Core tasks (T023–T027, T032–T034, T040) can run beside US1.
  - T036 comes before T037.
- **User Story 3 (Phase 5)**: after Phase 2.
  - T049 follows T035, because they share `Wire.swift`.
  - T047 and T048 use the injectable limit from Phase 2 (T010).
- **Phase 6 (User Story 4)**:
  - T054 and T056 can start after Phase 2, and T055 follows T054;
  - T057 needs Phases 3–5 and T055;
  - T058 needs T057;
  - T059 and T060 need T058;
  - T061 needs T047 and T060;
  - T062 and then T063 run only if T061 misses.
- **Phase 7**: T064 only if T061 or T063 passed. T065 after the release.
- **Polish (Phase 8)**: after the stories being shipped. T069 can run any time after Phase 5.

### Within Each Story

- Tests first, and the R-3, R-4 and R-6 tests must fail first.
- Pure types in RekkertCore, then transports and the store, then views.
- The story is complete when its checkpoint holds.

### Parallel Opportunities

- **Phase 2**: T002, T004, T005 and T007 are all different files.
- **US1 tests**: T012–T016 are all different files.
- **US2**:
  - tests T023–T027, T030 and T031 run together;
  - after them, T032, T033, T034, T036, T040 and T042.
- **US3**: T044, T045, T046 and T048 run together, and T051 and T052 (phone and watch views) run together.
- **Phase 6**: T054 and T056 run together.

---

## Parallel Example: User Story 2

```bash
# Tests first, together:
Task: "ClockBoundsTests in Packages/RekkertKit/Tests/RekkertCoreTests/ClockBoundsTests.swift"
Task: "SharingSummaryTests in Packages/RekkertKit/Tests/RekkertCoreTests/SharingSummaryTests.swift"
Task: "LinkRecordTests additions in Packages/RekkertKit/Tests/RekkertCoreTests/LinkRecordTests.swift"
Task: "WireCompatibilityTests in Packages/RekkertKit/Tests/RekkertCoreTests/WireCompatibilityTests.swift"
Task: "EventTimeTests additions in Packages/RekkertKit/Tests/RekkertCoreTests/EventTimeTests.swift"

# Then the pure types, together:
Task: "MatchEvent.stamp to 0.01 s in Packages/RekkertKit/Sources/RekkertCore/Sync/MatchEvent.swift"
Task: "ClockBounds and ClockBook in Packages/RekkertKit/Sources/RekkertCore/Sync/"
Task: "LinkRadio, radio, detail, pointArrived(nil) and battery in Packages/RekkertKit/Sources/RekkertCore/Sync/LinkRecord.swift"
```

## Parallel Example: User Story 3

```bash
Task: "Phone wording in App/Sources/Views/{ShareCodeSheet,SharingSection,RootView,JoinMatchSheet}.swift"
Task: "Watch wording in WatchApp/Sources/Views/{WatchSharingCard,WatchRootView,WatchCourtPage,WatchGuestsView,WatchEndOfMatchQuestion,WatchJoinView}.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1, proven with User Story 2)

1. Phase 1, then Phase 2: the baseline and the simulation.
2. Phase 3 (User Story 1): no echo, one hello per link change, a looser Wi-Fi link. **Stop and
   validate**: `BusyHallTests` meets FR-010 in the simulation.
3. Phase 4 (User Story 2): delays, radios and summaries in every build.

Steps 2 and 3 together are the MVP: faster points that the record can prove. Ship them as the
TestFlight build of T057 (the limit is still 7).

### Incremental Delivery

1. **MVP** (US1 + US2): the slowness the players feel today is gone, and measured.
2. **User Story 3**: "N of M", the limit carried to every screen, and a full match ending a
   wrist join. It can ship at limit 7 with no harm.
3. **User Story 4**: the field run and calibration decide the limit.
4. **Phase 7**: nine guests, if the prediction allows. Then the two-court evening confirms it.

### Circuit Breaker

If T061, and T063's re-run, miss FR-010 at nine guests, the release ships Phases 3–5 at
limit 7. The numbers go back to `.specify/assessments/session-sharing-limits/` for a decision
between Options B and C (concept.md).

---

## Notes

- **[P]** tasks touch different files and depend on no unfinished task.
- **[Story]** labels map each task to its user story, for traceability.
- **Commits** follow the conventional style in the history, with no AI trailers (constitution,
  Development Workflow).
- **The manual tasks** are T057, T058, T065 and the second half of T059. Each writes its
  evidence into `validation.md`.
- **Raw field records stay with the requester.** Only the trimmed fixture in T060 is committed.

---

## Phase 9: Convergence

- [X] T071 Count a link that ends by timing out (`wroteOff`, `redialled`) as a drop on its radio in `SharingSummary`, as FR-007 counts any connection ending, and pin it in `CoreTests/SharingSummaryTests.swift` per FR-007 (partial)
- [X] T072 Record `path unsatisfied` when a ready Wi-Fi link goes to `.waiting` in `RekkertSync/LocalNetworkTransport.swift`, closing it with `DropDetail.pathUnsatisfied` as its detail, so a lost path is told apart from a keepalive timeout per plan D-3 (partial)
- [X] T073 Tell the watch "no room", with the limit, when its phone is turned away from a full match it joined from the phone, within 15 s, in `RekkertSync/WatchStandIn.swift` and `WatchApp/Sources/Views/`, with a test in `SyncTests/LimitReachesWatchTests.swift` per FR-013 (partial)
- [X] T074 Turn a host's `needsUpdate` into a plain "update Rekkert to join" refusal on the guest's phone and watch: a `SharingFailure` and `LocalNetworkTransport.Failure` case, the store calling `onRefused`, and wording in `JoinMatchSheet` and `WatchJoinView`, with a test that fails first, per FR-015 (partial)
- [X] T075 Make `Calibration.replay` in `SyncTests/Calibration.swift` a true replay: each guest's taps at the times the record shows (arrival minus delay), and each guest out of range from `outOfReach` to `backInStep` and each link dropped as recorded, per FR-017 (partial)
- [ ] T076 Once T060 pins `Airwaves.Settings.calibrated`, run `ClockOffsetTests` on calibrated busy-hall speeds with FR-006's 10% cap asserted, and if it fails, tighten the bounds (for example the far end's receive and send times in the `clock` answer) per FR-006 (partial)
- [ ] T077 Once T060 pins `Airwaves.Settings.calibrated`, move `BusyHallTests` and `ClubNightTests.twoCourtsFullHalfAnHour` onto it and turn FR-010's and FR-011's known issues into firm assertions, at the current limit whether or not Phase 7 runs, per FR-020 (partial)
- [X] T078 Add `SyncTests/OlderHostTests.swift`: a guest from this release on a host acting as 1.1 follows every point, is never sent a `clock` question, and records relayed delays as `unknown; older`, per FR-015 (partial)
- [X] T079 Review the 20-arrival minimum on FR-011's 5-second share in `CourtHarness.DelayStats.enoughForAShare`: get it into spec.md through `/speckit-clarify`, or remove it from `BusyHallTests` and `ClubNightTests`, per FR-011 (unrequested)
- [X] T080 Bring spec.md's assumption that delays are bounded from the round trips points already make in line with D-2 (revised), the dedicated `clock` exchange, through `/speckit-clarify` or `/speckit-specify` per plan D-2 (contradicts)
- [X] T081 Add the typical delay and the share within 2 s to the record screen's stint header (`SharingSummary.headerLines`, `contracts/screens.md`) per FR-003 (partial)
- [X] T082 Put the radios up to the host on the guest's `joined` entry in `RekkertSync/SharedSession.swift` per FR-002 (partial)
- [X] T083 Add a test that a two-hour evening with ten people's delay entries fits in the record, exports and parses back, and is still pruned after 7 days, per Edge Cases: a long evening (missing)
- [X] T084 Add a test that a guest's watch standing in for its phone gets points within FR-010's times in `CourtHarness`, per Edge Cases: a watch standing in (missing)
- [X] T085 List `SharingSignal.state(_:limit:)` in `contracts/wire-protocol.md`'s changed messages per plan: wire contract (partial)
