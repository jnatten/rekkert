---

description: "Task list for Reliable Session Sharing, and Sharing from the Wrist"
---

# Tasks: Reliable Session Sharing, and Sharing from the Wrist

**Input**: Design documents from `specs/001-fix-session-sharing/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required. The spec asks for an automated check per cause found (FR-006, SC-005)
and simulated-link coverage of everything under "Staying on the match" (SC-011). The
constitution (Principle III) asks for tests first. In every story, the test tasks come
first and **must fail on the code as it is before that story's implementation**.

**Organization**: Tasks are grouped by user story, in the spec's priority order, so each
story can be built, tested and shipped on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: The user story the task belongs to (US1–US5, as in spec.md)
- Paths are from the repository root. `RekkertSync/` means
  `Packages/RekkertKit/Sources/RekkertSync/`, `RekkertCore/` means
  `Packages/RekkertKit/Sources/RekkertCore/`, `SyncTests/` means
  `Packages/RekkertKit/Tests/RekkertSyncTests/`, `CoreTests/` means
  `Packages/RekkertKit/Tests/RekkertCoreTests/`
- `RC-n`, `RW-n` and `D-n` refer to the root causes and decisions in research.md
- Tuist globs `App/Sources/**`, `WatchApp/Sources/**` and `Shared/**`, and SwiftPM picks up
  new files in existing targets, so new files need no project or package changes

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A known-good baseline, and the one test utility everything after needs

- [X] T001 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh` on the current commit and confirm both pass; any failure found here is not this feature's and must be raised before going on
- [X] T002 [P] Add `TestClock` in `SyncTests/TestClock.swift`: a manually advanced `Clock` (`Duration`-based, `now` moves only on `advance(by:)`), with sleepers resumed in deadline order, for driving radio timing and liveness without real waits

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make the Bluetooth logic testable on macOS (D-16), add the new message kinds,
and let the host know links by device. Every story needs these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Define the platform-free radio seam in `RekkertSync/Radio/Radio.swift`. A `Radio` protocol keyed by opaque `PeerToken`s:
  - Host side: `offer(_ chunk: Data, to:) -> Bool`; a ready callback when the shared transmit queue has room; `maximumChunk(for:)`; subscribed and unsubscribed callbacks.
  - Guest side: `write(_:to:)` with a did-write callback; connect, disconnect, did-connect and did-disconnect.
  - Both sides: an injected `any Clock<Duration>`.
  - No `#if os(...)`, so it builds on macOS.
- [X] T004 Extract the state machine from `RekkertSync/BluetoothTransport.swift` into `RekkertSync/Radio/RadioCore.swift`, driven only through `Radio`:
  - What moves: `Peer` and its backlog, `step`/`drain`/`drainEverybody`, ask and miss with `LinkHealth`, the greeting/challenge/answer/confirm handshake with `LinkSeal`, the candidate and proof deadlines, and `ReconnectPolicy` use.
  - Replace `DispatchTime`/`asyncAfter` with the injected clock.
  - **Behaviour must not change in this task.** Existing `SyncTests` must still pass.
- [X] T005 Reduce `RekkertSync/BluetoothTransport.swift` to a CoreBluetooth adapter: the `Shim` delegates translate into `Radio` calls on `RadioCore`, and the `PeerTransport` conformance forwards to it. The macOS stub (today at BluetoothTransport.swift:1023-1045) keeps compiling. `scripts/verify.sh` must pass (depends on T004).
- [X] T006 [P] Build `SimulatedRadio` in `SyncTests/SimulatedRadio.swift`, implementing `Radio` over one shared medium driven by `TestClock`. It must model:
  - a host transmit queue of K slots, with a configurable number of slots freed per ready callback;
  - an airtime budget in bytes per second, shared by all links;
  - latency and loss per link;
  - an app suspended (no callbacks, link kept);
  - an app ended (links and memory gone) and relaunched, with or without restoration;
  - host address rotation (a pending connect to the old address never completes);
  - a cap on connections.

  Depends on T003 only.
- [X] T007 Build `CourtHarness` in `SyncTests/CourtHarness.swift`. It holds a host and up to 8 guests, each a `MatchStore` on a `RadioCore`-backed transport over one `SimulatedRadio`, and each with its own watch on a `LoopbackTransport` pair. Helpers:
  - `score(on:)`, `allInStep()`, `advance(by:)`;
  - `endApp(_:)` (drop the objects but keep that device's `SessionStore` temp directory and in-memory code keeper) and `relaunch(_:restored:)`;
  - `outOfRange(_:)` and `backInRange(_:)`;
  - per-point arrival times on every device.

  Depends on T005 and T006.
- [X] T008 [P] Add the message changes from `contracts/wire-protocol.md`.
  - **In `RekkertCore/Sync/Wire.swift`:**
    - `SharingFailure.noRoom`;
    - `Wire.sharingStopped(sessionID:)`;
    - `SharingSignal` cases `.hostingStatus(HostingStatus)`, `.startHosting`, `.stopHosting` and `.followPhone`;
    - `SharingStandby` gains optional `share: UUID?` and `startedAt: Date?`;
    - the application-context snapshot payload carries the phone's `SessionRole`.
  - **In `RekkertCore/Sync/ShareAccess.swift`:** `GuestCard` gains optional `pairedTo: DeviceID?`.
  - **New types** in `RekkertCore/Sync/Wire.swift`, from data-model.md:
    - `HostingStatus`, with fields `isSharing`, `code`, `joinLink`, `qr: Data?`, `participants: [ParticipantSummary]`, `canShare` and `failure`;
    - `ParticipantSummary`, with `name` and `state`.
  - **Tests first**, in `CoreTests/WireCompatibilityTests.swift`:
    - every new case round-trips;
    - a `GuestCard` JSON without `pairedTo` still decodes;
    - an unknown `SharingSignal` case fails to decode instead of crashing.
- [X] T009 [P] Add `Participant` and `ParticipantState` in `RekkertCore/Sync/ParticipantState.swift`.
  - **Tests first**, in `CoreTests/ParticipantStateTests.swift`.
  - **`Participant` fields:** `id: DeviceID`, `name: String?`, `devices: Set<DeviceID>`, `lastHeard: Date?`, `vector: VersionVector`, `access: ShareAccess.Level` and `isOlderBuild: Bool`.
  - **States, quoted from data-model.md:**
    - "`inStep`: `now − lastHeard ≤ 15 s` and `vector ≥ host.coverage`";
    - "`catchingUp`: `now − lastHeard ≤ 15 s` and `vector < host.coverage`";
    - "`outOfReach(since:)`: `now − lastHeard > 15 s`, with `since = lastHeard`".
  - **Limit:** "at most seven participants besides the host"; "A new device whose card names an existing participant does not count against it".
- [X] T010 Tag every proven link with its sender (D-7), across `RekkertCore/Sync/Wire.swift`, the transports and `RekkertSync/MatchStore.swift`. Depends on T004, T008 and T009.
  - `InboundPacket` in `RekkertCore/Sync/Wire.swift` gains an optional `link: LinkID`.
  - `RekkertSync/Radio/RadioCore.swift`, `RekkertSync/LocalNetworkTransport.swift` and `RekkertSync/FanOutTransport.swift` each record the `from:` of the first `hello` on a proven link against that link.
  - `RekkertSync/MatchStore.swift` keeps `participants: [DeviceID: Participant]` on the host, updated from hellos and guest cards. A proven link whose hellos name no sender becomes one participant with `isOlderBuild = true`.
- [X] T011 Report link changes with a reason (feeds D-10 and D-11), in `RekkertCore/Sync/Wire.swift` and every transport.
  - `PeerTransport` in `RekkertCore/Sync/Wire.swift` gains `linkChanges: AsyncStream<LinkChange>`: `up(LinkID)` or `down(LinkID, reason)`, with reasons `.timeout`, `.radioOff`, `.closedByPeer`, `.hungUp` and `.unknown`. Its default implementation is derived from `reachability`.
  - Implement it in `RekkertSync/Radio/RadioCore.swift`, `RekkertSync/LocalNetworkTransport.swift`, `RekkertSync/WatchConnectivityTransport.swift` and `RekkertSync/LoopbackTransport.swift`.
  - Depends on T004. It touches `Wire.swift`, so it runs after T008 and T010.

**Checkpoint**: the Bluetooth logic runs under `swift test`, the court harness works, and
the host knows links by device. `scripts/verify.sh` passes.

---

## Phase 3: User Story 1 — Every guest stays on the host's match without Wi-Fi (Priority: P1) 🎯 MVP

**Goal**: Fix the causes found (RC-1..RC-7, RW-4), so that a host and up to seven guests
stay in step with no Wi-Fi: phones in bags, an app ended, guests wandering off, and an
eighth guest refused.

**Independent Test**:

- On every push, `swift test --package-path Packages/RekkertKit --filter IncidentTests` and
  the US1 suites pass in `CourtHarness`.
- Before release, the four-phone field test in quickstart.md §4, steps 3–6.

### Tests for User Story 1 ⚠️ write first, watch them fail

- [X] T012 [P] [US1] Write `SyncTests/IncidentTests.swift` with `CourtHarness`, one test per cause. Each must fail on today's behaviour.
  - `hostAppEndedComesBackOnTheSameCode` (RC-1): host's app ended mid-match; guests in step within 30 s of the next point, with no code typed.
  - `silentFollowerIsNeverWrittenOff` (RC-2): a guest that never scores stays in step for 45 simulated minutes while the host misses three answers.
  - `everyGuestGetsTurns` (RC-3): 7 guests, one slot freed per ready callback; every guest gets every point.
  - `deliveryDoesNotSnowball` (RC-4): 7 guests over 2 simulated hours; per-guest bytes stay bounded; ≥95% of points within 5 s and all within 30 s (FR-002).
  - `guestAppEndedRejoinsWithoutTyping` (RC-5).
  - `eighthGuestIsToldNoRoom` (RC-7).
  - `standingInWatchCountsOnce` (RW-4).
- [X] T013 [P] [US1] Write `CoreTests/KeptCodeTests.swift` for the rules in data-model.md §KeptCode:
  - `expiresAt = startedAt + 12 h`;
  - "An expired item counts as absent and is deleted";
  - the host clears it on stop;
  - a guest's code is replaced on joining another code, kept after Leave, and forgotten when told sharing has stopped;
  - a typed code that never worked is never kept;
  - at most one kept code per device.
- [X] T014 [P] [US1] Write `SyncTests/HubSchedulerTests.swift` (D-4):
  - the turn cursor carries on across ready callbacks;
  - a host-side send never drains one guest greedily;
  - priority is handshake, then live, then catch-up;
  - a long catch-up frame interleaves with other guests' live pushes;
  - no guest is starved when one slot is freed per callback.
- [X] T015 [P] [US1] Write `SyncTests/PerParticipantDeliveryTests.swift` (D-5):
  - each participant is sent only `log.events(after: known[p])`;
  - "An event leaves the outbox once every participant that is not `outOfReach` for more than 60 s covers it";
  - a participant away for 10 minutes is caught up from the log, with nothing lost or doubled (FR-004);
  - a packet is never sent back on the link it came in on;
  - the phone↔watch pair outbox is unchanged.
- [X] T016 [P] [US1] Write `SyncTests/LivenessTests.swift` (D-6):
  - an idle guest sends a hello after 10 s with nothing sent;
  - after three misses, the host marks the guest out of reach and sends it a hello every 15 s, never going silent;
  - a guest that gets no answer to three hellos hangs up and dials again;
  - a guest is back in step within 30 s of the cause going away (FR-003, SC-003).
- [X] T017 [P] [US1] Write `SyncTests/CapacityTests.swift` (D-8, FR-001, FR-005):
  - seven guest participants are accepted;
  - the eighth is refused with `noRoom` and told within 15 s;
  - a phone and its standing-in watch count once;
  - a watch that joined alone counts once, and so does an older build;
  - a subscriber that has not proved itself within 15 s is dropped;
  - none of this pushes the other guests' points past FR-002's times.
- [X] T018 [P] [US1] Write `SyncTests/RestoreTests.swift` (D-2, FR-025, using `CourtHarness.relaunch`):
  - a host relaunched with an unexpired kept code shares again on the same code and share id, including between matches;
  - a relaunched guest resumes joining;
  - a guest that left, from its phone or from its watch, still has its kept code, and a relaunch does not put it back on;
  - a restored relaunch (Bluetooth restoration) and one woken by its watch both run `restore()`;
  - an expired code restores nothing;
  - past 12 hours, sharing carries on in the running app but the code is no longer kept.
- [X] T019 [P] [US1] Write `SyncTests/HostGoneAndStopTests.swift`:
  - **FR-026, host gone for good:** guests keep scoring; they are told "out of reach" with a since-time within 15 s; they cannot finish or settle the score; everything merges when the host is back.
  - **FR-028:** on Stop, every guest in reach receives `sharingStopped` before the links are cut, files its copy in History as it stood, and forgets the code.
  - **Fallback for an older host:** the guest shows out of reach.
- [X] T020 [P] [US1] Write `SyncTests/JoinRefusalTests.swift`:
  - **FR-008:** within 15 s each failure reports its own reason: no match on that code nearby (wrong code, or host out of range), `noRoom`, Bluetooth off, permission denied.
  - **FR-029:** with two hosts nearby on different codes, a guest joins only its own, and only a refused key counts against the code.
- [X] T021 [P] [US1] Write `SyncTests/StandInHandBackTests.swift` (FR-009):
  - with the guest's phone app ended and a workout running on the watch, the watch carries on with the match on its own;
  - without a workout and not in front, it reports that the phone needs opening;
  - when the phone's app runs again, the phone takes over, the watch stands down, and nothing is lost.

### Implementation for User Story 1

- [X] T022 [P] [US1] Add `KeptCode` in `RekkertCore/Sync/KeptCode.swift`.
  - Fields: `code: SessionCode`, `share: UUID`, `role: SessionRole`, `startedAt: Date`, and the computed `expiresAt` = `startedAt + 12 h`.
  - `current(now:)` returns `nil` past `expiresAt`.
  - Add the lifecycle rules from data-model.md §KeptCode. T013 must pass.
- [X] T023 [P] [US1] Add `CodeKeeper` in `RekkertSync/CodeKeeper.swift`.
  - A `CodeKeeping` protocol with `read() -> KeptCode?`, `keep(_:)` and `forget()`.
  - A Keychain implementation: one generic-password item, accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`. It deletes the item on read when it has expired.
  - An in-memory implementation for tests.
  - The code must never be written to `active.json` or any other file.
- [X] T024 [US1] Keep the code, and bring sharing back, in `RekkertSync/SharedSession.swift`. Depends on T022 and T023.
  - `keep` the code in `host()`, and when a join proves itself.
  - `forget` on a host's `stop()`. A guest forgets only on joining another code and when `sharingStopped` arrives. A guest's `leave()` and `letGo()` keep the code, since a Leave from its watch reaches the phone as `store.onLeft` → `letGo()` (SharedSession.swift:106) and FR-024 needs the code for **Join again**.
  - Add `restore()`. With a kept host code, rehost on the kept code and share id, even between matches. With a kept guest code, `resumeJoining` only if the stored role is still `.guest`, meaning it was on the match when its app was ended. A guest that had left keeps its code for **Join again** and is not put back on by a relaunch.
  - Relax the `store.state != nil` guard in `host()` for a restore only.
- [X] T025 [US1] Call `sharing.restore()` from `start()` in `Shared/AppModel.swift` on every launch path: user, WatchConnectivity background launch, and Bluetooth restoration. Correct the launch comment in `App/Sources/RekkertApp.swift` (today it claims the radio relaunches the app). `AppModel` is shared, so this runs on the watch too; T067 gives the watch a kept code to restore.
- [X] T026 [US1] Add CoreBluetooth state restoration in `RekkertSync/BluetoothTransport.swift` (D-3).
  - Create `CBPeripheralManager` with `CBPeripheralManagerOptionRestoreIdentifierKey`, and `CBCentralManager` with `CBCentralManagerOptionRestoreIdentifierKey`.
  - Implement `willRestoreState` on both. Hand the restored service, subscribed centrals and pending peripherals to `RadioCore` as existing peers, then trigger `restore()`.
  - iOS only.
- [X] T027 [P] [US1] Add `HubScheduler` in `RekkertSync/Radio/HubScheduler.swift`, a pure type (D-4):
  - a turn cursor that persists across ready callbacks;
  - a per-peer backlog in priority order: handshake, then live, then catch-up;
  - catch-up frames split so they interleave;
  - live frames keep their 4 s expiry.
- [X] T028 [P] [US1] Add `LinkLiveness` in `RekkertSync/Radio/LinkLiveness.swift`, a pure type (D-6), driven by the injected clock:
  - the guest's idle hello at 10 s;
  - the host's out-of-reach mark after three misses, then a hello every 15 s;
  - the guest's redial after three unanswered hellos.
- [X] T029 [US1] Make `RekkertSync/Radio/RadioCore.swift` use `HubScheduler` in place of `drainEverybody` and the greedy single-peer `drain`, for every host-side send. T014 and `everyGuestGetsTurns` must pass (depends on T027).
- [X] T030 [US1] Make `RekkertSync/Radio/RadioCore.swift` use `LinkLiveness`.
  - `missed()` for a central no longer just clears `isReady` and goes silent.
  - Liveness state changes are emitted on `linkChanges`.
  - T016 and `silentFollowerIsNeverWrittenOff` must pass (depends on T028).
- [X] T031 [US1] Add the participant limit (D-8) in `RekkertSync/Radio/RadioCore.swift`, `RekkertSync/SharedSession.swift` and `RekkertSync/LocalNetworkTransport.swift`. T017 and `eighthGuestIsToldNoRoom` must pass.
  - In `RekkertSync/Radio/RadioCore.swift` and `RekkertSync/SharedSession.swift`, the handshake refuses with `noRoom` once seven guest participants are on, counting a guest's phone and its card-naming watch as one.
  - Drop a subscriber that has not proved itself within 15 s.
  - Make `RekkertSync/LocalNetworkTransport.swift` refuse the same way.
- [X] T032 [US1] Fix rediscovery in `RekkertSync/Radio/RadioCore.swift` (RC-3 tail, RC-6).
  - A proof timeout never blacklists a host; only a refused key does.
  - `resumeJoining` clears the blacklist.
  - A pending connect to the host's old peripheral gives up after 20 s and rescans by service UUID, keeping the connect attempt alongside.
- [X] T033 [US1] Deliver per participant (D-5) in `RekkertSync/MatchStore.swift` and `RekkertSync/FanOutTransport.swift`. T015 and `deliveryDoesNotSnowball` must pass.
  - **In `RekkertSync/MatchStore.swift`:**
    - Keep `known: [DeviceID: VersionVector]` from hellos.
    - Send each participant only what it lacks, never the whole outbox to everyone.
    - Forget an outbox event per the rule quoted in T015.
  - **In `RekkertSync/FanOutTransport.swift`:** send per participant through the link tags from T010, and never send back to the source link.
  - **Retire `RekkertSync/ReplyFold.swift`** for shared-session sends. Keep the pair (phone↔watch) acknowledgement as it is.
- [X] T034 [US1] Count a standing-in watch with its phone (RW-4) in `RekkertSync/WatchStandIn.swift` and `RekkertSync/MatchStore.swift`. `standingInWatchCountsOnce` must pass.
  - In `RekkertSync/WatchStandIn.swift`, once the watch is proven on the host, it sends a `GuestCard` with `pairedTo` set to its phone's `DeviceID`.
  - In `RekkertSync/MatchStore.swift`, the host adds that watch to the phone's participant `devices`.
- [X] T035 [US1] Make Stop tell the guests (FR-028, D-9) in `RekkertSync/SharedSession.swift` and `RekkertSync/MatchStore.swift`.
  - `stop()` in `RekkertSync/SharedSession.swift` sends `Wire.sharingStopped` to every guest and waits up to 2 s for it to go out before cutting links.
  - In `RekkertSync/MatchStore.swift`, a guest receiving it files its copy in History as Leave does, forgets the kept code, and sets a "stopped by host" state for the screens.
- [X] T036 [US1] Show a host that is out of reach (FR-007, FR-026, D-10), from `RekkertSync/SharedSession.swift` to the phone's and watch's screens.
  - `RekkertSync/SharedSession.swift` exposes `hostOutOfReachSince: Date?`, set once the host has been out of reach for 15 s.
  - In `RekkertSync/MatchStore.swift`, finishing and settling are disabled on guests while it is set.
  - `App/Sources/Views/ConnectionBadge.swift` shows "Host out of reach since 20:41".
  - `WatchApp/Sources/Views/WatchCourtPage.swift` shows the same line beneath the score.
  - No stale score may be presented as current for more than 15 s (SC-004).
- [X] T037 [US1] Say why a join failed (FR-008), in `RekkertSync/SharedSession.swift`, `App/Sources/Views/JoinMatchSheet.swift` and `WatchApp/Sources/Views/WatchJoinView.swift`.
  - Map search and handshake outcomes to `SharingFailure` in `RekkertSync/SharedSession.swift`: no match found nearby, `noRoom`, Bluetooth off, permission denied. All within 15 s.
  - Show the contract's wording in `App/Sources/Views/JoinMatchSheet.swift` and `WatchApp/Sources/Views/WatchJoinView.swift`: "No match on 482 915 nearby", "No room on this match", "Bluetooth is off on your iPhone", "Rekkert can't use Bluetooth: allow it in Settings".
  - T020 must pass.
- [X] T038 [US1] Hand the match back from the watch to the phone (FR-009), in `RekkertSync/WatchStandIn.swift`. T021 must pass.
  - Extend `StandInPolicy` and the stand-in in `RekkertSync/WatchStandIn.swift`: stand in when the phone's app has ended, while a workout runs or Rekkert is in front.
  - Otherwise report `phoneNeedsOpening`.
  - Stand down as soon as the phone is through again.
- [X] T039 [US1] Run `swift test --package-path Packages/RekkertKit` (every suite T012–T021 green, existing suites unchanged) and `scripts/verify.sh`

**Checkpoint**: User Story 1 works on its own. Guests stay on through every cause found.
This is the MVP and can ship without the remaining stories.

---

## Phase 4: User Story 2 — See who is on, and why not (Priority: P2)

**Goal**: Show the host each guest's state, show every device its two links separately,
and keep a sharing record that can tell a watch↔phone break from a guest↔host break.

**Independent Test**: In `CourtHarness`, take one guest out of range, switch one guest's
radio off, and end a third guest's app. The host's participant list shows each change
within 15 s, and each phone's merged record lists the events in order (spec US2).

### Tests for User Story 2 ⚠️ write first, watch them fail

- [X] T040 [P] [US2] Write `CoreTests/LinkRecordTests.swift`:
  - entries merged by `time` and deduplicated by `id`;
  - "Days older than 7 are pruned when a file is opened";
  - the export matches `contracts/sharing-record.md` line for line, and parses back;
  - "No player names, scores or codes are ever recorded";
  - the header notes "Watch entries up to HH:MM (not in touch since)" when the watch is behind.
- [X] T041 [P] [US2] Write `SyncTests/WhoIsOnTests.swift`. In `CourtHarness` (the return to `inStep` needs T030 from US1):
  - the host's participants move `inStep` → `outOfReach(since:)` → `inStep` within 15 s of each change (FR-010);
  - each device exposes pair reachability and match reachability separately (FR-011);
  - the four staged failures of SC-006 each leave records that name the broken link.

### Implementation for User Story 2

- [X] T042 [P] [US2] Add `LinkRecord` and `LinkRecordEntry` in `RekkertCore/Sync/LinkRecord.swift`, per data-model.md.
  - Fields: `id`, `time`, `device` (`.phone`/`.watch`), `session: UUID?`, `link` (`.pair`/`.host(DeviceID)`/`.guest(DeviceID)`/`.radio`) and `kind: LinkEvent`. `LinkEvent` has every kind listed there, including the debug-only `pointArrived(latency:)`.
  - Add the plain-text export of `contracts/sharing-record.md`, and its parser.
  - T040 must pass.
- [X] T043 [US2] Add `LinkRecorder` in `RekkertSync/LinkRecorder.swift` (FR-012).
  - **Storage:** one file per day under Application Support, with `isExcludedFromBackup = true`, pruning days older than 7.
  - **Events recorded:**
    - from `linkChanges` (T011) and `RadioCore`: `proven`, `refused`, `wroteOff`, `redialled`;
    - `SharedSession` phase changes;
    - `standIn` and `standDown`;
    - `launched(.user/.background/.restored)`, and `appHadBeenEnded` when a launch finds a kept code;
    - `notificationPosted`;
    - in debug builds only, `pointArrived(latency:)`.
  - **Wiring:** create it in `Shared/AppModel.swift`.
- [X] T044 [US2] Send the watch's record to the phone (D-11) with `RekkertSync/WatchConnectivityTransport.swift`.
  - On the watch, `RekkertSync/WatchConnectivityTransport.swift` sends the day files with `WCSession.transferFile`, metadata `{"kind": "linkRecord", "day": "YYYY-MM-DD"}`.
  - On the phone, `LinkRecorder` merges them and records `recordReceived(from: .watch)`.
  - T041 must pass.
- [X] T045 [P] [US2] List the participants in `App/Sources/Views/ShareCodeSheet.swift`: name, or "Phone 1"…, with **In step**, **Catching up** or **Out of reach since 20:41**. Count participants instead of links, and remove the false "older Rekkert" claim (ShareCodeSheet.swift:38).
- [X] T046 [P] [US2] Update `App/Sources/Views/ConnectionBadge.swift`. Show the watch link and the match link separately (FR-011). For a host with a kept code but no hosting, show "Not sharing: tap to share again on 482 915", which calls `host()` on the kept code.
- [X] T047 [P] [US2] Add the watch status lines from `contracts/watch-ui.md` to `WatchApp/Sources/Views/WatchMenuView.swift` and `WatchApp/Sources/Views/WatchCourtPage.swift`.
  - Use the contract's wording exactly.
  - The menu shows every line that applies. The court page shows one, with the match first: "Host out of reach since…" outranks "iPhone out of reach".
  - Add the stand-in lines "Your iPhone's app was closed: following on the watch" and "Open Rekkert on your iPhone".
- [X] T048 [P] [US2] Add a **Sharing record** entry to `App/Sources/Views/SettingsView.swift`, and a new `App/Sources/Views/SharingRecordView.swift`. It shows the merged record newest first, with a Share button exporting `rekkert-sharing-YYYY-MM-DD.txt` through the system share sheet. Nothing leaves otherwise (FR-013).
- [X] T049 [P] [US2] In `WatchApp/Sources/WatchHaptics.swift`, tap the wrist following `HapticPreferences` when the wearer has been out of reach of the match for 15 s, and again when back in step (FR-032).
- [X] T050 [US2] Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh`

**Checkpoint**: User Stories 1 and 2 both work. Failures are visible as they happen and
explainable afterwards.

---

## Phase 5: User Story 3 — A guest's watch is on whatever its phone is on (Priority: P2)

**Goal**: A guest's watch always ends up on its phone's shared match. It does so without a
race against its own session, a notification brings it round, and one tap fixes it when it
does not.

**Independent Test**: The guest joins on the phone three times: with Rekkert in front on
the watch, with it closed and opened later, and with a warm-up of the watch's own running.
Each time the watch ends up on the shared match (spec US3).

### Tests for User Story 3 ⚠️ write first, watch them fail

- [X] T051 [P] [US3] Add tests to `SyncTests/GuestWatchFollowTests.swift`:
  - the snapshot carries the role, and a watch running a warm-up of its own adopts its guest phone's match without waiting for a point;
  - a `.role` arriving on its own triggers a re-sync;
  - the watch's own unshared match is filed through `.displaced` (FR-015);
  - `.followPhone` returns the phone's snapshot with its role;
  - `startingOwnMatchTakesPhoneOff` is true exactly while the watch's phone is a guest on a shared match (FR-030).

  Also add `guestWatchTakesItsPhonesMatch` (RW-2) to `SyncTests/IncidentTests.swift`.

### Implementation for User Story 3

- [X] T052 [US3] Make a guest phone's match win on its watch (D-12, FR-014), in `RekkertSync/MatchStore.swift`.
  - Put `role`, plus a summary of the shared match the phone is on (session id and host name), in the application-context payload with the log.
  - On the watch, adopt that match whenever the context says the phone is a guest, before any `createdAt` comparison (today MS:1543-1553).
  - Re-sync when `.role` arrives (today MS:1312).
  - Keep the `createdAt` rule for two unshared sessions.
  - Expose `startingOwnMatchTakesPhoneOff: Bool` on `MatchStore`: true on a watch whose paired phone is a guest on a shared match. T051 asserts it, and T055 reads it.
- [X] T053 [US3] Handle `.followPhone`: in `Shared/AppModel.swift`'s `joinFromWatch`, call into `RekkertSync/MatchStore.swift` to re-offer the phone's snapshot with its role.
- [X] T054 [US3] Add the banner "Your iPhone is on Ada's match" with **Get on it** to `WatchApp/Sources/Views/WatchRootView.swift` and `WatchApp/Sources/Views/WatchCourtPage.swift`. **Get on it** sends `.followPhone`.
  - Show the FR-016 reason when the watch cannot do it: "iPhone out of reach", or the phone cannot reach the host.
- [X] T055 [US3] Confirm before a guest's watch starts a match of its own (FR-030). In `WatchApp/Sources/Views/WatchRootView.swift`, Quick match and the presets page ask first whenever `store.startingOwnMatchTakesPhoneOff` (T052) is true: "This takes your iPhone off Ada's match." The view holds no rule of its own (constitution, Principle I).
- [X] T056 [US3] Post the notification that brings the watch (FR-027, D-13), in `Shared/AppModel.swift`, iOS only.
  - **When:** on joining as a guest while the watch cannot be reached.
  - **What:** a local notification titled "You're on Ada's match", body "Tap to follow on your watch.", in a category the watch app handles.
  - **Permission:** asked through the same flow as `Shared/RoundAlarmFollower.swift`, if it has never been asked.
  - **If notifications are not allowed:** say on the phone that the watch will show the match once Rekkert is opened on it.
  - **Withdraw** it once the watch is on the match.
  - **Record** `notificationPosted`.
- [X] T057 [US3] Handle the notification on the watch, in `WatchApp/Sources/RekkertWatchApp.swift`: register the category, and on a tap open on the match and send `.followPhone`.
- [X] T058 [US3] Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh`

**Checkpoint**: The guest's watch follows its phone. US1–US3 each work on their own.

---

## Phase 6: User Story 4 — The host runs sharing from the wrist (Priority: P3)

**Goal**: The host's watch can start and stop sharing, show the code as digits and a
scannable picture, and show who is on, all with the phone in a bag.

**Independent Test**: With the host's phone in a bag, the host:

1. starts sharing on the watch;
2. watches a guest join from what the watch shows, and arrive in **Who's on**;
3. stops sharing from the watch.

Spec US4. Scenario 6 also needs T035 from US1.

### Tests for User Story 4 ⚠️ write first, watch them fail

- [X] T059 [P] [US4] Write `SyncTests/HostWatchSharingTests.swift`:
  - the phone sends `hostingStatus` live and in the context whenever sharing starts or stops, a participant's state changes, or the code changes (FR-019);
  - `.startHosting` works only while a match is on;
  - `.stopHosting` stops sharing and guests get `sharingStopped`;
  - with the phone unreachable, the request fails on the watch and nothing changes (FR-020);
  - between matches the code stays shared.

### Implementation for User Story 4

- [X] T060 [US4] Publish `HostingStatus` from the phone, via `RekkertSync/SharedSession.swift` and `Shared/AppModel.swift`.
  - Build it in `RekkertSync/SharedSession.swift`, and send it from `Shared/AppModel.swift` on every relevant change, live and in the application context.
  - It carries `participants` from T009/T010 and the join link `https://rekkert.natten.dev/join#<code>`.
  - The QR image is drawn as a PNG by `App/Sources/JoinQRImage.swift` (new, Core Image `CIQRCodeGenerator`, iOS only), injected into `AppModel` so the watch build never links Core Image.
- [X] T061 [US4] Handle `.startHosting` and `.stopHosting` in `joinFromWatch` in `Shared/AppModel.swift`. They call `sharing.host()`, allowed only while a match is on, and `sharing.stop()`. Each answers with a `hostingStatus` carrying `failure` when nothing could be done.
- [X] T062 [P] [US4] Add `WatchApp/Sources/Views/WatchCodeView.swift`.
  - **Code:** six digits spanning the screen width, as `482 915`, on every supported watch size (FR-017).
  - **Below it:** the QR image, scannable by an iPhone camera from about 20 cm on the smallest watch (FR-018), and "Scan with the Camera to join".
  - **VoiceOver** reads the code digit by digit (FR-031).
  - Update it in place when the code changes.
- [X] T063 [P] [US4] Add `WatchApp/Sources/Views/WatchGuestsView.swift`: one row per participant, with name or "Phone 1"…, and **In step**, **Catching up** or **Out of reach since 20:41**, with VoiceOver labels.
- [X] T064 [US4] Add the host's items to `WatchApp/Sources/Views/WatchMenuView.swift`.
  - **Items:** **Share match**, **Code**, **Who's on**, and **Stop sharing** with the confirmation "Stop sharing? Everyone else leaves this match."
  - **Visibility, quoted from contracts/watch-ui.md:** "**Share match** shows only while a match is on and the phone is not sharing. **Code**, **Who's on** and **Stop sharing** show only while it is. None of them shows on a guest's watch, and **Leave** never shows on the host's".
  - **Court page:** show "Sharing · 3 on" beneath the score, in `WatchApp/Sources/Views/WatchCourtPage.swift`.
- [X] T065 [US4] Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh`

**Checkpoint**: The host never needs the phone to share.

---

## Phase 7: User Story 5 — Guests join and leave from the wrist (Priority: P3)

**Goal**: A guest with the phone in a bag can join, leave and join again from the watch
alone, with no retyping while the match is still shared.

**Independent Test**: A guest joins from the watch with the phone in a bag, leaves from the
watch, and joins again from the watch. The phone follows each step (spec US5). Rejoining
needs the kept code from US1.

### Tests for User Story 5 ⚠️ write first, watch them fail

- [X] T066 [P] [US5] Write `SyncTests/GuestWristTests.swift`:
  - the guest's watch keeps the code from `standby`, including `share` and `startedAt`, through `CodeKeeper`;
  - **Join again** works without typing while the match is shared;
  - with the phone in a bag (its app suspended), joining from the watch puts the watch and the phone on the match within 10 s of the last digit, on `TestClock` (SC-008);
  - **Join again** after the host stopped reports "no match on that code nearby" and forgets the code (FR-024);
  - Leave on the watch, after its confirmation, takes the phone off, and Leave on the phone takes the watch off (FR-022, FR-023);
  - joining from the match menu replaces a match of the watch's own, filing it;
  - a watch whose phone is hosting must confirm before joining another match (FR-021);
  - a watch alone stays on while a workout runs, and catches up when Rekkert comes in front (FR-021, built in T067);
  - a watch whose app is ended and relaunched with an unexpired kept code, its phone unreachable, is back on the match with nothing typed (FR-025).

### Implementation for User Story 5

- [X] T067 [US5] Let the guest's watch keep the code, and stay on without its phone, in `RekkertSync/WatchStandIn.swift` and `RekkertSync/SharedSession.swift`.
  - The phone sends `standby` with `share` and `startedAt`, from `RekkertSync/SharedSession.swift` and `Shared/AppModel.swift`.
  - The guest's watch keeps it with `CodeKeeper` in `RekkertSync/WatchStandIn.swift`, under the same rules as T022.
  - On every watch launch, `restore()` (T024, run by T025 on the watch as well) hands an unexpired kept guest code to the stand-in. A watch whose app was ended goes back to the match by itself, without the code typed again (FR-025).
  - A watch on the match without its phone keeps its link while a workout runs. When Rekkert comes back in front after a suspension, it says hello, and dials again if the link has gone, so it catches up (FR-021).
- [X] T068 [US5] Change the guest's items in `WatchApp/Sources/Views/WatchMenuView.swift`.
  - Add **Join a match** to the match menu.
  - Replace the narrow **Join again** condition (today WatchMenuView.swift:180): show it while an unexpired kept code exists and the watch is off that match.
  - **Leave** asks "Leave Ada's match? Your iPhone leaves too." and shows only on a guest's watch.
- [X] T069 [US5] Update `WatchApp/Sources/Views/WatchRootView.swift` and `WatchApp/Sources/Views/WatchJoinView.swift`.
  - Show **Join again** on the start screen too.
  - If the watch's phone is hosting, confirm before joining: "Joining another match stops sharing for everyone on yours."
- [X] T070 [US5] Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh`

**Checkpoint**: All five stories work on their own.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T071 [P] Update `README.md`.
  - **"Joining from the wrist":** the watch dials the host itself, and the host's watch shares.
  - **"How syncing works":** the code is kept for at most 12 hours in this-device Keychain, Bluetooth state restoration, fair turns, per-participant delivery, and liveness.
  - **Add a section** on the sharing record.
  - **Remove** "the code is never kept" and "there is no version of this where the code is read out from a wrist".
- [X] T072 [P] Add a third phase to `scripts/share.sh`: end the host's app (`xcrun simctl terminate`) and relaunch it. Assert the host comes back on the same code, and that every `active.json` again holds the same events with nothing typed.
- [X] T073 [P] Add `-rekkert-demo-watch-page code` and `-rekkert-demo-watch-page follow-phone` to `WatchApp/Sources/Views/WatchDemoLaunch.swift`, and list them in `README.md`'s launch-argument list.
- [X] T074 [P] Add a debug-only **End app as the system would** to `App/Sources/Views/SettingsView.swift`. It calls `kill(getpid(), SIGKILL)`, so Bluetooth restoration can be tested on devices (quickstart §4 step 5).
- [X] T075 Make the new and changed watch screens work with VoiceOver and larger text sizes (FR-031): `WatchMenuView.swift`, `WatchCourtPage.swift`, `WatchRootView.swift`, `WatchJoinView.swift`, `WatchCodeView.swift` and `WatchGuestsView.swift` in `WatchApp/Sources/Views/`.
- [X] T076 Check whether any task added an Info.plist key or entitlement. If one did, add its assertion to `scripts/verify.sh`. If none did, note that in the PR description.
- [X] T077 Run levels 1–3 of `specs/001-fix-session-sharing/quickstart.md` and record the results in the PR description.
- [-] T078 **Deferred: skipped for now, and blocks nothing.** Run the real-device field test (manual): `specs/001-fix-session-sharing/quickstart.md` §4, four iPhones and four watches, Wi-Fi off.
  - Record the results in a new `specs/001-fix-session-sharing/field-test.md`: each step's outcome, the time from the last digit typed on a watch to that guest being on the match (SC-008), the exported sharing records, the SC-002 arrival times and the SC-012 battery figures.
  - Set `SimulatedRadio`'s airtime budget from the measured arrival times (SC-009).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. It **blocks every story**.
  - T004 → T005 → T007.
  - T003 → T006 → T007.
  - T008 and T009 → T010 → T011.
- **US1 (Phase 3)**: after Foundational. It is the MVP.
- **US2 (Phase 4)**: after Foundational, and after T030 from US1. A guest that comes back
  shows **In step** again only once it sends the idle hello T030 adds, which T041 and T044
  check. The rest of US2 uses the participants (T009/T010) and link changes (T011) from
  Foundational.
- **US3 (Phase 5)**: after Foundational. Independent of US1 and US2.
- **US4 (Phase 6)**: after Foundational. Scenario 6 (guests told on Stop) needs T035 from US1.
- **US5 (Phase 7)**: after US1, because Join again needs the kept code (T022–T024).
- **Polish (Phase 8)**: after the stories being shipped. T078 is deferred and blocks nothing.

### Within Each Story

- Tests first. They must fail before the implementation tasks start.
- Pure models (`RekkertCore`) come before the transports and stores (`RekkertSync`), which
  come before the screens (`App/`, `WatchApp/`).
- Tasks that edit the same file run in ID order:
  - `RadioCore.swift`: T029 → T030 → T031 → T032;
  - `MatchStore.swift`: T033 → T034 → T035 → T036;
  - `WatchMenuView.swift`: T047 → T064 → T068.
- Each story ends with its own run of `swift test` and `scripts/verify.sh`.

### Parallel Opportunities

- Phase 2: T006, T008 and T009 together, once T003 is in.
- US1: all ten test tasks, T012–T021. Then T022, T023, T027 and T028 together.
- US2: T040 and T041. Then T042, T045, T046, T047, T048 and T049.
- US4: T062 and T063 together.
- After Foundational, US3 can go to a different developer alongside US1. So can US2's
  record and screens (T040, T042, T045–T049); T041 and T044 wait for T030.
- Polish: T071–T074 together.

---

## Parallel Example: User Story 1

```bash
# Tests, all at once (each must fail first):
Task: "IncidentTests in Packages/RekkertKit/Tests/RekkertSyncTests/IncidentTests.swift"
Task: "KeptCodeTests in Packages/RekkertKit/Tests/RekkertCoreTests/KeptCodeTests.swift"
Task: "HubSchedulerTests in Packages/RekkertKit/Tests/RekkertSyncTests/HubSchedulerTests.swift"
Task: "PerParticipantDeliveryTests in Packages/RekkertKit/Tests/RekkertSyncTests/PerParticipantDeliveryTests.swift"
Task: "LivenessTests in Packages/RekkertKit/Tests/RekkertSyncTests/LivenessTests.swift"

# Then the pure pieces, all at once:
Task: "KeptCode in Packages/RekkertKit/Sources/RekkertCore/Sync/KeptCode.swift"
Task: "CodeKeeper in Packages/RekkertKit/Sources/RekkertSync/CodeKeeper.swift"
Task: "HubScheduler in Packages/RekkertKit/Sources/RekkertSync/Radio/HubScheduler.swift"
Task: "LinkLiveness in Packages/RekkertKit/Sources/RekkertSync/Radio/LinkLiveness.swift"
```

## Parallel Example: User Story 2

```bash
Task: "LinkRecordTests in Packages/RekkertKit/Tests/RekkertCoreTests/LinkRecordTests.swift"
Task: "WhoIsOnTests in Packages/RekkertKit/Tests/RekkertSyncTests/WhoIsOnTests.swift"
# then
Task: "Participant list in App/Sources/Views/ShareCodeSheet.swift"
Task: "Sharing record screen in App/Sources/Views/SharingRecordView.swift"
Task: "Wrist taps in WatchApp/Sources/WatchHaptics.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 and Phase 2. The Bluetooth core is now testable, which is most of the risk.
2. Phase 3 (US1). Fixes every cause found.
3. **Stop and validate**: run the US1 suites, `scripts/verify.sh`, and quickstart §4
   steps 3–6 on four phones.
4. Ship to TestFlight. This alone answers "the guests fell off".

### Incremental Delivery

1. US1: guests stay on. (MVP)
2. US2: who is on, and the sharing record. The next field failure can be explained.
3. US3: the guest's watch follows its phone.
4. US4: the host shares from the watch.
5. US5: guests join and leave from the watch.
6. Polish. The field test (T078) is deferred, and nothing waits on it.

---

## Notes

- [P] tasks touch different files and depend on nothing unfinished.
- Tests in each story must fail before that story's implementation.
- Principle II: no task changes the reducer, the merge or the event format. If one seems to
  need to, stop and amend the plan first.
- Commit after each task or logical group, using jj and the conventional-commit style.

---

## Phase 9: Convergence

- [ ] T079 Make a code typed on the watch say why within 15 s when its phone is reachable but finds nothing: today the phone's 14 s search and then the wrist's own 14 s search add up to about 26 s (`StandInPolicy` hands over on the phone's `notFound`; `SharedSession.searchLimit`), and pin it with a simulated test in `SyncTests/GuestWristTests.swift` per FR-008 (partial)
- [ ] T080 Tell a guest already on the match that Bluetooth is off, or its permission denied, on the phone and on the watch, instead of only "out of reach": `RekkertSync/SharedSession.swift` gives `.bluetoothOff`/`.bluetoothDenied` only on a first join and otherwise just records `radioOff`, and `WatchStandIn.Status` has no such line; cover it with a simulated test per FR-008 and Edge Cases "Bluetooth off or denied" (partial)
- [ ] T081 Add a simulated test of an americano over two courts with a host and seven guests, every guest's watch on, for at least 30 simulated minutes, checking that every phone and watch shows the host's score at each check and that points arrive within FR-002's times; the seven-guest tests today run without watches and on a traditional match (`IncidentTests`, `CapacityTests`). Use the current `SimulatedRadio` speed; its field calibration stays with the deferred T078 per US1/AC6, SC-009, SC-011 (partial)
- [ ] T082 Tell a guest's watch when the host stops sharing, as the contract's status line "… stopped sharing. Saved in History.", not only its phone (`App/Sources/Views/RootView.swift`); `WatchStandIn` has no such status per US4/AC6, FR-028, contracts/watch-ui.md (missing)
- [ ] T083 Add a simulated test in which a watch on the match without its phone, with no workout and Rekkert in the background, comes to the front and is in step within 10 s; `SyncTests/StandInHandBackTests.swift` covers only the workout and "phone needs opening" cases per FR-002, FR-021 (partial)
- [ ] T084 Let the one-line status beneath the score on the watch grow with larger text sizes, as the menu's status lines now do; it is a fixed 11 pt in the compact header of `Shared/ScoreboardView.swift` per FR-031 (partial)
- [ ] T085 Name the host in guest-facing texts as `contracts/watch-ui.md` writes them ("Your iPhone is on Ada's match", "Leave Ada's match?", "Ada stopped sharing", "You're on Ada's match"): guests are never told the host's name, so it has to travel from the host, with older builds left as they are per contracts/watch-ui.md, FR-016 (partial)
