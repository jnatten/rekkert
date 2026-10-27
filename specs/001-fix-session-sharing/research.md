# Research: Reliable Session Sharing, and Sharing from the Wrist

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Date**: 2026-10-27

The code was read end to end in three areas: the Bluetooth host serving several guests, the
lifecycle of a sharing session and its code, and the phone↔watch paths. Every finding is
marked **VERIFIED** (the code path was read through and confirmed) or **SUSPECTED** (the code
allows it, but whether it fired depends on platform behaviour that only real devices show).
Paths are relative to the repository root; `BT` is
`Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift` and `MS` is
`Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift`.

## Part 1 — What went wrong on 2026-10-26 (FR-006)

None of the paths below can leave two devices with permanently different scores: merging is
a union, and every one of them converges once a link carries a hello. What they do is stop a
guest getting on, or stop it following the host. That reads as "a different score" on the
court until something reconnects. Every one fits "the host's phone and watch were fine, the
others were not": the host's watch talks to its own phone over WatchConnectivity, which none
of these touch.

### RC-1 · The host's app is ended, and nothing brings sharing back — VERIFIED

- The code and share id live only in memory, `SharedSession.hosted`
  (`SharedSession.swift:63-65`), by design (`SharedSession.swift:7-9`: "a host who quits
  shares again with a new one").
- On any cold launch the phase is `.off`, so `revival` is `.nothing` and `resume()` does
  nothing (`SharedSession.swift:192-218`). That holds for a user opening the app and for a
  background launch through `didFinishLaunching` (`App/Sources/RekkertApp.swift:31-38`).
- Neither Bluetooth manager uses state restoration (`options: nil`, BT:166, BT:174). The
  advertisement and the GATT service die with the process, and iOS will not relaunch the
  app for the radio. The comment at `RekkertApp.swift:31` says it does; for Bluetooth it does
  not.
- The match, the host role, the guest list and the access table all come back from disk.
  The host's watch keeps working throughout (its workout keeps it running, and its messages
  wake the phone). The phone never tells its watch it is hosting
  (`SharedSession.swift:474-490`). The phone shows no badge for a host that has stopped
  sharing (`App/Sources/Views/ConnectionBadge.swift:54, 85, 109-112`).
- The only way back is "Share this match again" (`MatchOptionsMenu.swift:124-131`), which
  draws a **new** code (`SharedSession.swift:167-177`). Guests still on the old code:
  - over Bluetooth, reject the new greeting's fingerprint and blacklist that host for the
    rest of their join (BT:814-821, 889-902, 669);
  - over the local network, skip its advertisement (`LocalNetworkTransport.swift:445-451`).
  The guests' "Still looking" alert only shows in the foreground (`RootView.swift:101-120`),
  so a phone in a bag shows nothing.

This matches the incident exactly. Why iOS would end the host's app is SUSPECTED: a
suspended app is ended under memory pressure, nothing records it, and a crash looks the same.

### RC-2 · The host silently writes off a guest that is only following — VERIFIED

- After three unanswered questions, `missed()` clears `isReady` for a central and does
  nothing else (BT:299-313). The host does not hang up on a guest.
- From then on, `sendLive` and `broadcast` skip that guest (BT:234, 317). Only a frame
  *from* the guest makes it ready again (BT:504-506).
- A guest that is in step and not scoring sends nothing: `retryUndelivered` idles on an empty
  outbox (MS:1014). Its own link still looks up, so it believes it is on the match.

Three misses come easily when the radio is busy (RC-3, RC-4) or a guest's phone is slow to
wake. At a court where one or two people keep score, every other guest is exactly this kind
of silent follower. Symptom: "got on, then stopped following the host", for good.

### RC-3 · The host serves its guests in a fixed order — code VERIFIED, size SUSPECTED

- `drainEverybody` rebuilds its turn list from `peers.values` on every
  `peripheralManagerIsReady` and returns at the first full queue (BT:453-467). The start
  never rotates, so when a callback frees fewer slots than there are guests with something
  waiting, the same guests are served every time.
- `send` makes it worse: it drains one guest greedily (BT:338, 363-365), so one guest's
  snapshot or long frame fills the shared queue.
- For a starved guest, live pushes reach the head of its backlog after their 4 s expiry and
  are dropped unsent (BT:373-375). Its handshake answer waits in the same queue. If proof
  takes more than 10 s on a first join, the guest rejects the right host and blacklists it
  (BT:875-891). With no Wi-Fi, it gives up after the 10 s search plus a 10 s grace
  (`SharedSession.swift:432-469`).

Symptom: "never got on" when several join at once, and "stopped following" for whoever sorts
last.

### RC-4 · All-or-nothing acknowledgement feeds on itself — VERIFIED, tipping point SUSPECTED

- The outbox may forget only what *every* peer acknowledged within the fan-out's 4 s
  (`ReplyFold.swift:37`; `FanOutTransport.swift:94`). A late hello is thrown away
  (`LinkReplies.swift:10-14`).
- Every event a host relays from a guest also goes into its outbox (MS:1601), and a retry
  sends the *whole* outbox to every peer as one frame (MS:1154-1165), at most every 32 s.
- A frame that has started always finishes (BT:373), so a big retry holds up that guest's
  queue and the live pushes behind it expire.
- Events echo: a guest relays what it hears from the host back to the host, and the host
  echoes a guest's own event back to it, because the fan-out never leaves out the source
  (MS:1595-1602; `FanOutTransport.swift:161`).

Once the outbox is bigger than the radio can get to every guest in 4 s, it is never
acknowledged and only grows. A watch standing in with its Bluetooth suspended makes this
worse (RW-4). Symptom: lag that grows with every guest and every point.

### RC-5 · A guest's app is ended and forgets the code — VERIFIED

`SharedSession.wanted` is memory only (`SharedSession.swift:66`). A relaunched guest keeps
the match and the guest role but cannot reconnect, and shows "Rejoin" for a code to be typed
(`ConnectionBadge.swift:85-94`). Leaving forgets it too, on the phone and the watch
(`WatchStandIn.swift:185-187`).

### RC-6 · Finding the host again with both phones in bags — SUSPECTED (platform)

After a long drop, the guest waits on a `connect` with no timeout to the host's old
peripheral (BT:688, 758). The host's private address rotates and the phones are not bonded,
so that connect can never complete. The fallback is a background scan (BT:757), and a
backgrounded peripheral advertises only in the overflow area, which a scanner with its screen
off is not reliably shown. This needs checking on real devices.

### RC-7 · No limit on guests, and no "no room" — VERIFIED

`subscribed` accepts any number of centrals (BT:616-623). Subscribers that never prove
themselves are never timed out. How many connections iOS gives one peripheral, and how the
airtime is shared, are unknown.

### The guest's watch that never showed the match

- **RW-1 · Nothing wakes the watch app — VERIFIED.** On joining, the phone sends the watch
  the application context, a role message and live events (MS:558, 1455-1473, 1675). Live
  sends need the watch app active (`WatchConnectivityTransport.swift:197`), and a phone
  cannot wake its watch (`WatchConnectivityTransport.swift:211-214`). Unless a workout is
  running, the match appears only when the guest next brings Rekkert to the front.
- **RW-2 · Snapshot before role lets the watch's own session win — VERIFIED.** `adopt`
  publishes the snapshot (MS:1457) before `role = .guest` and `shareRole()` (MS:1460, 1465),
  on different channels. A watch that has a session of its own (a warm-up counts), and has
  not heard its phone is a guest, falls back to comparing `createdAt` (MS:1547-1553).
  `createdAt` is when the empty log was made, not when play started, so the host's match can
  look hours old. The watch refuses it and offers its own. It heals only at the next
  snapshot or point, because a role arriving does not trigger a re-sync (MS:1312).
  Meanwhile the watch shows Finish/Discard instead of Leave (MS:331-336).
- **RW-3 · A match started on the watch takes the phone off the code — VERIFIED, by
  design.** Between the host's matches, Quick match or a preset on a guest's watch takes its
  phone off the shared code (MS:1485-1501), with no question asked.
- **RW-4 · A standing-in watch counts as another phone — VERIFIED.** It sends no guest card
  (MS:461), so the host counts one person twice, and the share sheet claims an older Rekkert
  is connected (`ShareCodeSheet.swift:38`). With its Bluetooth suspended (no workout), it
  costs every question 4 s until three misses, and stalls the all-or-nothing
  acknowledgement (RC-4).

### Checked and ruled out

- **Per-central state.** Each central has its own sealing, nonces and counters (BT:63-86,
  618; `LinkSeal.swift:82-89`) and its own MTU (BT:348-351).
- **A full transmit queue.** Chunks it refuses are kept and offered again (BT:379-386), and
  `peripheralManagerIsReady` is wired up (BT:945-947).
- **Concurrent draining.** All draining runs on one serial queue (BT:338, 345).
- **Other Bluetooth bookkeeping.** A stale backlog is dropped on re-subscribe (BT:397-402),
  and correlation ids are unique (BT:269-273).
- **Rejoining.** It merges rather than replaces (MS:1439-1448). NewCodeTests, RejoinTests
  and ReconnectTests pass (29 tests).
- **Finishing.** A guest's watch ending its copy never finishes the host's match (MS:1274),
  and the host overrules stray Finishes (MS:1652-1658).
- **Leaving.** Leave on the watch takes the phone off, and the other way round
  (OwnWatchTests:284, 416). This already meets FR-022 and FR-023 apart from confirmation.
- **Locked-phone access.** `active.json` is readable on a locked background relaunch (no
  data-protection class is set).

## Part 2 — Decisions

### D-1 · Keep the code on the devices that have been on the match (FR-025)

- **Decision**: Keep `{code, share id, role, startedAt}` as one Keychain generic-password
  item on each device that has been on the match: the host's phone, and each guest's phone
  and watch.
  - Accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronisable.
  - The 12-hour limit is enforced when the item is read, because Keychain items can outlive
    the app.
  - The host clears it on Stop sharing. A guest replaces it on joining another match,
    forgets it when told sharing has stopped (FR-028), and keeps it after Leave so it can
    join again (FR-024).
  - The pure rules live in RekkertCore (`KeptCode`); the Keychain itself sits behind a small
    protocol, so tests use an in-memory one.
- **Rationale**:
  - The share id has to stay the same as well as the code, so that every key and fingerprint
    derived from them is identical after a relaunch (`SessionKey.swift:21-77`).
  - This-device-only and after-first-unlock means the item never leaves the device, never
    reaches a backup, and can be read on a background relaunch while the phone is locked.
- **Alternatives considered**:
  - A file excluded from backup, as `DeviceIdentity` does. Rejected: it gets no per-item
    data protection, and the code is a secret.
  - Keeping only the derived keys. Rejected: the host still has to show the code, and the
    keys are no less sensitive than a 20-bit code.

### D-2 · Bring sharing back on every launch (RC-1, RC-5)

- **Decision**: `SharedSession` gains a `restore()` step, run from `AppModel.start()` on
  every launch path: user, WatchConnectivity and Bluetooth restoration.
  - With an unexpired kept code and `role == .host`, it hosts again on that code and share
    id.
  - With `role == .guest`, it resumes joining.
  - The guard in `host()` that needs a match on (`SharedSession.swift:159`) is relaxed for a
    restore, so a host between matches comes back too.
- **Rationale**: removes RC-1 and RC-5 at the root, so guests reconnect by themselves
  (FR-003, SC-010).
- **Alternatives considered**: keeping the app alive in the background so it is never
  ended. Rejected: iOS gives no such guarantee, and it costs battery.

### D-3 · CoreBluetooth state restoration on the phone (RC-1, RC-6)

- **Decision**: create both managers with restore identifiers
  (`CBPeripheralManagerOptionRestoreIdentifierKey`,
  `CBCentralManagerOptionRestoreIdentifierKey`), and handle `willRestoreState`:
  - re-adopt the published service, the subscribed centrals and the pending connections;
  - then run D-2.
- **Rationale**: after the system ends the app, iOS keeps advertising, keeps the service
  published and keeps pending connections on its behalf. It relaunches the app in the
  background when a guest connects or a host reappears. This is the only mechanism that
  revives a phone left in a bag. It does not apply after the user force-quits; the sharing
  record notes that case (D-11).
- **Alternatives considered**: background tasks. Rejected: none of them suits a link that
  lasts all evening.

### D-4 · Fair turns on the host (RC-3)

- **Decision**: replace the per-callback rebuild with a cursor that persists across ready
  callbacks, so each callback starts with the guest after the last one served.
  - A host-side `send` enqueues and wakes the shared drain, instead of draining one guest
    greedily.
  - Each guest's backlog goes in priority order: handshake first, then live pushes, then
    catch-up.
  - Catch-up frames are split so they interleave with other guests' live pushes.
- **Rationale**: every guest gets airtime in proportion, however few slots each callback
  frees.
- **Alternatives considered**: an L2CAP channel per guest (`CBL2CAPChannel`). It gives
  stream flow control per guest and more throughput, but it is a much larger change.
  Deferred, unless the field test (SC-001, SC-009) shows the shared queue cannot carry seven
  guests.

### D-5 · Per-guest delivery instead of all-or-nothing (RC-4)

- **Decision**: the store keeps each participant's last known version vector, from the
  hellos, which now name their sender (D-7).
  - Each participant is sent only the events it is missing. The whole outbox is never sent
    to everyone again.
  - The outbox can forget an event once every participant still counted as on the match has
    it. A participant that has been out of reach longer than 60 s no longer holds the outbox
    back; it is caught up by vector when it returns.
  - The fan-out never sends a packet back to the link it came from.
- **Rationale**: Principle II is untouched. Merging is still a union, and catch-up by vector
  difference cannot lose an event (FR-004). Each guest's traffic is now bounded by what it is
  actually missing.
- **Alternatives considered**: keeping all-or-nothing and raising the timeout. Rejected: it
  still tips over, only with more guests.

### D-6 · Liveness both ways (RC-2, SC-004)

- **Decision**:
  - A guest sends a small hello whenever 10 s have passed with nothing sent to the host.
  - A host that counts three misses keeps the guest connected, marks it out of reach, and
    sends it a hello every 15 s instead of going silent.
  - A guest that hears nothing back for three of its hellos hangs up and dials again.
- **Rationale**: neither end can be written off without the other noticing, which closes
  RC-2. The same signal feeds the host's per-guest state (FR-010) and the out-of-reach
  notices (FR-007).
- **Alternatives considered**: relying on BLE supervision timeouts. Rejected: a link can
  stay up with nobody answering on it, which is RC-2 itself.

### D-7 · Know who is on: participants, not links (FR-010, FR-011, RW-4)

- **Decision**:
  - Once a link proves itself, it is tagged with the sender's `DeviceID` from its first
    hello.
  - A guest's watch that stands in sends a guest card naming its phone, so the host counts
    the pair as one participant.
  - The host derives each participant's state from when it was last heard from and its
    vector against the host's:
    - **in step**: heard within 15 s, and has everything;
    - **catching up**: heard within 15 s, and behind;
    - **out of reach**: not heard for 15 s.
- **Rationale**: answers "who is on, and why not" and stops one person being counted twice.
  It is also what the per-guest delivery in D-5 needs.
- **Alternatives considered**: keeping link counts. Rejected: they cannot name anyone.

### D-8 · A limit of seven guests, and a "no room" answer (FR-001, FR-008, RC-7)

- **Decision**: the host takes up to seven guest participants, where a phone and its
  standing-in watch count once. Anyone after that is refused at the handshake with a new
  `noRoom` reason, which the guest shows on its phone and watch.
  - A subscriber that has not proved itself within 15 s is dropped.
- **Rationale**: an honest refusal is better than a link that slowly starves everyone else.
  How many connections iOS really allows is checked in the field test. The limit is a
  constant that can be adjusted.

### D-9 · Stopping sharing tells the guests (US4 AS6)

- **Decision**: before cutting its links, the host sends every guest a `sharingStopped`
  message. A guest that receives it files its copy in History as it stood, the same way
  Leave does, and says the match is no longer shared.
- **Rationale**: today the links are cut first (`SharedSession.swift:321-327`), so to a guest
  it looks exactly like the host disappearing. Filing the copy matches what Leave already
  does. This also settles the one item `/speckit-clarify` left outstanding.

### D-10 · When the host is gone: tell the guests, keep scoring (FR-026, FR-007)

- **Decision**: a guest whose host has been out of reach for 15 s shows "Host out of reach
  since 20:41" persistently: in the phone's sharing badge, and on the watch's court page and
  menu. It is not only a foreground alert. Scoring carries on into the outbox, as today.
  Finishing stays disabled while the host is gone.
- **Rationale**: FR-007 and SC-004 rule out a stale score shown as current. The watch is
  what players look at with their phones in bags.

### D-11 · The sharing record (FR-012, FR-013, SC-006)

- **Decision**:
  - A pure `LinkRecord` model in RekkertCore: timed entries recording which device (phone
    or watch), which link (to its paired device, or to the host or a guest by `DeviceID`),
    and what happened. The kinds are listed in the data model.
  - A file per day in Application Support, excluded from backup, with days older than 7
    pruned.
  - Transport reachability carries a reason instead of a bare `Bool`, so the record says
    why a link went (timeout, radio off, refused, wrong code, no room).
  - The watch writes its own record and sends it to the phone with
    `WCSession.transferFile`, which is durable, whenever the phone can be reached.
  - The phone merges both by time, and shows the result under Settings → Sharing record,
    with a Share button that exports it as plain text.
  - A cold launch while a code is kept is recorded as "app had been ended", the only trace
    an ended app can leave.
  - No scores, no names, and no codes go in the record.
- **Rationale**: SC-006 needs both halves of a pair side by side. Principle V holds: nothing
  leaves the owner's devices unless the owner shares it.
- **Alternatives considered**:
  - `os.Logger`. Rejected: users cannot get at it without a Mac, and retention is not ours
    to control.
  - Showing the record on the watch. Rejected by the clarification.

### D-12 · The guest's watch follows its phone (FR-014..FR-016, RW-2, RW-3)

- **Decision**:
  - The role travels with the snapshot, in the same application-context payload. A watch
    therefore never weighs the clock against a match its guest phone is on, and a role
    arriving on its own triggers a re-sync.
  - A guest phone's shared match always takes over the watch's own unshared match, which
    is filed through the existing `.displaced` path.
  - A watch that knows its phone is on a match it is not on says so, and offers one tap:
    "Get on it", which asks the phone for its snapshot.
  - Starting a match on the watch while the phone is a guest now asks once: "This takes
    your iPhone off Ada's match."
- **Rationale**: closes RW-2 and makes RW-3 a choice the player makes. The `createdAt` rule
  stays for two unshared sessions, where it is right.

### D-13 · A notification brings the guest's watch round (FR-027, RW-1)

- **Decision**: when a guest's phone joins and its watch cannot be reached, the phone posts
  a local notification: "You're on Ada's match. Tap to follow on your watch." With the phone
  locked in a bag, iOS shows it on the watch. Tapping it opens Rekkert there, which makes
  the link reachable, and the match arrives.
  - Permission is asked when joining if the app has not asked before. The app already posts
    round alarms (`Shared/RoundAlarmFollower.swift`).
  - A watch that is already reachable gets no notification.
- **Rationale**: the only way to bring the watch app to the front without a workout. The
  clarification chose it.

### D-14 · The host's watch runs sharing (FR-017..FR-020)

- **Decision**:
  - **Phone → watch**: a `hostingStatus` message on the existing `.sharing` channel,
    carrying the code, a QR image of the join link and each participant's name and state.
    - The channel is phone↔watch only; the shared-session scope drops it
      (`FanOutTransport.swift:62`).
    - The status is sent live while the watch can be reached, and in the application
      context for a cold start.
  - **Watch → phone**: `startHosting` and `stopHosting` requests, handled next to the
    existing `join` in `AppModel.joinFromWatch` (`Shared/AppModel.swift:290-297`).
  - **The QR image** is rendered on the phone with Core Image's `CIQRCodeGenerator` and sent
    as a small PNG.
- **Rationale**:
  - watchOS has no Core Image, and sending a picture keeps the watch simple.
  - The phone does the hosting (watchOS cannot advertise), so the watch only asks for it and
    shows what the phone reports.
- **Alternatives considered**:
  - A QR encoder in pure Swift on the watch. Rejected: more code to maintain, for one
    picture the phone can already make.
  - Sending the QR module matrix instead of a PNG. A fair second choice; the PNG is simpler
    to draw.

### D-15 · Joining and leaving on a guest's wrist (FR-021..FR-024)

- **Decision**:
  - "Join a match" is also in the watch's match menu, not only on the idle screen.
  - "Join again" shows whenever the watch is off a match whose kept code has not expired,
    and uses that code (D-1).
  - Leave stays in the menu, one tap away on the menu page, and gains a confirmation.
  - The narrow "Join again" condition at `WatchMenuView.swift:180` is replaced.
- **Rationale**: meets the tap counts in FR-022 and SC-008. Joining from the wrist keeps
  working whether or not the phone can be reached (`WatchStandIn`).

### D-16 · Tests that simulate the radio (SC-005, SC-011)

- **Decision**:
  - **Extract the core.** Move the host and guest state machine out of
    `BluetoothTransport` into a platform-free core in RekkertSync: turns and backlog, the
    ask/miss health, the handshake orchestration, the liveness of D-6, and the participant
    limit.
    - It sits behind a small `Radio` protocol: offer a chunk and get back whether it was
      taken, a ready callback, write and did-write, subscribe and unsubscribe, connect and
      disconnect, and an injected clock.
    - `BluetoothTransport` becomes a thin CoreBluetooth adapter over that core. On macOS
      the core builds and runs.
  - **A `SimulatedRadio` in the tests** models:
    - a shared transmit queue of K slots, and how many slots a ready callback frees;
    - an airtime budget per second;
    - latency and loss per link;
    - an app being suspended;
    - an app being ended and run again, with or without restoration;
    - address rotation;
    - a limit on connections.
  - **A multi-device harness** runs a host and up to seven guests, each a `MatchStore` with
    its watch on a `LoopbackTransport` pair, over that radio.
  - **Every root cause is first written as a test that fails on today's code** (RC-1..RC-5,
    RC-7, RW-2, RW-4), then fixed.
- **Rationale**:
  - Principle III wants the engine tested without a device, and the Simulator has no
    Bluetooth at all.
  - Today none of the draining, ask/miss, redial or handshake logic runs under `swift test`
    (BT:1023-1045 is an inert stub).
  - This is what the clarification asked for: simulated tests on every push, plus one real
    field test.
- **Alternatives considered**: device-only tests. Rejected by the clarification.

### D-17 · Field validation (SC-001, SC-002, SC-003, SC-010, SC-012, SC-009)

- **Decision**:
  - Before release, one field test on real devices: four iPhones and four watches, Wi-Fi
    off, following [quickstart.md](quickstart.md). Each phone's sharing record and the
    battery readings are exported as the evidence.
  - The seven-guest case is shown in simulated-link tests and checked at the first club
    night afterwards.
- **Rationale**: as clarified. The record (D-11) doubles as the test log.

## Open items that only real devices can settle

| Item | Covered by |
|---|---|
| Whether iOS reliably shows a backgrounded host to a guest scanning with its screen off (RC-6) | Field test step "both in bags, walk out and back"; records show redial and discovery times |
| How many central connections one iPhone peripheral holds in practice (RC-7, D-8) | Field test plus club night; the limit is a constant |
| Whether one shared transmit queue carries seven guests within SC-002 (D-4) | Simulated airtime budget calibrated against the four-phone field test; L2CAP remains the fallback |
