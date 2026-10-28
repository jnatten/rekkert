# Contract: Messages Between Devices

**Feature**: [../spec.md](../spec.md) · **Data model**: [../data-model.md](../data-model.md)

Rekkert devices on one match may run different builds, so every change here is additive.
Two scopes exist today, and both are kept:

- **Shared session**: phone ↔ phone, plus a guest's watch standing in with the host. It is
  carried over Bluetooth and the local network.
- **Pair**: a phone ↔ its own watch, over WatchConnectivity. The `.sharing`, `.left` and
  `.role` messages never leave this scope (`FanOutTransport.swift:62`).

## Shared-session scope

| Message | Direction | Status | Contents / rule |
|---|---|---|---|
| `hello(session, vector, from)` | any → any | **Used more** | `from` names the sender's `DeviceID`. The host now keys participants on it (D-7). An idle guest sends one every 10 s; the host sends one every 15 s to a participant it has marked out of reach (D-6). |
| `events(session, [MatchEvent])` | any → any | **Changed use** | The host sends each participant only what its last vector lacks (D-5). Never sent back on the link it came in on. |
| `snapshot(log, access?)` | host → guest | **Extended** | A whole log, only when nothing less will do. `access` (optional): the host's `ShareAccessTable`, in its answer to a hello and its published snapshot but not in a live offer, which goes to every link at once. A joining guest takes it with the match, so it is never on the match with more say than the host gave it. Absent from older builds, whose guests go on allowing everything until `.access` arrives. |
| `guestCard(device, name, pairedTo?)` | guest → host | **Extended** | `pairedTo` (optional): a standing-in watch names its phone, so the pair counts once |
| `sharingStopped(session)` | host → guests | **New** | Sent before the host cuts its links. A guest files its copy in History, as Leave does, forgets the code, and says the match is no longer shared (D-9, FR-028). |
| Handshake refusal `noRoom` | host → guest | **New reason** | Seven participants are already on. The guest shows "No room on this match" on its phone and watch (D-8, FR-008). |

## Pair scope (`.sharing` channel and the application context)

| Message | Direction | Status | Contents / rule |
|---|---|---|---|
| Application context snapshot | phone → watch | **Changed** | Now carries the phone's `role` with the log, so a watch whose phone is a guest adopts its match without weighing clocks (D-12) |
| Application context snapshot `access` | phone → watch | **New** | A guest's copy of the host's list, so its watch has it the moment it has the match. Only fills in a missing list or brings the same one up to date: a list from another share is replaced by `.access` alone. A guest's `.access` itself now goes to its watch only, never back over a link to the host. |
| `role` | phone → watch | **Changed use** | Arriving on its own, it now triggers a re-sync |
| `sharing.hostingStatus(HostingStatus)` | phone → watch | **New** | Code, join link, QR PNG, participants and their states, last failure (D-14). Sent live when reachable, and in the context for a cold start. |
| `sharing.startHosting` | watch → phone | **New** | Share the match. The answer is a `hostingStatus`. |
| `sharing.stopHosting` | watch → phone | **New** | Stop sharing; the watch has already confirmed. The answer is a `hostingStatus`. |
| `sharing.followPhone` | watch → phone | **New** | "Get on it": the phone re-offers its snapshot with its role |
| `sharing.standby(code, isThrough, share?, startedAt?, issuedAt?)` | phone → watch | **Extended** | `share` and `startedAt` let a guest's watch keep the code (D-1) and stand in on the same share. `issuedAt` is stamped each time the phone says it, replays included; a watch ignores one said before it last saw its phone go, which can be handled after the phone is back. Older phones send none and are taken at their word. |
| `sharing.join(code)`, `sharing.cancel`, `sharing.state(...)` | | Unchanged | |
| Sharing-record file | watch → phone | **New** | Sent with `WCSession.transferFile`, metadata `{"kind": "linkRecord", "day": "2026-10-27"}`. The phone merges it (D-11). |

## Compatibility rules

1. **An older build that receives a new message kind** fails to decode it and answers with
   a hello (MS:1214-1217), so nothing stalls.
2. **An older build that receives `guestCard` with `pairedTo`** decodes it. Unknown JSON keys
   are ignored, and the card still counts.
3. **An older guest refused with `noRoom`** sees an ordinary failed join. That is acceptable:
   it is past the limit either way.
4. **An older host never sends `sharingStopped`.** A new guest falls back to today's
   behaviour: the host goes out of reach, and the guest shows "Host out of reach since…"
   (D-10).
5. **An older guest whose hello does not name its sender** is listed by a new host as
   "Older Rekkert", and counted as one participant.
6. **An older watch ignores `role` in the context**, and keeps today's clock rule. Watch and
   phone ship together, so this lasts only until the watch app updates.
7. **The event format, the merge and the reducer are unchanged** (Principle II).
