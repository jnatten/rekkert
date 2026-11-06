# Data Model: Asking at the End of a Shared Match, and Sharing Between Matches

**Feature**: [spec.md](spec.md) · **Decisions**: [research.md](research.md)

New types live in `RekkertCore/Sync`, are `Codable, Sendable, Hashable`, and hold no
SwiftUI, WatchKit or HealthKit (Principle I). Every field added to an existing persisted or
wire type is optional, so older files and older builds decode it as absent.

## New: `BetweenMatches` (D-1)

What a device knows between one shared match and the next. `MatchStore` holds one and
persists it in `ActiveSession`.

| Field | Type | Meaning |
|---|---|---|
| `idleSince` | `Date?` | Since when nothing has been on while sharing or waiting. Nil during a match, and when this device is not sharing. |
| `ask` | `EndOfMatchAsk?` | The end-of-match question still open on this device. |
| `newMatch` | `NewMatchNotice?` | The new-match dialog still open on this device. |

| Rule | Definition |
|---|---|
| `idleLimit` | 30 minutes (FR-026) |
| `isIdleExpired(now:, matchOn:)` | `!matchOn && idleSince != nil && now >= idleSince + idleLimit` |
| `blocksScoring` | `newMatch != nil` (FR-013) |

### `EndOfMatchAsk`

| Field | Type | Meaning |
|---|---|---|
| `session` | `UUID` | The match that ended. It keys the answer for both halves of the pair. |
| `side` | `Side` | `.host(guestsOn: Int)` or `.guest(hostName: String?, hostKeepsSharing: Bool)` |
| `askedAt` | `Date` | For the record. |

`hostKeepsSharing` becomes true when the host's access table arrives with `keptSharingAfter`
equal to `session` (D-5).

### `NewMatchNotice`

| Field | Type | Meaning |
|---|---|---|
| `session` | `UUID` | The host's new match |
| `hostName` | `String?` | From the host's access table. Nil reads as "The host". |
| `arrivedAt` | `Date` | For the record. |

### `BetweenMatchesAnswer` (pair wire value, D-4)

| Field | Type | Meaning |
|---|---|---|
| `session` | `UUID` | `ask.session`, or `newMatch.session` |
| `choice` | `Choice` | `.keepSharing`, `.stopSharing`, `.stay`, `.leave` or `.ok` |

### Transitions

All of these are pure functions on the value. `now` is passed in.

```text
                      matchEnded(session, side?, now)
   (match on) ───────────────────────────────────────────▶ idleSince = now
        ▲                                                   ask = side.map(EndOfMatchAsk)
        │                                                   newMatch = nil
        │
        │ ownMatchBegan / hostsMatchTakenOver                    │
        │   ask = nil, idleSince = nil                           │ answered(a) where a.session == ask.session
        │                                                        ▼
        │                                             ask = nil (idle clock keeps running)
        │
        │ hostsNextMatchArrived(session, hostName, now)
        └── ask = nil (recorded as unanswered if it was open)
            newMatch = NewMatchNotice(session, hostName, now)
            idleSince = nil

   newMatch open ──answered(.ok | .leave, newMatch.session)──▶ newMatch = nil
   sharingStarted(now) / joinedBetweenMatches(now) ──▶ idleSince = now (if no match is on)
   sharingEnded (stopped, left, stopped by host, idle) ──▶ all fields nil
```

The rules a test pins down:

- Who is asked:
  - **The phone's side.** A phone asks if its `role` is `.host` or `.guest`.
  - **The watch's side.** A watch asks if its `pairedRole` is `.host` or `.guest`.
  - **Not asked.** A device whose side is `.solo`.
- **One question per session.** A `matchEnded` for the session already answered raises
  nothing, so a relaunch or a late farewell does not ask again.
- **Leave wins.** An `answered(.stay)` and an `answered(.leave)` for the same session close
  the question either way round. The leave itself is carried out by the existing leave path.
  `.stay` takes nothing back (FR-011).
- **The idle clock:**
  - **When it starts.** It starts again at every `matchEnded`, and never during a match.
  - **What does not reset it.** A `.stay` or `.keepSharing` does not reset it.

## Changed: `ActiveSession` (persisted, `active.json`)

| Field | Change |
|---|---|
| `betweenMatches: BetweenMatches?` | **New.** Absent in older files, and read as empty. |

## Changed: `ShareAccessTable` (wire and persisted, D-5)

| Field | Change |
|---|---|
| `keptSharingAfter: UUID?` | **New.** The ended session after which the host answered Keep sharing. It is set with `revision += 1` through a `keepingSharing(after:)` builder like `with(hostName:)`. A newer revision may carry a different session; older builds ignore the key. |

## Changed: wire types (D-7, D-4, D-6)

| Type | Change |
|---|---|
| `Wire.sharingStopped` | `(sessionID: UUID, reason: SharingStopReason?)`. `reason` is new and optional. |
| `SharingStopReason` | **New**: `.host` (stopped by hand, or at the end-of-match question) or `.idle` (30 minutes with no match on) |
| `SharingSignal.hostStoppedSharing` | `(host: String?, reason: SharingStopReason?)`. `reason` is new and optional. |
| `SharingSignal.answered(BetweenMatchesAnswer)` | **New**, pair only |
| `SharingSignal.newMatch(NewMatchNotice)` | **New**, pair only, phone → watch |
| `HostingStatus` | `canShare` becomes `role != .guest`, with no match needed (D-8). `endedBy: SharingStopReason?` is **new**, so the host's watch can say sharing stopped after 30 minutes. |
| `GuestCard` | `leaving: Bool?` is **new**. A guest that leaves sends a card with `leaving: true` to its host before cutting its links, and the host drops it from its list (D-16). |

The full message table and the compatibility rules are in
[contracts/wire-protocol.md](contracts/wire-protocol.md).

## Changed: `LinkEvent` (sharing record, D-12)

| Case | Written when |
|---|---|
| `endOfMatchAsked` | `ask` is opened on this device |
| `endOfMatchAnswered(EndOfMatchChoice)` | The question is answered here, as keepSharing, stopSharing, stay or leave |
| `endOfMatchUnanswered` | The host's next match closed an open question |
| `newMatchShown` | `newMatch` is opened on this device |
| `newMatchAnswered(NewMatchChoice)` | The dialog is answered here, as ok or leave |
| `idleStop` | Sharing stopped, or a guest left, after 30 minutes with no match on |

Each case gets its `text` and its `init(text:)` parse. The rendered lines are in
[contracts/sharing-record.md](contracts/sharing-record.md).

## Changed: `MatchStore` surface (RekkertSync)

| Member | Change |
|---|---|
| `betweenMatches: BetweenMatches` | **New**, read by the views |
| `answer(_ choice:)` | **New.** It applies a choice to the open question or notice, says it to the pair (D-4) and records it. It carries out nothing else: `SharedSession.answer(_:)` and `WatchStandIn.answer(_:)` call it first, then stop or leave. Views never call it directly. |
| `joinedBetweenMatches(access:)` | **New**, private. Called from `handle(.snapshot)` when a joining store with an empty log is handed an empty snapshot on a non-pair link: the host has nothing on (D-9). It also takes the access list that came with it. |
| `.guestCard` handling | On the host, a card with `leaving == true` calls `participants.remove(card.device)` and `onParticipantsChanged` (D-16) |
| `leaveSharedSession()` | On a guest, it first sends the goodbye card on each host link, waiting up to 2 s (D-16) |
| `startingOwnMatchLeavesSharing: Bool` | **New**: true on a phone whose role is `.guest`, or on a watch where `startingOwnMatchTakesPhoneOff` (D-15) |
| `canScore`, `canRunRounds` | They are now also false while `betweenMatches.blocksScoring` |
| `.sharingStopped` handling | It also acts for an empty-log guest on a non-pair link (D-7) |
| `onMatch` | `MatchMoment` gains `.nextFromHost(UUID)`, which the app uses for the notification (D-11) |

## Changed: `SharedSession` surface (RekkertSync)

| Member | Change |
|---|---|
| `host(code:)`, `startHostingFromTheWatch()` | No match needed. A guest still cannot (D-8). |
| `stop(reason:)` | `reason` defaults to `.host`. `.idle` is used by the idle check. |
| `stoppedForIdle: Bool`, `acknowledgeIdleStop()` | **New**: the host is told at the next look (FR-026) |
| `hostStopReason: SharingStopReason?` | **New**, beside `hostWhoStopped`, for the guest's notice |
| The idle watch | **New**: a task on the injected `sleep` every 30 s, and a check at the top of `restore()` and `resume()` (D-10) |
| `answer(_ choice:)` | **New**, the phone's one entry point for every answer (D-4). It calls `store.answer(choice)` first, then `stop()` for `.stopSharing`, and the guest's leave path for `.leave`. |

## Changed: `WatchStandIn` surface (RekkertSync)

| Member | Change |
|---|---|
| `answer(_ choice:)` | **New**, the watch's one entry point (D-4). `.stopSharing` goes to `stopHosting()`, and the question closes only once the phone reports it is no longer sharing, so it stays open on "Can't reach your iPhone" (FR-007). `.leave` goes to the watch's `SharedSession.leave()`, after `store.answer(.leave)`. Every other choice goes to `store.answer`. |

## Unchanged

- `MatchLog`, `MatchEvent` and the reducer.
- Draws and schedules.
- Version vectors.
- `KeptCode` and its 12 hours.

Principle II holds: nothing here changes what a match is, only what a device asks and lets
its wearer do between matches.
