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
| `snapshot` | host → guest | Unchanged | A whole log, only when nothing less will do |
| `guestCard(device, name, pairedTo?)` | guest → host | **Extended** | `pairedTo` (optional): a standing-in watch names its phone, so the pair counts once |
| `sharingStopped(session)` | host → guests | **New** | Sent before the host cuts its links. A guest files its copy in History, as Leave does, forgets the code, and says the match is no longer shared (D-9, FR-028). |
| Handshake refusal `noRoom` | host → guest | **New reason** | Seven participants are already on. The guest shows "No room on this match" on its phone and watch (D-8, FR-008). |

## Pair scope (`.sharing` channel and the application context)

| Message | Direction | Status | Contents / rule |
|---|---|---|---|
| Application context snapshot | phone → watch | **Changed** | Now carries the phone's `role` with the log, so a watch whose phone is a guest adopts its match without weighing clocks (D-12) |
| `role` | phone → watch | **Changed use** | Arriving on its own, it now triggers a re-sync |
| `sharing.hostingStatus(HostingStatus)` | phone → watch | **New** | Code, join link, QR PNG, participants and their states, last failure (D-14). Sent live when reachable, and in the context for a cold start. |
| `sharing.startHosting` | watch → phone | **New** | Share the match. The answer is a `hostingStatus`. |
| `sharing.stopHosting` | watch → phone | **New** | Stop sharing; the watch has already confirmed. The answer is a `hostingStatus`. |
| `sharing.followPhone` | watch → phone | **New** | "Get on it": the phone re-offers its snapshot with its role |
| `sharing.standby(code, isThrough, share?, startedAt?)` | phone → watch | **Extended** | `share` and `startedAt` let a guest's watch keep the code (D-1) and stand in on the same share |
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
