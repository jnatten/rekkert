# Data Model: Reliable Session Sharing, and Sharing from the Wrist

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Decisions**: [research.md](research.md)

Pure types live in `RekkertCore/Sync` (Principle I). Existing types this builds on:
`SessionCode`, `DeviceID`, `VersionVector`, `MatchLog`, `GuestCard`, `ShareAccess` and
`SessionRole`.

## KeptCode (D-1)

What a device keeps so that sharing survives the app being ended, and so a guest can join
again without typing the code.

| Field | Type | Notes |
|---|---|---|
| `code` | `SessionCode` | The six digits |
| `share` | `UUID` | The share id; with the code, it fixes every derived key and fingerprint |
| `role` | `SessionRole` (`.host` / `.guest`) | Which way to resume |
| `startedAt` | `Date` | When the host started sharing on this code; the guest copies it from the host |
| `expiresAt` | `Date` | Computed: `startedAt + 12 h` |

**Rules**

- Kept only on a device that has been on the match: the host's phone, and a guest's phone
  or watch once it has proved itself on the match. A code typed in that never worked is not
  kept. The host's watch is shown the code but does not keep it.
- Read through `KeptCode.current(now:)`. An expired item counts as absent and is deleted.
  A host still sharing when its code expires carries on sharing; only keeping it stops, so
  an app ended after that shares on a new code.
- A guest forgets its kept code when told sharing has stopped (FR-028).
- `restore()` rejoins a guest only if its stored role is still `.guest`. After a Leave, the kept code serves Join again and nothing else.
- Stored as one Keychain item: this device only, after first unlock, not synchronisable.
  It never goes in `active.json` or any other file.
- At most one kept code per device. Hosting or joining another code replaces it.

**Lifecycle**

```text
          host starts / guest proves itself
 (none) ─────────────────────────────────────▶ kept
   ▲                                            │
   │  host stops sharing                        │ app ended and run again:
   │  guest joins another code (replaced)       │   restore() hosts or rejoins on it
   │  guest told sharing stopped                │
   │  12 h passed (on read)                     │ guest leaves:
   └────────────────────────────────────────────┘   stays kept, for "Join again"
```

## Participant and ParticipantState (D-7)

The host's view of who is on the match. It replaces link counts.

| Field | Type | Notes |
|---|---|---|
| `id` | `DeviceID` | The guest's phone, or its watch if the watch joined on its own |
| `name` | `String?` | From the guest card ("Who are you?"); `nil` shows as "Phone 1"… |
| `devices` | `Set<DeviceID>` | Its phone, and its watch while that stands in |
| `lastHeard` | `Date?` | Anything received on any of its links |
| `vector` | `VersionVector` | The latest it reported in a hello |
| `access` | `ShareAccess.Level` | Existing per-device level |
| `isOlderBuild` | `Bool` | A proven link with no hello naming a sender |

`ParticipantState` is derived; it is never stored or sent as truth.

| State | Condition |
|---|---|
| `inStep` | `now − lastHeard ≤ 15 s` and `vector ≥ host.coverage` |
| `catchingUp` | `now − lastHeard ≤ 15 s` and `vector < host.coverage` |
| `outOfReach(since:)` | `now − lastHeard > 15 s`, with `since = lastHeard` |

```text
 join proven ──▶ catchingUp ──(has everything)──▶ inStep
                    ▲  │                            │
                    │  └──────(15 s silent)─────────┤
                    │                               ▼
                    └────────(heard again)──── outOfReach(since)
```

**Rules**

- A watch standing in sends a guest card that names its phone (`pairedTo`). Its `DeviceID`
  joins that phone's `devices`, so one person is never counted twice.
- The participant limit (D-8): at most seven participants besides the host. A new device
  whose card names an existing participant does not count against it.
- Participants are kept for the shared match's lifetime, so the host's list shows who
  dropped. A guest that left with a farewell, or was filed on Stop, is removed.

## Delivery per participant (D-5)

Replaces the all-or-nothing `ReplyFold` acknowledgement in `MatchStore`.

| Field | Type | Notes |
|---|---|---|
| `known` | `[DeviceID: VersionVector]` | Per participant: the latest vector heard |
| `outbox` | existing | Events not yet known to every counted participant |

**Rules**

- A participant is sent `log.events(after: known[p])`: only what it is missing, split into
  frames the radio interleaves (D-4). The whole outbox is never sent to everyone.
- An event leaves the outbox once every participant that is not `outOfReach` for more than
  60 s covers it. A returning participant is caught up by its hello's vector, so nothing is
  lost (Principle II).
- A packet is never sent back on the link it came in on.
- A phone and its own watch keep their existing pair outbox and acknowledgement.

## LinkRecord and LinkRecordEntry (D-11)

A device's account of what happened to its links. It is read on the phone, with its watch's
record merged in.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Deduplicates entries merged from the watch |
| `time` | `Date` | |
| `device` | `.phone` / `.watch` | Which half of the pair wrote it |
| `session` | `UUID?` | The match's session id, to group entries; not personal |
| `link` | `.pair` / `.host(DeviceID)` / `.guest(DeviceID)` / `.radio` | |
| `kind` | `LinkEvent` | See below |

`LinkEvent` kinds:

- Launches: `launched(.user / .background / .restored)`, `appHadBeenEnded`, recorded when a
  launch finds a kept code.
- Sharing: `sharingStarted`, `sharingRestored`, `sharingStopped`.
- Joining: `joinStarted`, `joined`, `proven`, `refused(.wrongCode / .noRoom / .access)`.
- Link health: `dropped(.timeout / .radioOff / .closedByPeer / .hungUp / .unknown)`,
  `outOfReach`, `backInStep`, `caughtUp(events:)`, `wroteOff`, `redialled`.
- The watch: `standIn`, `standDown`.
- The radio: `radioOff`, `radioOn`, `permissionDenied`.
- The record itself: `notificationPosted`, `recordReceived(from: .watch)`.
- Debug builds only: `pointArrived(latency:)`, how long after it was scored an event reached
  this device. It is what the field test measures SC-002 with, and it carries no score.

**Rules**

- No player names, scores or codes are ever recorded. Device ids are random identifiers.
- Stored as one file per day under Application Support, excluded from backup. Days older
  than 7 are pruned when a file is opened.
- The watch sends its files to the phone with a durable transfer when it can. The phone
  merges them by `time` and deduplicates by `id`.
- `reachability` reasons replace the bare `Bool` the transports report today, so `dropped`
  can say why.

## HostingStatus (D-14) — phone → its own watch

| Field | Type | Notes |
|---|---|---|
| `isSharing` | `Bool` | |
| `code` | `SessionCode?` | `nil` when not sharing |
| `joinLink` | `URL?` | `https://rekkert.natten.dev/join#<code>` |
| `qr` | `Data?` | A PNG of the join link, drawn on the phone |
| `participants` | `[ParticipantSummary]` | `{name, state}` in the order they joined |
| `canShare` | `Bool` | `false` if nothing can be shared |
| `failure` | `SharingFailure?` | Why the last start or stop request did nothing |

Sent live when the watch can be reached, and in the application context for a cold start.
It is never sent beyond the pair.

## Sharing requests (D-14, D-12, D-15) — watch → its own phone

| Request | Meaning | Handled by |
|---|---|---|
| `startHosting` | Share the match on the phone | `SharedSession.host()` |
| `stopHosting` | Stop sharing, after the watch has confirmed | `SharedSession.stop()`, which tells guests (D-9) |
| `join(code)` | Existing | |
| `cancel` | Existing | |
| `followPhone` | "Get on it": send me the match you are on | `MatchStore` re-offers its snapshot with its role |

A request the phone cannot carry out is answered with a `HostingStatus` carrying a
`failure`. A request that cannot reach the phone fails on the watch at once, as joins do
today (FR-020: say so, change nothing).

## Sharing phase — state transitions

```text
 HOST                                        GUEST
 off ──host()──▶ hosting(code)               off ──join(code)──▶ searching ──proven──▶ joined
                  │   ▲                                            ▲  │                  │
     app ended ───┘   └── restore() with kept code     link lost  │  └─(20 s, never on)─▶ failed
                  │                                    (keeps     │                      │
     stop() ──────┴──▶ off (+ sharingStopped to guests) looking)──┘   sharingStopped ────┤
                                                                       or Leave ─────────▶ off (filed)
                                                       app ended ── restore() with kept code ──▶ searching
```
