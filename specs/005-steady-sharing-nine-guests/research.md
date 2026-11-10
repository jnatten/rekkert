# Research: Steadier, Measurable Sharing for Two Full Courts

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Date**: 2026-11-10

The assessment in `.specify/assessments/session-sharing-limits/` holds the field evidence: the
exported sharing records from 4, 8 and 9 November. This file holds what the code does today, and
the decisions.

Every finding below is marked:

- **VERIFIED**: the code path was read through and confirmed;
- **SUSPECTED**: the code allows it, but whether it happens depends on platform behaviour or
  timing.

Paths are relative to `Packages/RekkertKit/Sources/` unless they start with `App/`, `WatchApp/`,
`Shared/` or `Tests/`. Short names:

| Short name | File |
|---|---|
| MS | `RekkertSync/MatchStore.swift` |
| FO | `RekkertSync/FanOutTransport.swift` |
| LN | `RekkertSync/LocalNetworkTransport.swift` |
| RC | `RekkertSync/Radio/RadioCore.swift` |
| BT | `RekkertSync/BluetoothTransport.swift` |
| LR | `RekkertCore/Sync/LinkRecord.swift` |
| T | `Packages/RekkertKit/Tests/RekkertSyncTests` |

## Part 1: What the code does today

### R-1 · The record cannot say how late a point was, or over which radio

- **Delay is only recorded in debug builds.** `pointArrived(latency:)` is noted in `relay()` for
  each new point, inside `#if DEBUG` (MS:2137-2148). Spec 001 added it for its field test; no
  reason for keeping it debug-only is written down (`specs/001-fix-session-sharing/data-model.md:132-133`).
  VERIFIED
- **The delay subtracts two devices' clocks.** It is `now() − event.at`. `event.at` is stamped
  by the device that tapped, on its own clock (MS:248-251, 1411-1414; `RekkertCore/Sync/MatchEvent.swift:80-84`).
  The host relays a guest's point to the other guests (MS:1506-1512), so the device that tapped
  is often not even connected to the one receiving. VERIFIED
- **Tap times are rounded to 0.1 s** (`MatchEvent.stamp`, `MatchEvent.swift:121-126`). That
  alone is ±0.05 s, half of FR-006's budget. VERIFIED
- **No clock reading travels between devices.** The hello, guest card, seal nonces, Bluetooth
  greeting and Bonjour TXT record carry none (`RekkertCore/Sync/Wire.swift:198`;
  `RekkertCore/Sync/ShareAccess.swift:118-123`; `RekkertSync/LinkSeal.swift:37`; RC:9-18;
  LN:205-208). The only timestamps, `issuedAt`, go one way between a phone and its watch
  (Wire.swift:102, 141). VERIFIED
- **There is a round trip to carry one.** Every push to a link is `.events` answered by
  `.hello` (MS:1526-1557, 1737), and the host pushes every point to every guest. VERIFIED
- **No link knows its radio.** `LinkID` is a fresh UUID (Wire.swift:264-268). `InboundPacket`
  and `LinkChange` carry no radio (Wire.swift:274-299). The fan-out drops which child a packet
  came from (FO:113-121), though it can find a link's child while the link is up (FO:189). Both
  radios are attached as the same `.sharedSession` scope (`Shared/AppModel.swift:68-76`).
  VERIFIED
- **Every drop on the local network is `closedByPeer`, and the error is thrown away.** That
  covers any non-TLS failure, end of stream, a receive error and a frame that won't decode
  (LN:541-542, 687-690, 704, 707-708). Bluetooth uses the same reason for any disconnect
  (RC:582, 797, 907). VERIFIED
- **Sessions in the record are matches, not sharing.** An entry's session is the match's
  `log.sessionID` (`RekkertSync/SharedSession.swift:299`). Since spec 004, sharing lasts across
  matches. VERIFIED
- **Size.** The record is JSONL, one file per device per day, pruned after 7 days, with no size
  cap (`RekkertSync/LinkRecorder.swift:51-60, 111-126`; LR:152). A delay entry for every arrival
  at a ten-person, two-hour evening is about 320 entries and about 85 KB per device. The watch
  re-sends all its day files on every pair reconnect (`LinkRecorder.swift:59, 88-93`).
  VERIFIED (size SUSPECTED, hand-counted)

### R-2 · Why the second link drops: the operating system ends it, not this code

- **No app timer closes a local-network link once it is up.**
  - `dialTimeout` only applies before ready (LN:588-595).
  - `searchTimeout` only applies before the first join (LN:270-287).
  - A reply timeout fails the request but keeps the link (LN:745-748).
  - The app's own hang-ups are labelled `hungUp` or `timeout` (LN:365, 579), and none appear in
    the field records.

  VERIFIED
- **TCP keepalive is the likely cut.** Idle is 2 s, the interval 2 s and the count 3, so a
  link with no acknowledgement for about 8 s is failed (LN:459-469). The other way out is the
  OS failing the connection when the peer-to-peer Wi-Fi path goes. Both ends count from the same
  last exchange, so both see the drop within about 2 s, which matches the field records.
  SUSPECTED
- **Peer-to-peer Wi-Fi pauses for several seconds.** Likely triggers are switching channels,
  scanning while not on a network, sharing the chip with Bluetooth, and an app suspended in a
  bag. The drops that hit two guests within a second point to something on the host.
  SUSPECTED (platform)
- **Redial is immediate.** A guest redials at once if the browser still lists the host, or
  rebuilds the browser after 2 s (LN:626-641, 668-683). Each new link sends the whole snapshot,
  one way (LN:535-537). VERIFIED

### R-3 · Each drop sets off a full round of sync on every link

- **Every local-network link going up or down announces reachability** (LN:538, 624). The
  fan-out passes on any child's change (FO:123-127, 324-326).
- **The store answers each change with a full `synchronise()`** (MS:1344-1386). That is:
  - a hello on every link of both radios;
  - the snapshot, forced;
  - presets, display and haptics;
  - the access table on the host;
  - on a guest, a guest card on both links, each answered by the access table
    (MS:651-671, 1908-1910).

  Rounds are merged, but each can take up to 4 s.
- **This is a lot of traffic.** With N guests each dropping about 60 times an hour, the host
  runs about 120N rounds an hour. Each puts N hellos and N access tables on the shared
  Bluetooth queue.
- **A quiet guest's 10-second idle hello also leads to a round** (`RekkertSync/Radio/LinkLiveness.swift:9`;
  RC:288-299).

The code path is VERIFIED; how much this costs is SUSPECTED. This is the most likely reason
points felt slow with every guest still holding a link.

### R-4 · A guest on both radios sends the host's points back to it

- **`push` leaves out only the link a point came on** (MS:1506-1513). A guest that hears a host
  point over Wi-Fi first writes it back to the host over Bluetooth. The host drops the duplicate
  by event id (MS:2138; `RekkertCore/Sync/MatchLog.swift:85-92`), but still answers with a full
  hello (MS:1738). VERIFIED
- **The cost doubles.** A guest on both radios costs about 10 Bluetooth chunks per point,
  against about 5 for a guest on Bluetooth alone. SUSPECTED (estimate)

### R-5 · What one point costs the host's Bluetooth

- **Each frame is sealed per guest as it goes out.** That adds about 46 B per frame and 1 B per
  chunk (RC:500-506; `RekkertSync/LinkSeal.swift:68-75`; `RekkertSync/Framing.swift:34`;
  `RekkertSync/Chunking.swift:15`).
- **Chunk size.** Chunks use the connection's `maximumUpdateValueLength`, capped at 512. 20 B
  is only a fallback (BT:117, 218-220; RC:141). A point is about 290 B sealed, so 2 chunks at
  182 B.
- **One transmit queue serves every guest.** It goes round-robin, one chunk per guest per turn,
  with handshake ahead of live ahead of catch-up (BT:215; RC:601-609;
  `RekkertSync/Radio/HubScheduler.swift:9-62`).
- **Guest writes wait for a response, one at a time** (BT:359; RC:541-562).
- **A live push not started within 4 s is dropped and left for the retry** (RC:496-499;
  `RekkertSync/LinkReplies.swift:27-33`). The retry runs every 4 s, with a patience of up to 8
  (MS:94-95, 1316-1330).

The structure is VERIFIED; the byte counts are SUSPECTED. Delay per point grows linearly with
the number of guests, plus whatever traffic from R-3 and R-4 is already ahead in the queue.

### R-6 · The limit, and what the guest after it sees

- **The limit is enforced in one place:** `guard all.count < Self.limit` at
  `RekkertCore/Sync/ParticipantState.swift:75`, which reads `limit = 7` at :34. Counting matches
  a guest's id, devices and `pairedTo` (:52-85). The host's own watch is never counted
  (MS:544). VERIFIED
- **Seven is hard-coded in text:**
  - the phone at `App/Sources/Views/JoinMatchSheet.swift:256`;
  - the watch at `WatchApp/Sources/Views/WatchJoinView.swift:213`;
  - a comment at MS:657;
  - `README.md:745-746`.

  There are no string catalogues. Tests assert seven in `ParticipantStateTests.swift:44-58`,
  `CapacityTests.swift:53-117`, `IncidentTests.swift:57-130` and `ClubNightTests.swift:15-22`.
  VERIFIED
- **The watch does not know the limit.** `HostingStatus` carries participants but no limit
  (Wire.swift:132-165), so "N of M" cannot be shown there today. VERIFIED
  - The phone shows "N guests joined" (`App/Sources/Views/ShareCodeSheet.swift:113-119`) and
    "N on" (`App/Sources/Views/SharingSection.swift:46-51`).
  - The watch shows "N on" (`WatchApp/Sources/Views/WatchSharingCard.swift:18`, `WatchRootView.swift:382`).
    `WatchCourtPage.swift:75-76` leaves out guests who are out of reach.
- **A wrist join can lose "match is full".** When the phone answers `.noRoom` while the watch
  waits on it, the watch looks for the host itself (`RekkertSync/WatchStandIn.swift:57-60`).
  If it hears nothing, it can give up after up to 20 s with `.notFound` (:12, 63-64, 491-495),
  which breaks both the 15 s limit and the wording. `StandInPolicy.Status` has no "full" case
  (:144-153). The path is VERIFIED; the timing breach is SUSPECTED.

### R-7 · Older versions

- **Bluetooth needs an exact version match.** The greeting is version 3, and a guest that sees
  another version ignores that host and scans on (RC:17, 963-965, 1043-1058). VERIFIED
- **The local network still advertises `v = "1"`**, unchanged since 1.0 (LN:206, 479). VERIFIED
- **An older build cannot read a new `Wire` case.** It fails to decode and is answered with a
  hello (MS:1667-1671). A new optional field on an existing case is skipped by older decoders.
  VERIFIED
- **1.0 over the local network** (SUSPECTED):
  - it connects, because the pre-shared key is unchanged;
  - it cannot read `noRoom`, so when the match is full it redials in a loop;
  - an event kind it does not know fails the whole batch, so it shows as catching up while
    getting nothing.

  1.1 understands every message the host sends today.
- **Nothing tells a host which build a guest runs.** No refusal means "please update". VERIFIED

### R-8 · The simulation

- **It has no Wi-Fi link.** The harness passes `LocalNetworkTransport()`, which on macOS is an
  empty stand-in (`T/CourtHarness.swift:141`; LN:776-806). `SharedSession` takes that concrete
  type (`SharedSession.swift:113, 159`). VERIFIED
- **It models no jitter, repeated drops, busy airspace or clock offset.** Delay is a fixed
  30 ms, and every device reads one clock (`T/SimulatedRadio.swift:11, 177, 284`;
  `T/CourtHarness.swift:92, 136, 143`). VERIFIED
- **What it does model** (`T/SimulatedRadio.swift:10-24, 94-96, 246-305`), all VERIFIED:
  - one send queue per host, with K slots;
  - throughput per host queue and per guest write;
  - a cap on chunk size and on connections;
  - seeded random loss, host to guest only;
  - test-driven drops, suspension, relaunch and address rotation.
- **The store's own timers run on real time, not the test clock**, only shortened (MS:1270,
  1318, 1650-1661, 2538; `T/CourtHarness.swift:14-15, 137`). A retried point's simulated delay
  therefore depends on the machine. SUSPECTED
- **Delays are pooled across devices.** `arrivalTimes()` loses which device each one belongs
  to, includes the scorer at one step, and leaves out points that never arrived
  (`T/CourtHarness.swift:287-300`). VERIFIED
- **The seven-guest test is slow.** The two-court test (`T/ClubNightTests.swift:19-41`) runs
  150 points over 30 simulated minutes and took 155.5 s on CI on 2026-11-10. The whole package
  job took about 8 of its 60 minutes (`.github/workflows/test.yml:24`). VERIFIED
- **Nine guests on two links in a busy hall** at 50 ms steps is estimated at 15–20 minutes per
  test. SUSPECTED
- **The record parser already exists.** `LinkRecord.parse` reads exported rows, including
  `pointArrived` (LR:206-246; `Tests/RekkertCoreTests/LinkRecordTests.swift:81`). The test
  target has no resources (`Package.swift:26-30`). VERIFIED

### R-9 · Battery

- **Nothing in the code reads battery level** (no `batteryLevel` or
  `isBatteryMonitoringEnabled` anywhere). Spec 001's battery measurement (SC-012) depended on
  the field test that was skipped. VERIFIED

## Part 2: Decisions

### D-1 · Point delays in every build, with taps stamped to the hundredth (FR-001, FR-006)

- **Decision**:
  - Drop the `#if DEBUG` around `pointArrived` (MS:2143-2148).
  - The kind becomes `pointArrived(latency: TimeInterval?)`, where `nil` is written as
    `unknown` (D-2).
  - It is noted on the device the point first arrived at, as now. "First" means new to the
    log, so a point heard over both radios counts once.
  - `MatchEvent.stamp` rounds to 0.01 s instead of 0.1 s.
- **Rationale**:
  - At 0.1 s, rounding alone uses half of FR-006's budget.
  - `at` is written once by the author and copied verbatim, so every device still sees the
    same value. Principle II is untouched: no reducer, draw or schedule reads the extra digit.
  - Hundredths cost about one byte more per event, and older builds decode the date the same
    way.
- **Alternatives considered**:
  - A separate precise tap time beside `at`. Rejected: two times for one tap, and more bytes
    than one extra digit.
  - Keeping 0.1 s and lowering the accuracy goal. Rejected by the clarified spec.

### D-2 · Clock offsets from the round trip that already happens (FR-006)

- **Decision**:
  - **The reply carries the replier's clock.** `.hello` gains an optional `clock: Date?`, set to
    the replier's time t₂. The sender times its request (t₁) and the reply (t₄) around
    `sendLive` in `deliver()`.
  - **Each sample bounds the offset.** The offset to that device lies in [t₂ − t₄, t₂ − t₁].
    The estimate is the midpoint, with an error of at most half the round trip.
  - **A pure `ClockBounds` value in RekkertCore** keeps the narrowest recent sample per device.
    It widens by an assumed 50 ppm drift as the sample ages, and composes across hops by adding
    half-widths.
  - **The host passes on the authors' offsets.** It adds an optional
    `offsets: [DeviceID: ClockBounds]?` to each `.events` push, giving its estimate for each
    event's author. A guest receiving a point relayed from another guest then adds its own
    offset to the host.
  - **The watch uses the same scheme.** Its hello to its phone carries `clock`, and the watch
    adds the phone's offset to whatever the phone passed on.
  - **A delay is `unknown` when the error could exceed 0.1 s.** That is when half-widths plus
    0.005 s of rounding exceed 0.1 s.
- **Rationale**:
  - It needs no new message and no version bump: optional fields on two existing cases, which
    older builds skip (R-7).
  - Samples come with every point, so they stay fresh.
  - A two-hop path with 60 ms round trips is within ±65 ms.
- **Alternatives considered**:
  - **Trusting each device's system clock.** Rejected: there is no way to know the error with
    no network at court, and FR-006 forbids a wrong number.
  - **A dedicated time-sync message.** Rejected: it is extra traffic on the queue R-5 says is
    the bottleneck.
  - **Measuring from when the host first had a point.** Rejected: the spec counts from the tap.

### D-3 · Each link names its radio, and drops say why (FR-002)

- **Decision**:
  - **A new `LinkRadio` enum**, with the cases `bluetooth` and `wifi`, in RekkertCore.
  - **Each shared-session child reports its radio.** `RadioCore` reports `bluetooth` and
    `LocalNetworkTransport` reports `wifi`.
  - **The fan-out answers which radio a link is on.** It records the child's radio when the link
    comes up and answers `radio(of: LinkID)`. The store caches it with `farEnds` at first proof,
    so a drop can still be named after the link is gone.
  - **`LinkRecordEntry` gains two optional fields**:
    - `radio: LinkRadio?`;
    - `detail: String?`, holding one short code for a local-network drop: `ETIMEDOUT`,
      `ECONNRESET`, `ECONNREFUSED`, `ENETDOWN`, `path unsatisfied`, `tls`, `dns` or `other`.
      A pure, tested `DropDetail` mapping in RekkertSync picks the code. The error's own
      description text never reaches the record, because it can carry endpoint details
      (FR-004).
  - **Reach entries list the radios that were up.** The host's `outOfReach` and `backInStep`
    are per guest, not per link, so they list every radio that was up when noted.
- **Rationale**:
  - The field analysis had to infer the radio from one guest's `radioOff`.
  - The error detail is what tells keepalive from a lost path, which is the open question
    behind D-7.
  - Both fields are optional, so older records still decode.
- **Alternatives considered**:
  - Putting the radio in `LinkID`. Rejected: every transport and test that builds a `LinkID`
    would change, for no gain over a lookup.

### D-4 · A summary per sharing stint (FR-003, SC-007)

- **Decision**:
  - **A pure `SharingSummary` in RekkertCore**, with `LinkRecord.summaries()` computing it from
    the entries.
  - **A stint runs from `sharingStarted`, `sharingRestored` or `joined`** to `sharingStopped`,
    leaving, or the end of the day's file. It is not per match, because sharing has outlived
    matches since spec 004.
  - **It holds**:
    - the points received;
    - the number with a known delay, with their median and slowest;
    - the share within 1 s and within 2 s;
    - drops per radio;
    - unreachable time per far device.
  - **Export prints it as indented lines** at the start of each stint. The parser already skips
    lines it cannot read (LR:233-246).
  - **`SharingRecordView` shows it as a section header** above that stint's entries.
- **Rationale**: SC-007 asks that the owner can read the answer without a developer. A summary
  turns about 650 delay lines into four numbers.
- **Alternatives considered**: summarising per match. Rejected: one sharing evening covers
  several matches, and a summary per match splits the answer up.

### D-5 · No echo: a point goes back to no device that sent it (FR-008, R-4)

- **Decision**:
  - `push` leaves out every link whose far end is the device the events came from, not only the
    link they came on. It uses `farEnds` (MS:1506-1513).
  - Events arriving on one link mark them as held on every sibling link to the same device.
- **Rationale**:
  - It roughly halves the Bluetooth chunks per point for guests on both radios.
  - Principle II is safe: it only skips events that device provably holds, and the hello still
    catches up anything missed.
- **Alternatives considered**: deduplicating at the far end only. That is already done, and it
  does not save the airtime.

### D-6 · A link going up or down costs one hello on that link, not a round on all of them (FR-008, R-3)

- **Decision**:
  - **A child's link change wakes only that link.** It is no longer passed on as a store-wide
    reachability change unless overall reachability, or the pair's, actually changed (FO:123-127,
    324-326).
  - **A newly proven link gets a hello on that link only**, which brings its catch-up.
  - **`access` and `guestCard` go out on first proof of a device, or when they change.** They no
    longer go out on every re-proof (MS:651-671, 1251-1264, 1344-1360).
  - **Periodic anti-entropy stays as it is**: the nudge, the retry and the idle hello.
- **Rationale**: R-3 is about 120N rounds an hour of avoidable traffic on the shared queue. A
  dropping link then costs one hello on its own link.
- **Alternatives considered**: rate-limiting `synchronise()`. Rejected: it delays real catch-up
  just as much as the needless kind.

### D-7 · Find out why the Wi-Fi link drops, time-boxed, and loosen keepalive (FR-007)

- **Decision**:
  1. **Ship D-3 first** (radio and error detail), and read the cause in the small field run's
     records.
  2. **Loosen the local network's TCP keepalive** from about 8 s to about 20 s (idle 5 s,
     interval 3 s, count 5; LN:462-465), so a pause in peer-to-peer Wi-Fi does not end the link.
     While a guest has Bluetooth up as well, it notices a dead Wi-Fi link later at no cost,
     because points go on over Bluetooth (D-5, D-6).
  3. **A guest on Wi-Fi alone still notices a dead link** through the store's own liveness: the
     10 s idle hello and three misses, as Bluetooth already does. The local network has no miss
     counter today (LN:745-748). It gains one by reusing `LinkHealth`
     (`RekkertSync/LinkReplies.swift:41`), which `LinkHealthTests` already pins, so no
     untested rule is added (Principle III).
  4. **The time box is two days of investigation after the small field run.** If the records
     then show drops caused by something no setting changes, the work stops there. The drops
     are reported against FR-007's target, which is not a release gate, and FR-008 and FR-010
     still hold through D-5 and D-6.
- **Rationale**:
  - Keepalive is the only app-controlled cut that fits the field records (R-2).
  - It is a one-line change, and the records will say whether it worked.
- **Alternatives considered**:
  - **No Wi-Fi redial while Bluetooth is up.** Rejected: it ends the churn, but moves all the
    load onto the Bluetooth queue that scales worst (R-5).
  - **One radio per guest.** Rejected for the same reason.

### D-8 · Wi-Fi first with Bluetooth as fallback: deferred, behind the measurements

- **Decision**:
  - For now, keep sending each point on every link a guest has. The first to arrive wins, and
    after D-5 and D-6 the cost is the point and its hello, once per radio.
  - Only if the calibrated nine-guest simulation (D-11) misses FR-010 does the host send on
    Wi-Fi first, and on Bluetooth only when Wi-Fi has not answered within 300–500 ms.
- **Rationale**:
  - Sending on both links is what gives speed when one is pausing.
  - The fallback adds state and a delay whenever Wi-Fi is quietly dying. It is only worth it if
    the Bluetooth queue is the limit.
- **Alternatives considered**: adopting it now. Rejected: there are no numbers yet to say it is
  needed.

### D-9 · Coming back after the host's Bluetooth restarts (FR-009)

- **Decision**:
  - No product change is expected: the field records show every guest back within 7 s.
  - A simulated test turns the host's radio off for 2 s and on again with four guests, and
    asserts every guest is back in step within 10 s.
  - The record already notes `radioOff` and `radioOn`, and they gain the `bluetooth` radio
    (D-3).
- **Rationale**: FR-009 pins today's behaviour so later changes cannot lose it.

### D-10 · A simulation that can show the problem (FR-020, User Stories 1 and 3)

- **Decision**: all changes are in the test target, with no product code:
  - **A second link per guest.** The harness gives each phone a second `SimulatedRadio` on a
    separate `Airwaves` standing in for Wi-Fi, with its own `RadioCore` attached as
    `.sharedSession` in `boot` (`T/CourtHarness.swift:120-124`).
  - **Drops on that link.** A seeded `Flapper` drops and restores it with the field numbers:
    - up for a median of 43 s (90th percentile 127 s);
    - down for a median of 4.1 s (90th percentile 10.9 s);
    - a third of drops shared with another guest.
  - **A busy hall.** `Airwaves.Settings` gains:
    - `jitter`;
    - `busyAir`, a factor on `bytesPerSecond`;
    - bursty loss;
    - loss on guest writes.
  - **Clock offsets.** Each simulated device has its own clock offset and drift, so D-2 is
    tested against known errors.
  - **Delay per device.** Arrival times are kept per device. The scorer is left out, a point
    that never arrives is a failure, and a helper gives the median, 95th percentile and
    slowest.
  - **Faster runs.** `TestClock` gains `nextDue`, and the harness steps to whichever comes
    first: the next due timer or the step. The 12 s gaps between points then cost almost
    nothing. The step is 50 ms, so 1-second targets mean something.
- **Rationale**:
  - The Wi-Fi stand-in is a Bluetooth core, so it tests how the store copes with a second link
    that keeps dropping, which is the code D-5 and D-6 change. It does not test
    `LocalNetworkTransport`, which only builds for iOS. Field runs cover that.
  - With `nextDue`, the nine-guest test should fit inside `verify.sh`. If the package tests
    pass 30 minutes on CI, the sync suites are split across parallel CI jobs, each running
    `verify.sh`'s test step on a filter. `verify.sh` stays the definition of green
    (Principle IV).
- **Alternatives considered**:
  - **A protocol for `SharedSession`'s local network**, so a fake can stand in. Deferred:
    larger, and only needed if the store-level stand-in misses something the field runs show.
  - **Moving the store's timers onto the test clock** (R-8). First deferred, then done during
    User Story 1: with the busy-hall suite running in parallel, `deliveryDoesNotSnowball`
    failed on real-time retries, and real-time waits hid the 1-second delays. `MatchStore` and
    `FanOutTransport` take an injectable `sleep`, which the harness runs on the radio's clock
    at the app's own timings.

### D-11 · Calibrating from a real run (FR-017, SC-006)

- **Decision**:
  - A `Calibration` helper in the test target reads an exported record with `LinkRecord.parse`.
  - The record from the small field run is kept in the test target as a Swift string fixture,
    trimmed, with its header line holding full device ids removed.
  - The helper fits `latency` from the fastest single-hop Bluetooth delays, and fits
    `bytesPerSecond` by replaying the run until the simulated 95th percentile matches.
  - A replay test asserts the fit is within 25% (FR-017).
  - The result is pinned as `Airwaves.Settings.calibrated`, which the nine-guest tests use.
  - The field run includes a burst, two guests walking out and back to force catch-up, so the
    queue is loaded enough to pin `bytesPerSecond`.
- **Rationale**:
  - It reuses the parser.
  - It stays device-free (Principle III).
  - With three guests the queue is barely loaded, so the burst is what makes the throughput
    figure meaningful.
- **Alternatives considered**: a script under `scripts/`. Rejected: the scripts are standalone
  files that cannot import the package.

### D-12 · Battery readings in the record (FR-019, SC-005)

- **Decision**:
  - **The record gains a `battery(level:)` entry.** It is noted when sharing starts and stops,
    and at most every 10 minutes in between, whenever the app is running anyway.
  - **`LinkRecorder` decides when to note a reading**, and is tested for it.
  - **The app shells only read the level and hand it over** whenever they run:
    `UIDevice.batteryLevel` on the phone, `WKInterfaceDevice.batteryLevel` on the watch. The
    shells hold no rule (Principle I), and RekkertSync stays free of UIKit and WatchKit.
  - **The summary shows the drain per hour for the stint.**
  - **The comparison without sharing is a run in the quickstart**: the same devices for an hour
    with sharing off and a workout on, read the same way.
- **Rationale**:
  - FR-019 asks for measured and reported, with no limit, so readings in the record are
    enough.
  - A battery level is not match or player data, and it stays on the device unless shared
    (Principle V).
- **Alternatives considered**: reading Settings → Battery by hand. Kept as a cross-check only:
  it is per app over 24 hours, and the watch shows no per-app use.

### D-13 · Nine guests, and "N of M" everywhere the count shows (FR-012–FR-014, FR-016)

- **Decision**:
  - **`Participants.limit` becomes 9**, in the change that follows a calibrated nine-guest
    simulation passing (FR-016). Until then it stays 7, and everything else ships.
  - **The limit travels with the count**:
    - `HostingStatus` gains `limit: Int?`, set at `SharedSession.swift:858-866`;
    - `noRoom` gains `limit: Int?`.
  - **The phone and watch views say "N of M on"** (contracts/screens.md). The hard-coded
    "seven" in `JoinMatchSheet` and `WatchJoinView` comes from the limit instead, and so does
    `README.md`.
  - **A full match ends a wrist join quickly.** `StandInPolicy.Status` gains `full`. A `.noRoom`
    heard by either half of the pair ends the wrist's join at once, with "Match is full", within
    15 s (R-6).
  - **Tests**: the capacity tests are parameterised on `Participants.limit`, and the two-court
    test runs nine guests.
- **Rationale**:
  - Nine is the scope: two full courts and two sitting out.
  - The test is what decides whether nine ship. Anything above nine is out of scope even if the
    simulation allows it.
- **Alternatives considered**: a limit set at run time from measurements. Rejected: it is not
  needed for the scope, and is harder to test.

### D-14 · Older versions stay on, and future breaks can be explained (FR-015)

- **Decision**:
  - **Everything on the wire stays additive**: optional fields only, and no new `Wire` case a
    1.1 guest would receive unasked. 1.1 guests keep working and are counted once.
  - **From this release, `hello` and `GuestCard` carry an optional `protocol: Int?`**, and
    there is a new refusal, `needsUpdate`. A later breaking change can then tell guests from this
    release on, plainly.
  - **Neither Bluetooth's greeting version nor the local network's TXT version changes.**
- **Rationale**: the requester accepts breaking changes, but this feature needs none.
- **Known limit**:
  - A 1.0 guest over Wi-Fi can still sit "catching up" while getting nothing, as it can today
    (R-7). The host shows it as catching up, not in step.
  - 1.0's own screen cannot be changed from here.
  - This is recorded as a risk in plan.md.

### D-15 · Field runs and evidence (FR-018, FR-019, SC-002–SC-006)

- **Decision**:
  1. **A TestFlight build with D-1 to D-7 and D-12** goes to the players.
  2. **The small field run** follows [quickstart.md](quickstart.md): a host and three guests in a
     hall, at least an hour, some with Wi-Fi on, with the walk-out burst and a battery
     comparison. Every phone's record is exported.
  3. **Calibration follows** (D-11), then the nine-guest decision (D-13).
  4. **After release, the first two-court evening confirms the limit** (FR-018), with its
     records kept.
  5. **Results go in `validation.md`.** The raw records stay with the requester, and only the
     trimmed fixture is committed.
- **Rationale**: the order of the spec's Option A, with the clarified release gate (Q3 → B).

## Open items that only real devices can settle

| Item | Covered by |
|---|---|
| Whether the Wi-Fi drops are keepalive or a lost path, and whether D-7 ends them | D-3 error detail; small field run |
| How many central connections one host phone holds in practice | Two-court evening after release; the record notes refusals and drops |
| Whether the calibrated simulation predicts nine guests well enough | Two-court evening after release (FR-018); the limit is lowered in the next release if not (FR-016) |
| Battery drain per hour with and without sharing | Small field run and two-court evening (D-12) |
| Whether the host's Bluetooth restarts more often under load | Records from both runs |
