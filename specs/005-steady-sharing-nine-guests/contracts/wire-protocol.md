# Contract: Wire Changes for 005

**Feature**: [../spec.md](../spec.md) · **Decisions**: [../research.md](../research.md) D-2, D-5, D-6, D-13, D-14

## Rules

- **Additive only.** Every change is an optional associated value or an optional field. A 1.1
  build decodes every message the host sends, skipping fields it does not know (research R-7).
- **Version markers stay put.** The Bluetooth greeting stays at version 3, and the
  local-network TXT record stays at `v = "1"`.
- **Two new `Wire` cases.** `needsUpdate`, which this release never sends, exists so a later
  breaking change can tell guests from this release on, plainly. `clock` is sent only to
  devices whose hello carried `protocol`, so no 1.1 build ever receives it.
- **Event formats are unchanged**, apart from `at` being rounded to the hundredth
  (data-model.md). Principle II is weighed in plan.md.

## Changed messages

| Message | Before | After | Who sets it | Who reads it |
|---|---|---|---|---|
| `hello` | `hello(sessionID:, vector:, from:)` | `+ clock: Date?`, `+ protocol: Int?` | Every sender from this release. `clock` is the sender's time when it encodes the hello | The other end, to time a round trip (D-2) |
| `events` | `events(sessionID:, events:)` | `+ offsets: [DeviceID: ClockSpan]?`, `+ stamps: [Stamp]?` | Every sender from this release, on every push. On a link, `stamps` say when a point tapped on a watch following its phone reached that phone; each device that passes one on rewrites it in its own clock. To a phone's own watch, `stamps` say when the phone had each point | The receiver, to bound the sender's clock and compose its offset to each event's author; and to time a point from where FR-010 or FR-010a starts |
| `snapshot` | `snapshot(log, role:, access:)` | `+ stamps: [Stamp]?` | A phone, to its own watch only: when it had the points of the last minute | The watch, to time the hop when the snapshot gets there before the push |
| `noRoom` | `noRoom(sessionID:)` | `+ limit: Int?` | The host | The guest's phone and watch, to say how many fit |
| `GuestCard` | `device, name, pairedTo, leaving` | `+ protocol: Int?` | Guests from this release | The host, to know which guests can understand `needsUpdate` |
| `HostingStatus` (phone → watch) | `…, participants, …` | `+ limit: Int?` | The host's phone | The host's watch, for "N of M on" |
| `sharing(.state)` (phone → watch) | `state(SharingState)` | `+ limit: Int?`, with `.failed(.noRoom)` | A guest's phone turned away from a full match | Its watch, to say how many the match takes, whichever device the code was typed on |
| `SharingFailure` (phone → watch) | `…, noRoom, bluetoothOff, bluetoothDenied` | `+ needsUpdate` | A guest's phone told to update | Its watch, from the same release |
| `needsUpdate(sessionID:)` | — | **new case** | Nobody in this release | Builds from this release, which say on phone and watch that Rekkert needs updating to join |
| `clock(reading:)` | — | **new case** | Every device from this release, on each link to a device that sent `protocol`: when the link is greeted, then every 30 s while sharing. A phone also asks its own watch every 30 s while sharing, if the watch sent `protocol`. Asked with no reading, answered with one | The asker, to time a round trip (D-2) |

## Timing a round trip (D-2)

```text
near (t₁) ── clock() / events ──────────────▶ far
near (t₄) ◀── clock(reading: t₂) / hello(clock: t₂) ─ far
offset(far − near) ∈ [t₂ − t₄, t₂ − t₁]
```

- t₁ and t₄ are the near device's clock around `sendLive`, for a `clock` question or a push.
  The `clock` exchange fits in one radio chunk each way, so it gives the narrow samples; a push
  gives wider ones, which the narrowest-sample rule mostly sets aside.
- A reply without `clock`, from an older build, gives no sample. Delays from that device are
  then `unknown` unless another path bounds them.
- A push's `offsets` hold the sender's current bounds on the recipient and on each author in
  the batch, as `ClockSpan`: `[lower, upper]` in whole milliseconds, rounded outwards. It
  leaves out any device it has no bounds for.

## What a link change sends (D-5, D-6)

| Event | Before | After |
|---|---|---|
| One link to a device comes up, while another to it is up | Full `synchronise()` on every link | `hello` on that link only |
| The first link to a device comes up | Full `synchronise()` | `hello` on that link, plus `access` (host) or `guestCard` (guest) |
| A link drops, while another to the device is up | Full `synchronise()` | Nothing |
| The last link to a device drops | Full `synchronise()` | As today: the device is marked, and catch-up happens on its return |
| Points arrive from device D on link L | Pushed back on every link except L | Pushed on no link to D, and marked held on all of D's links |

## Compatibility

| Pair | Behaviour |
|---|---|
| This release ↔ this release | All of the above |
| This release host ↔ 1.1 guest | 1.1 skips `clock`, `protocol`, `offsets` and `limit`, and is never sent a `clock` question. Its hellos have no `clock`, so its delays read `unknown` on the host. It is counted once, as today |
| 1.1 host ↔ this release guest | The guest gets no `offsets` and no `limit`. Delays from the host are known from direct samples; relayed delays read `unknown`. The guest's text falls back to "Match is full" without a number |
| 1.0 guest over Wi-Fi | Unchanged from today. Known limit, D-14 |

A `Stamp` is about the sender's own clock, and travels as at most three numbers: the event's
place in the message (in the log's order, in a snapshot), milliseconds after the event's own tap
reading, and how many milliseconds that could be out. A phone stamping its own watch's point
writes `[0,350]`. A device passing a stamp on reads it through its bounds on the sender's clock,
writes it in its own, and adds that bound's half-width to the spread, `[0,362,21]`. `[0]` means
nothing on the way could bound it, and the point's link reads unknown. A receiver whose total
spread is past FR-006's tenth records the link as unknown.

`WireCompatibilityTests` decodes each changed message with and without its new fields, and
decodes a 1.1-shaped payload with the new decoder, and the other way round.
