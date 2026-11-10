# Contract: Wire Changes for 005

**Feature**: [../spec.md](../spec.md) · **Decisions**: [../research.md](../research.md) D-2, D-5, D-6, D-13, D-14

## Rules

- **Additive only.** Every change is an optional associated value or an optional field. A 1.1
  build decodes every message the host sends, skipping fields it does not know (research R-7).
- **Version markers stay put.** The Bluetooth greeting stays at version 3, and the
  local-network TXT record stays at `v = "1"`.
- **One new `Wire` case, `needsUpdate`, which this release never sends.** It exists so a later
  breaking change can tell guests from this release on, plainly.
- **Event formats are unchanged**, apart from `at` being rounded to the hundredth
  (data-model.md). Principle II is weighed in plan.md.

## Changed messages

| Message | Before | After | Who sets it | Who reads it |
|---|---|---|---|---|
| `hello` | `hello(sessionID:, vector:, from:)` | `+ clock: Date?`, `+ protocol: Int?` | Every sender from this release. `clock` is the sender's time when it encodes the hello | The other end, to time a round trip (D-2) |
| `events` | `events(sessionID:, events:)` | `+ offsets: [DeviceID: ClockBounds]?` | The host, on per-link pushes | The guest, to compose its offset to each event's author |
| `noRoom` | `noRoom(sessionID:)` | `+ limit: Int?` | The host | The guest's phone and watch, to say how many fit |
| `GuestCard` | `device, name, pairedTo, leaving` | `+ protocol: Int?` | Guests from this release | The host, to know which guests can understand `needsUpdate` |
| `HostingStatus` (phone → watch) | `…, participants, …` | `+ limit: Int?` | The host's phone | The host's watch, for "N of M on" |
| `needsUpdate(sessionID:)` | — | **new case** | Nobody in this release | Builds from this release |

## Timing a round trip (D-2)

```text
near (t₁) ── events / hello ──▶ far
near (t₄) ◀── hello(clock: t₂) ─ far
offset(far − near) ∈ [t₂ − t₄, t₂ − t₁]
```

- t₁ and t₄ are the near device's clock around `sendLive` in `deliver()`, and on a hello it
  sends itself.
- A reply without `clock`, from an older build, gives no sample. Delays from that device are
  then `unknown` unless another path bounds them.
- The host's `offsets` hold its current `ClockBounds` for each author in the batch. It leaves
  out any author it has no bounds for.

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
| This release host ↔ 1.1 guest | 1.1 skips `clock`, `protocol`, `offsets` and `limit`. Its hellos have no `clock`, so its delays read `unknown` on the host. It is counted once, as today |
| 1.1 host ↔ this release guest | The guest gets no `offsets` and no `limit`. Delays from the host are known from direct samples; relayed delays read `unknown`. The guest's text falls back to "Match is full" without a number |
| 1.0 guest over Wi-Fi | Unchanged from today. Known limit, D-14 |

`WireCompatibilityTests` decodes each changed message with and without its new fields, and
decodes a 1.1-shaped payload with the new decoder, and the other way round.
