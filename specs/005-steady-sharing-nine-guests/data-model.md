# Data Model: Steadier, Measurable Sharing for Two Full Courts

**Feature**: [spec.md](spec.md) · **Research**: [research.md](research.md)

Everything here is additive, except two changes:

- tap times are rounded to the hundredth instead of the tenth;
- the participant limit goes from 7 to 9 once FR-016 allows.

Nothing in the reducer, the draws, the schedules or the version vectors changes (Principle II).
New types are pure values in `RekkertCore` unless marked otherwise.

## Changed: `MatchEvent.stamp` (D-1)

| | Before | After |
|---|---|---|
| Rounding of `at` | 0.1 s | 0.01 s |

- `at` is still written once, by the device that tapped, and copied verbatim everywhere.
- Older builds decode the date unchanged.
- No rule reads the extra digit.

## New: `LinkRadio` (D-3)

| Case | Meaning |
|---|---|
| `bluetooth` | A link over `RadioCore` / `BluetoothTransport` |
| `wifi` | A link over `LocalNetworkTransport`: a shared network or peer-to-peer Wi-Fi |

The phone↔watch link is `pair`, as today, and has no radio.

## Changed: `LinkRecordEntry` (D-3, D-12)

| Field | Type | Change | Notes |
|---|---|---|---|
| `id`, `time`, `device`, `session`, `link`, `kind` | as today | — | |
| `radios` | `[LinkRadio]?` | **new**, optional | The radio a host or guest link entry is about, or every radio up to that device for a reach or delay entry; both are written `bt+wifi`. Absent on `pair` and `radio` entries, and in older lines |
| `detail` | `String?` | **new**, optional | One code from `DropDetail` (below) for a local-network drop. Never the platform's description text, a name, a score or a code |

Older lines decode with both fields absent. An older phone drops a newer watch's lines it cannot
decode, as it does today.

## Changed: `LinkEvent` kinds (D-1, D-3, D-12)

| Kind | Change | Text form |
|---|---|---|
| `pointArrived(latency: TimeInterval?)` | latency is now optional, and noted in every build, for point taps only, not undos or corrections. An unknown delay for a point from, or relayed through, a 1.1 device carries `detail: "older"` | `pointArrived(0.412s)`, `pointArrived(unknown)` or `pointArrived(unknown; older)` |
| `battery(level: Double)` | **new**, level 0…1. `LinkRecorder` decides when to note one: when sharing starts or a join completes, when it stops or the guest leaves, and otherwise only when 10 minutes have passed since the last. The app shells only hand it the level | `battery(83%)` |
| `outOfReach`, `backInStep` | unchanged kind; the entry's `radios` list the radios that were up | — |
| everything else | unchanged | — |

The exact rows are in [contracts/sharing-record.md](contracts/sharing-record.md).

## New: `ClockBounds` (D-2)

What one device knows about another device's clock: the far device's clock minus the near
device's lies in `[lower, upper]`.

| Field | Type | Notes |
|---|---|---|
| `lower` | `TimeInterval` | t₂ − t₄ from the sample |
| `upper` | `TimeInterval` | t₂ − t₁ from the sample |
| `sampledAt` | `Date` | The near device's time at t₄ |

Rules, each pinned by `ClockBoundsTests`:

- **`estimate`** is the midpoint, and **`halfWidth`** is half of `upper − lower`.
- **`aged(at:)`** widens both ends by 50 ppm of the time since `sampledAt`.
- **`narrower(than:at:)` keeps the better sample.** A new sample replaces the kept one when its
  aged half-width is smaller.
- **`contradicts(_:)`**: two bounds that do not overlap cannot both be true, so one far clock
  changed between them.
- **`composed(with:)`** chains two hops. The near device's bounds on B, plus B's bounds on A,
  give the near device's bounds on A: the estimates and the half-widths both add.
- **`delay(arrivedAt:tappedAt:)`** returns `arrivedAt − (tappedAt − estimate)`. It returns
  `nil` when `halfWidth + 0.005 > 0.1`, which is FR-006.

## New: `ClockSpan` (D-2)

Bounds as they travel in a push's `offsets`: `lower` and `upper` in whole milliseconds,
encoded as `[lower, upper]`. Made from `ClockBounds` by rounding `lower` down and `upper` up,
so a span never claims more than was known. The receiver takes it as sampled when it arrived;
the sender aged it to the moment it sent.

## New: `ClockBook` (D-2)

- Per device, a `[DeviceID: ClockBounds]`, kept in memory by `MatchStore`. It is not
  persisted, because samples go stale anyway.
- It is updated from every reply that carries a reading (`.clock` or `.hello`), and from the
  `offsets` on every `.events` push, composed with the receiver's bounds on the sender.
- The watch keeps one too, with its phone's bounds as the first hop.
- It lives in `ClockBounds.swift`, beside the bounds it holds.
- A new sample that contradicts the kept one replaces it, however wide: the far clock changed.
- When this device's own clock changes (`NSSystemClockDidChange`), the book is cleared and every
  delay noted in the next 60 s reads unknown. Delays already in flight were timed partly on the
  old clock, and the first fresh samples can still be crossing the change.

## New: `DropDetail` (D-3, FR-004)

A pure mapping in `RekkertSync`, from the platform's connection error to one short code. The
record never holds the error's own description text, which can carry endpoint details.

| Platform error | Code |
|---|---|
| POSIX `ETIMEDOUT` | `ETIMEDOUT` |
| POSIX `ECONNRESET` | `ECONNRESET` |
| POSIX `ECONNREFUSED` | `ECONNREFUSED` |
| POSIX `ENETDOWN`, `ENETUNREACH` | `ENETDOWN` |
| The path stopped being satisfied | `path unsatisfied` |
| Any TLS error | `tls` |
| Any DNS error | `dns` |
| Anything else | `other` |

## New: `ArrivalConditions` (FR-010)

One rule in `RekkertCore`: whether nothing was wrong for one point arriving on one device. The
summary and the simulated tests both use it.

`nothingWrong(arrivalAt:on:from:entries:pairEntries:)` is true when both of these hold:

1. **The device had a connection up when the point arrived:**
   - a guest's phone: at least one `proven` link to the host not since `dropped`;
   - the host: a link to the guest the point came from;
   - a watch following its phone: its `pair` link up, and the phone met this condition at the
     same moment, read from `pairEntries`.
2. **Nothing went wrong recently.** In the 30 seconds before arrival, there is no
   `outOfReach` for that device (or for its phone, for a watch), and no `caughtUp` on it.

Rules pinned by `ArrivalConditionsTests`:

- one link up of two;
- every link down;
- out of reach 29 s before, and 31 s before;
- `caughtUp` within 30 s;
- the host's view of a guest;
- a watch whose phone was fine, and one whose phone was not.

## New: `SharingSummary` (D-4, D-12)

Computed by `LinkRecord.summaries()` from the entries of one device, with its watch merged in
on the phone.

| Field | Type | Notes |
|---|---|---|
| `start`, `end` | `Date` | One stint: from `sharingStarted`, `sharingRestored` or `joined`, to `sharingStopped`, leaving, or the last entry of the day |
| `role` | host / guest | From the stint's first entry |
| `points` | `Int` | `pointArrived` entries in the stint |
| `knownDelays` | `Int` | Those with a latency |
| `medianDelay`, `slowestDelay` | `TimeInterval?` | Over the known delays |
| `withinOne`, `withinTwo` | `Double?` | The share of known delays ≤ 1 s and ≤ 2 s, over arrivals where `ArrivalConditions.nothingWrong` holds (FR-010) |
| `unknownShare` | `Double?` | The share of points whose delay is unknown, leaving out `older` ones. Above 10%, FR-010 cannot be judged for that device (FR-006) |
| `judgeable` | `Bool` | Whether FR-010 can be judged: at least 100 timed points (FR-010), and `unknownShare` ≤ 10% |
| `drops` | `[LinkRadio: Int]` | `dropped` entries per radio, leaving out `dropped(radioOff)` from the host's own Bluetooth restarting (FR-007) |
| `hostRestarts` | `Int` | How many times the host's Bluetooth went off and came back by itself during the stint |
| `watchUpTo` | `Date?` | On the phone: up to when the watch's entries are included, when the watch has not been in touch since (FR-005) |
| `unreachable` | `[String: TimeInterval]` | Per far device, the 4-hex short name: summed `outOfReach` → `backInStep` time |
| `batteryPerHour` | `[Device: Double?]` | Drain per hour for the phone and the watch, from the first and last `battery` entries |

Validation: a stint with no points still summarises, with `nil` delays. A stint that never ends
in the file ends at its last entry.

## Changed: wire messages (D-2, D-13, D-14)

All the fields below are optional, so older builds skip them (research R-7). The details and
the compatibility rules are in [contracts/wire-protocol.md](contracts/wire-protocol.md).

| Message | New field | Sent by |
|---|---|---|
| `Wire.hello` | `clock: Date?`: the sender's time when it wrote the hello | Every build from this release |
| `Wire.hello` | `protocol: Int?`: this release's sharing protocol, `2` | Every build from this release |
| `Wire.events` | `offsets: [DeviceID: ClockBounds]?`: the host's bounds for each event's author | The host, on per-link pushes |
| `Wire.noRoom` | `limit: Int?` | The host |
| `GuestCard` | `protocol: Int?` | Guests from this release |
| `HostingStatus` | `limit: Int?` | Phone → its watch |
| `Wire.needsUpdate(sessionID:)` | **new case**: never sent by this release | Kept for a later breaking change (D-14) |

## Changed: `Participants.limit` (D-13)

| | Today | After FR-016 passes |
|---|---|---|
| `Participants.limit` | 7 | 9 |

- The counting rules do not change: one person counts once, a standing-in watch joins its
  phone, and the host's watch is not counted.
- Until the calibrated simulation passes with nine, the constant stays 7, and the tests are
  parameterised on it.

## Changed: a refused join keeps the limit (D-13)

| Where | Change |
|---|---|
| `MatchStore.noRoomLimit: Int?` | **new**: the limit in the last `noRoom` this device heard |
| `SharingSignal.state(_:limit:)` | **new** optional `limit`, set by the phone with `.failed(.noRoom)` so its watch can say how many fit |
| `WatchStandIn.joining` | Ends as `.failed(.noRoom)` when either half of the pair heard `noRoom`, within 15 s of the join, never `.notFound` |
| `WatchStandIn.fullLimit: Int?` | **new**: the limit the wrist heard, from its phone or its own search |

## Test only: `Airwaves.Settings` and the harness (D-10, D-11)

| Addition | Notes |
|---|---|
| `jitter: Duration` | Added to each hop, seeded |
| `busyAir: Double` | Factor on `bytesPerSecond`, for a busy hall |
| `burstLoss` | Seeded bursts of lost chunks |
| `sharedAirtime: Bool` | Every host on the same airwaves draws on one byte budget, so a second shared match on the next court competes for the air |
| `guestWriteLoss: Double` | Loss on guest → host writes |
| `calibrated` | Static settings from `Calibration` (D-11) |
| `Flapper` | Drops and restores a guest's second link on a seeded schedule from the field numbers |
| Per-device clocks | Offset and drift per simulated device, for `ClockBounds` |
| `arrivals(by device:)` | Delays per device, without the scorer, with points that never arrived counted as failures |
| `TestClock.nextDue` | Lets the harness skip to the next scheduled timer |

## Not in code: the field run

A field run is written up in `validation.md`:

- the devices and models, the place, and the length;
- who had Wi-Fi on;
- the burst;
- each phone's summary rows;
- the battery per hour with and without sharing;
- the calibration result.

The raw records stay with the requester. Only the trimmed calibration fixture is committed.
