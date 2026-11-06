---

description: "Task list for Asking at the End of a Shared Match, and Sharing Between Matches"
---

# Tasks: Asking at the End of a Shared Match, and Sharing Between Matches

**Input**: Design documents from `specs/004-match-end-sharing-prompt/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required. The constitution (Principle III) asks for engine tests first, and every
gap found in research (R-2's silent arrival, R-3, R-4, R-5, R-7, R-13, R-15) gets a test that fails on
`9d930e27` before it is fixed. In every story the test tasks come first and **must fail for
the stated reason before that story's implementation**.

**Organization**: Tasks are grouped by user story, in the spec's priority order, so each
story can be built, tested and shipped on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: The user story the task belongs to (US1–US4, as in spec.md)
- Paths are from the repository root. Some are shortened:

  | Short | Full path |
  |---|---|
  | `RekkertSync/` | `Packages/RekkertKit/Sources/RekkertSync/` |
  | `RekkertCore/` | `Packages/RekkertKit/Sources/RekkertCore/` |
  | `SyncTests/` | `Packages/RekkertKit/Tests/RekkertSyncTests/` |
  | `CoreTests/` | `Packages/RekkertKit/Tests/RekkertCoreTests/` |

- `R-n` and `D-n` refer to the findings and decisions in research.md. `MS:`, `SS:` and `AM:`
  line numbers are as of `9d930e27`, and drift as tasks land, so find the code by the
  function named.
- Tuist globs `App/Sources/**`, `WatchApp/Sources/**` and `Shared/**`, and SwiftPM picks up
  new files in existing targets, so new files need no project or package changes.
- All UI text comes verbatim from [contracts/screens.md](contracts/screens.md). "Ada" there
  stands for the host's name, or "the host" when there is none.
- The new-match popup has three names: the engine calls it a notice (`NewMatchNotice`), the
  spec a dialog, and the screens show it as an alert. They are one thing.
- Views never carry out an answer themselves. They forward it to `SharedSession.answer(_:)`
  on the phone or `WatchStandIn.answer(_:)` on the watch (T010, D-4).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A known-good baseline

- [X] T001 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh` on `dbc72a3b` and confirm both pass. Any failure found here is not this feature's, and must be raised before going on.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The pure between-matches state, the additive wire and record fields, and the
store's plumbing for asking and answering. Every story needs these.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [P] Write `CoreTests/BetweenMatchesTests.swift` (Swift Testing, `@Suite("Between matches")`) for the rules in data-model.md. It fails to compile until T003. Cover:
  - **Who is asked.** `side(role:pairedRole:isWatch:)`: on a phone the side is `role`, and on a watch it is `pairedRole`. `.solo` asks nothing.
  - **One question per session.** A second `matchEnded` for an already-answered session opens nothing.
  - **Leave wins.** `answered(.stay)` followed by `answered(.leave)` for the same session closes the question, and so does the reverse order.
  - **The idle clock** (`idleLimit` is "30 minutes"):
    - it starts at `matchEnded`;
    - it is nil after `matchBegan`;
    - `isIdleExpired` is false at 29:59 and true at exactly 30:00 (`now >= idleSince + idleLimit`);
    - `answered(.stay)` and `answered(.keepSharing)` do not move `idleSince`.
  - **Scoring.** `blocksScoring` is true exactly while `newMatch != nil`.
  - **The host's next match.** `hostsNextMatchArrived` closes an open `ask`, reports it as unanswered, opens `newMatch`, and clears `idleSince`.
  - **`wantsNotification(appIsActive:watchReachable:)`** is true only when both are false (D-11).
  - **Persistence.** A `Codable` round trip of every field.
- [X] T003 Create `RekkertCore/Sync/BetweenMatches.swift` so T002 passes. Every type is `Codable, Sendable, Hashable`, with no platform imports:
  - `BetweenMatches`, with `idleSince: Date?`, `ask: EndOfMatchAsk?` and `newMatch: NewMatchNotice?`.
  - `EndOfMatchAsk`, with `session: UUID`, `side: Side` and `askedAt: Date`. `Side` is `.host(guestsOn: Int)` or `.guest(hostName: String?, hostKeepsSharing: Bool)`.
  - `NewMatchNotice`, with `session: UUID`, `hostName: String?` and `arrivedAt: Date`.
  - `BetweenMatchesAnswer`, with `session: UUID` and `choice: Choice`. `Choice` is `.keepSharing`, `.stopSharing`, `.stay`, `.leave` or `.ok`.
  - `static let idleLimit: TimeInterval = 30 * 60`.
  - The mutating transitions `matchEnded(session:side:now:)`, `answered(_:)`, `hostsNextMatchArrived(_:)`, `matchBegan()`, `sharingStarted(now:)`, `joinedBetweenMatches(now:)` and `sharingEnded()`. `hostsNextMatchArrived` returns whether it closed an unanswered question.
  - `isIdleExpired(now:matchOn:)`, `blocksScoring`, `static func side(role:pairedRole:isWatch:) -> SessionRole?` and `static func wantsNotification(appIsActive:watchReachable:) -> Bool`.
- [X] T004 [P] Add `keptSharingAfter: UUID?` and `func keepingSharing(after session: UUID) -> ShareAccessTable` to `RekkertCore/Sync/ShareAccess.swift`. `keepingSharing(after:)` does `revision += 1`, like `with(hostName:)`. Extend `CoreTests/ShareAccessTests.swift`:
  - a table built with it `supersedes` the one before;
  - JSON without the key decodes with nil;
  - the key round-trips.
- [X] T005 [P] Extend the wire in `RekkertCore/Sync/Wire.swift` (D-4, D-6, D-7):
  - add `SharingStopReason` (`.host`, `.idle`);
  - change `Wire.sharingStopped(sessionID: UUID)` to `sharingStopped(sessionID: UUID, reason: SharingStopReason?)`;
  - change `SharingSignal.hostStoppedSharing(host: String?)` to `hostStoppedSharing(host: String?, reason: SharingStopReason?)`;
  - add `SharingSignal.answered(BetweenMatchesAnswer)` and `SharingSignal.newMatch(NewMatchNotice)`;
  - add `HostingStatus.endedBy: SharingStopReason?`.

  Then fix every exhaustive switch and call site the compiler names: `MatchStore.keepToSayAgain` (the new signals say nothing again), `RekkertSync/FanOutTransport.swift`, `RekkertSync/WatchStandIn.swift`, `Shared/AppModel.swift` `joinFromWatch`, and the `onSharing` switch in `SyncTests/CourtHarness.swift` `boot`. Extend `CoreTests/WireCompatibilityTests.swift`:
  - the new cases round-trip (`everyNewMessageRoundTrips`);
  - a `sharingStopped`, a `hostStoppedSharing` and a `HostingStatus` encoded without the new keys decode with nil.
- [X] T006 [P] Add `.nextFromHost(UUID)` to `MatchMoment` in `RekkertCore/Sync/MatchMoment.swift`, and handle it wherever `MatchMoment` is switched on: `Shared/AppModel.swift`, and the workout follower `Shared/WorkoutFollower.swift` if it switches on it. For the follower, treat it like `.began`.
- [X] T007 [P] Add the six `LinkEvent` cases of [contracts/sharing-record.md](contracts/sharing-record.md) to `RekkertCore/Sync/LinkRecord.swift`, each with its `text` and its parse in `init(text:)` and the `plain` table:
  - `endOfMatchAsked`;
  - `endOfMatchAnswered(EndOfMatchChoice)`;
  - `endOfMatchUnanswered`;
  - `newMatchShown`;
  - `newMatchAnswered(NewMatchChoice)`;
  - `idleStop`.

  Add a write → export → `init(text:)` round trip for each in `CoreTests/LinkRecordTests.swift`.
- [X] T008 Add `betweenMatches: BetweenMatches?` to `ActiveSession` in `RekkertCore/Persistence/SessionStore.swift`. Decode it with `decodeIfPresent`, so an older `active.json` reads as empty. Add a test to `SyncTests/RestoreTests.swift` that an older `active.json` restores with an empty `betweenMatches`.
- [X] T009 Give `RekkertSync/MatchStore.swift` its between-matches plumbing (depends on T003–T008):
  - `public private(set) var betweenMatches: BetweenMatches`, loaded from and saved with `ActiveSession` in `persist()` and at init.
  - `public func answer(_ choice: BetweenMatchesAnswer.Choice)`. It applies `answered` for the open `ask` or `newMatch`, and notes `endOfMatchAnswered` or `newMatchAnswered` on the recorder. It sends `.sharing(.answered(…))` to the pair through the durable path used by `sendDurably`, and persists.
  - In `handle(_:)`'s `.sharing` case, from the paired device only:
    - apply `.answered` to `betweenMatches`;
    - for `.newMatch(notice)`, open the notice unless an answer for that session was already heard, and note `newMatchShown`.

    Still pass both to `onSharing`.
  - `canScore` and `canRunRounds` also return false while `betweenMatches.blocksScoring` (FR-013).
  - An injectable `participantCount: () -> Int` (default `participantStates().count`). The watch's `AppModel` sets it from `standIn.hosting?.participants.count`.
  - `MatchStore.answer` carries out nothing but the answer itself. Stopping and leaving belong to T010.
- [X] T010 Add the one engine entry point per device for every answer (D-4, Principle I). Depends on T009.
  - **`SharedSession.answer(_ choice:)`** in `RekkertSync/SharedSession.swift`:
    1. call `store.answer(choice)` first, so the answer is recorded and sent to the pair while the question still exists;
    2. then for `.stopSharing` call `stop()`, and for `.leave` take the guest's leave path, which is `stop()` for a guest's phone;
    3. do nothing more for `.keepSharing`, `.stay` and `.ok`.
  - **`WatchStandIn.answer(_ choice:)`** in `RekkertSync/WatchStandIn.swift`:
    - for `.leave`, call `store.answer(.leave)` and then the watch's own `SharedSession.leave()`;
    - for `.stopSharing`, call `stopHosting()` (T016 adds the wait for the phone to confirm);
    - for every other choice, call `store.answer`.

  Expose both through the watch's and the phone's `AppModel` as `model.sharing` and `model.standIn`, as today.
- [X] T011 Add helpers to `SyncTests/CourtHarness.swift`:
  - `finish(on:)`, which finishes from a given device;
  - `discard(on:)`;
  - `answer(_ choice:on:)`, which calls `SharedSession.answer` on a phone and `WatchStandIn.answer` on a watch (T010), as the views do;
  - `betweenMatches(of:)`;
  - `isWaiting(_:)`, true for a `.guest` role with an empty log;
  - `canScore(on:)`.

  Make sure `run(for:)` can advance the `TestClock` by 31 minutes without real waits.

**Checkpoint**: `swift test --package-path Packages/RekkertKit` passes. Nothing visible has
changed yet.

---

## Phase 3: User Story 1 - The host is asked at the end of a shared match (Priority: P1) 🎯 MVP

**Goal**: When a shared match ends, the device it was ended on asks the host to keep sharing
or stop, with the guest count. One answer counts for the phone and the watch.

**Independent Test**: A host shares a match with two guests and finishes it. Stop sharing
from the question tells both guests, who keep the match in History. Repeated with Keep, both
guests stay on and get the next match.

### Tests for User Story 1 ⚠️

- [X] T012 [US1] Write the host half of `SyncTests/EndOfMatchQuestionTests.swift` on `CourtHarness(guests: 2, withWatches: true)`. Each test fails on `9d930e27` because nothing is asked:
  - `hostIsAskedWithTheGuestCount`: after `finish(on: host.phone)`, the host phone's and the host watch's `ask` is `.host(guestsOn: 2)`. With no guests joined, it is `.host(guestsOn: 0)`.
  - `callingOffAsksToo`: same, after `discard`.
  - `aTournamentRoundDoesNotAsk`: ending a round of an americano opens nothing; finishing the tournament does.
  - `stopFromTheQuestionTellsEveryGuest`: `answer(.stopSharing, on: host.phone)`. Every guest gets the stop notice, keeps the match in History, and forgets the code. Nothing asks twice (FR-003). The host's record has `endOfMatchAnswered(stopSharing)`, written before sharing stopped.
  - `keepChangesNothing`: the code, the participants and their access are unchanged.
  - `anAnswerOnTheWatchClosesThePhone`: within 10 s of being in touch (FR-005).
  - `stopOnTheWatchWithThePhoneOutOfReachChangesNothing`: the watch's `ask` stays open, and sharing is still on (FR-007).
  - `aRelaunchDoesNotAskAgain`: `endApp` and then `relaunch` the host phone after answering. `ask` stays nil.
  - `startingTheNextMatchCountsAsKeep`: the host starts a match with the question open. `ask` closes, and guests get the match (FR-006).

### Implementation for User Story 1

- [X] T013 [US1] In `RekkertSync/MatchStore.swift` `concludeIfFinished` (MS:945-985), right where the log is replaced:
  - when `BetweenMatches.side(role:pairedRole:isWatch: !keepsHistory)` is `.host`, call `betweenMatches.matchEnded(session:side: .host(guestsOn: participantCount()), now:)`;
  - note `endOfMatchAsked`;
  - persist.

  In `startNewSession`, `configure` and `start(_:)` on the host side, call `betweenMatches.matchBegan()`. T039 covers the remaining paths.
- [X] T014 [US1] In `MatchStore.answer(_:)`, for `.keepSharing` on a store whose role is `.host`:
  - set `accessTable = accessTable.keepingSharing(after: ask.session)`;
  - `persist()`;
  - `shareAccess()` (D-5).

  `.stopSharing` only closes the question; `SharedSession.answer` (T010) then stops sharing.
- [X] T015 [US1] Give `SharedSession.stop` in `RekkertSync/SharedSession.swift` a `reason: SharingStopReason = .host` parameter, and pass it through a new `reason` parameter on `MatchStore.sayStoppedSharing(within:reason:)` into `Wire.sharingStopped(sessionID:reason:)`.
- [X] T016 [US1] Finish `WatchStandIn.answer(.stopSharing)` (T010) in `RekkertSync/WatchStandIn.swift`, for a host watch answering at the end of the match:
  - it calls `stopHosting()`;
  - it calls `store.answer(.stopSharing)` only once `hosting?.isSharing == false` comes back;
  - on `.cannotReachPhone` the question stays open (FR-007).
- [X] T017 [US1] Add the host's end-of-match alert to `App/Sources/Views/RootView.swift`, driven by `model.store.betweenMatches.ask` with a `.host` side. Use the title, message and buttons from contracts/screens.md, "End of match, host":
  - **Keep sharing** → `model.sharing.answer(.keepSharing)`;
  - **Stop sharing** (destructive) → `model.sharing.answer(.stopSharing)`.

  Present it after the finish confirmation has gone, using the same delayed-task pattern as the "Start a workout?" alert. Extend `isPresenting` so the effort sheet waits while the question is open.
- [X] T018 [US1] In `WatchApp/Sources/Views/WatchResultView.swift`, while a `.host` question is open, replace **Done** with "Keep sharing?", the guest count, **Keep sharing** and **Stop sharing**, each calling `model.standIn.answer(_:)` (T010, T016). Show "Can't reach your iPhone" when `standIn.hostingTrouble == .cannotReachPhone`. When the match was called off and there is no result, show the same choices as a `confirmationDialog` on `WatchIdleView` in `WatchApp/Sources/Views/WatchRootView.swift`.
- [X] T019 [US1] Run `swift test --package-path Packages/RekkertKit --filter EndOfMatchQuestion`. T012 passes, and the whole package stays green.

**Checkpoint**: The host is asked on whichever device ended the match, and Stop ends sharing
in one tap from the result (SC-003).

---

## Phase 4: User Story 2 - Each guest is asked, and the next match never arrives unannounced (Priority: P1)

**Goal**: Guests are asked to stay or leave within 30 s of the match ending, and within 5 s for
most. The host's next
match arrives with a one-tap dialog that blocks scoring until OK, and with a notification
when neither device has Rekkert in front.

**Independent Test**: Three guests. One leaves, one stays, one does not answer. The host
keeps sharing and starts the next match. The leaver never sees it. The other two get the
dialog naming the host, and scoring waits for OK.

### Tests for User Story 2 ⚠️

- [X] T020 [US2] Add the guest half to `SyncTests/EndOfMatchQuestionTests.swift`:
  - `guestsAreAskedWithinThirtySeconds`: each guest phone's and watch's `ask` is `.guest(hostName:, hostKeepsSharing: false)` within 30 s of `finish(on: host.phone)`. Run it over the simulated Bluetooth path too (SC-006). Fails today.
  - `leaveTakesThePhoneAndTheWatchOff`: Leave on the guest phone. Both devices leave, History holds the match, the code is kept for Join again, and the host's participants drop the guest within 15 s (FR-009). Fails today: the host shows the guest out of reach (R-13) until T026.
  - `aGuestOutOfReachAtTheEndIsAskedOnReturn`: a guest out of range when the host finishes is asked once back in range while the host is still between matches. If the host has started the next match by then, the guest gets the new-match notice instead, and its record has `endOfMatchUnanswered`.
  - `aLeaverNeverGetsTheNextMatch`: still in range, the host keeps sharing and starts a match. The leaver's log stays empty (FR-015, SC-001).
  - `stayWaitsForTheNextMatch`: `isWaiting` is true until the host's next match.
  - `unansweredIsStay`: no answer; the next match arrives with a notice. The guest's record has `endOfMatchUnanswered` (FR-012).
  - `keepIsToldToGuests`: after the host's Keep (T014), the guest's open `ask` has `hostKeepsSharing == true` on the phone and the watch (D-5).
  - `aStopReplacesTheQuestion`: the host stops while a guest's question is open. The question closes, and the stop notice is raised (FR-008).
  - `leaveWinsOverStay`: the guest's phone and watch are separated. The phone says Stay and the watch says Leave. On reuniting, both have left (FR-011). Fails until T027.
  - `leaveOnTheWatchBetweenMatchesTakesThePhoneOff`: with nothing on, Leave on the guest's watch (`answer(.leave, on: guest.watch)`). The phone leaves too, keeps the code for Join again, and the host's list drops the guest within 15 s (FR-009, FR-019). Fails today: the phone ignores the watch's `.left` (R-15).
- [X] T021 [P] [US2] Write `SyncTests/NextMatchNoticeTests.swift`:
  - `theNextMatchArrivesWithANotice`: the host keeps sharing and starts a match. Every guest phone and watch has `newMatch` naming the host, and the guest's record has `newMatchShown`. Fails today.
  - `aBluetoothGuestGetsTheNextMatchWithinThirtySeconds`: with only the simulated Bluetooth path, a waiting guest holds the host's next match, with its notice, within 30 s on the `TestClock` (FR-014, spec 001 FR-002).
  - `scoringWaitsForOK`: `canScore(on:)` is false on a guest until `answer(.ok)`. Points scored on the host and on other guests still reach that guest, and every device converges (Principle II).
  - `okOnTheWatchClosesThePhone`: within 10 s of being in touch (FR-013).
  - `leaveFromTheNotice`: both devices leave, and the host's list drops the guest.
  - `aStandingInWatchGetsTheNotice`: `endApp` the guest phone; the watch stands in. The host's next match opens `newMatch` on the watch.
  - `theHostIsNeverShownANotice`: on the host's phone and watch.
  - `joiningMidMatchShowsNoNotice`: a guest joining a match that is already on is not asked to confirm what it asked for.

### Implementation for User Story 2

- [X] T022 [US2] In `MatchStore.concludeIfFinished`, when the side is `.guest`, call `betweenMatches.matchEnded(session:side: .guest(hostName: accessTable?.hostName, hostKeepsSharing: accessTable?.keptSharingAfter == session), now:)` and note `endOfMatchAsked`. This works on a guest's phone through `role`, and on its watch through `pairedRole`. Use `accessTable?.hostName`, not `hostName`, which is nil when `canEndSession`.
- [X] T023 [US2] In `MatchStore.take(_:from:)` (MS:559), when the incoming table's `keptSharingAfter` equals an open `ask.session`, set that ask's `hostKeepsSharing` to true and persist.
- [X] T024 [US2] In `MatchStore.handle(_:)`'s `.snapshot` branch where an empty log adopts (MS:1853-1876), when the incoming match is the host's next one, do all of the following. "The host's next one" means `role == .guest` (or `pairedRole == .guest` on a watch standing in), `!packet.isFromPairedDevice`, `!isJoining` and `incoming.takesBack == nil`.
  - Call `betweenMatches.hostsNextMatchArrived(NewMatchNotice(session:hostName: accessTable?.hostName, arrivedAt: now()))`.
  - Note `endOfMatchUnanswered` if it closed an open question, and `newMatchShown`.
  - Fire `onMatch?(.nextFromHost(id))` in place of `announceBegan()`'s `.began`.
  - On a phone, send `.sharing(.newMatch(notice))` to the pair durably.
  - Persist.

  In `offerToThePair()`, re-send the open notice, so a watch woken by the notification gets it (D-11).
- [X] T025 [US2] Make `MatchStore.answer(_:)` close a `.guest` question on `.stay` and `.leave`, and the notice on `.ok` and `.leave`. Stay and OK change nothing else. Leave is carried out after it by `SharedSession.answer` or `WatchStandIn.answer` (T010), through the existing leave paths.
- [X] T026 [US2] Make a leaving guest say goodbye (D-16, FR-009):
  - add `leaving: Bool?` to `GuestCard` in `RekkertCore/Sync/ShareAccess.swift`, defaulting to nil in `init`, and a round trip with and without the key in `CoreTests/WireCompatibilityTests.swift`;
  - add `public func sayLeaving(within patience: Duration = .seconds(2)) -> Task<Void, Never>` to `RekkertSync/MatchStore.swift`, shaped like `sayStoppedSharing` (MS:1506-1520). It sends `guestCard(GuestCard(device:name:pairedTo:leaving: true))` live on each link in `transport.links`, and finishes once each has answered or `patience` is up. It does nothing when the role is not `.guest` (or `pairedRole == .guest` on a watch standing in);
  - in `RekkertSync/SharedSession.swift`, start `store.sayLeaving()` at the top of a guest's `stop()`, of `leave()` and of `letGo()`, before anything else. Keep the store's leaving immediate, and move `cutLinks()` into a task that runs once the goodbye finishes, as the host's `stop()` does with its farewell (SS:463-467). Skip the deferred cut if a new join or hosting has started by then, the same guard the host's `stop()` uses;
  - in `handle(_:)`'s `.guestCard` case (MS:1740), on the host, when `card.leaving == true`, call `participants.remove(card.device)`, which also drops its paired watch, then `onParticipantsChanged`. Add no admission for that card in `noteParticipant` (MS:440).

  `letGo()` also runs when a guest steps off to a match of its own (MS:909), so that path says goodbye too. This makes T020's `leaveTakesThePhoneAndTheWatchOff` and T021's `leaveFromTheNotice` pass.
- [X] T027 [US2] Let the watch's Leave reach the phone between matches (D-17, R-15). In `RekkertSync/MatchStore.swift` `handle(_:)`'s `.left` case (MS:1673-1677), when `packet.isFromPairedDevice && role == .guest && log.isEmpty && !isJoining`, act whatever session the message names: `dropSession()`, then `onLeft?()`, so `SharedSession.letGo()` sends T026's goodbye and cuts the links. Leave the rule for a match that is on unchanged, and do not tell the watch back. This makes T020's `leaveWinsOverStay` and `leaveOnTheWatchBetweenMatchesTakesThePhoneOff`, and T046's `leavingWhileWaitingTakesThePhoneAndTheWatch`, pass.
- [X] T028 [US2] In `Shared/AppModel.swift` (iOS), on `onMatch(.nextFromHost(session))`, post a notification when `BetweenMatches.wantsNotification(appIsActive: UIApplication.shared.applicationState == .active, watchReachable: store.isPairReachable)` (D-11). `AppModel` already reads `applicationState` this way (AM:145).
  - permission through `RoundAlarmFollower.askToNotify()`;
  - category `rekkert.followMatch`, identifier `next-<session>`;
  - title "Ada started a new match", or "The host started a new match" with no name; body "Tap to open it.";
  - note `notificationPosted`.

  Withdraw it, both delivered and pending, as soon as `store.betweenMatches.newMatch` closes, on either device. Follow the `beckonTheWatch` (AM:973-1000) shape.
- [X] T029 [US2] Check `WatchApp/Sources/RekkertWatchApp.swift`'s `didReceive`. A tap on a `next-…` notification takes the existing `standIn.followThePhone()` path, and the watch then shows the notice re-sent by T024's `offerToThePair`. Add nothing else unless that path drops the identifier.
- [X] T030 [US2] In `App/Sources/Views/RootView.swift`:
  - **The guest's end-of-match alert**: title "Stay for Ada's next match?", message per contracts/screens.md, **Stay** → `model.sharing.answer(.stay)`, **Leave** → `model.sharing.answer(.leave)`.
  - **The new-match alert**: "Ada started a new match", **OK** → `model.sharing.answer(.ok)`, **Leave** → `model.sharing.answer(.leave)`.
  - The new-match alert replaces an open question, and the "stopped sharing" alert replaces either.
  - The "Start a workout?" alert, which `.nextFromHost` also raises (T006), waits until the new-match alert is answered. Hold it back in the same delayed-task check that `isPresenting` drives, as T017 does for the effort sheet.
- [X] T031 [US2] On the watch:
  - In `WatchApp/Sources/Views/WatchResultView.swift`, guest answers in place of **Done**: **Stay** → `model.standIn.answer(.stay)`; **Leave** → `model.standIn.answer(.leave)`.
  - In `WatchApp/Sources/Views/WatchRootView.swift`, the full-screen new-match alert: **OK** → `model.standIn.answer(.ok)`; **Leave** → `model.standIn.answer(.leave)`. The watch's "Start a workout?" alert waits until it is answered.
  - Add a `newMatch()` cue to `WatchApp/Sources/WatchHaptics.swift` that plays `.notification` through its existing `play` and honours `preferences()`, called when the alert opens.
  - The court page's taps already read `store.canScore` (WatchCourtPage:98, 122), so scoring waits by itself; check the phone's match views do too (TraditionalMatchView:18, 99 and the others).
- [X] T032 [US2] Run `swift test --package-path Packages/RekkertKit --filter "EndOfMatchQuestion|NextMatchNotice"`. T020 and T021 pass, and the whole package stays green.

**Checkpoint**: No guest's screen changes to a new match without the dialog (SC-002), and
every guest who stays gets each next match while every leaver gets none (SC-001).

---

## Phase 5: User Story 3 - The host shares with no match on (Priority: P2)

**Goal**: Sharing starts, shows and stops from the phone's Home and the watch's start screen
with no match on. The host's Stop reaches waiting guests, and a forgotten share stops after
30 minutes with no match on.

**Independent Test**: With no match on, the host shares from Home, two guests join, a match
started reaches both, and Stop from Home tells both. Left sharing for 31 simulated minutes, it
stops by itself and everyone is told why.

### Tests for User Story 3 ⚠️

- [X] T033 [P] [US3] Write `SyncTests/HostWithNoMatchTests.swift`:
  - `shareFromThePhoneWithNoMatchOn`: `sharing.host()` with `store.state == nil` gives a code, and guests can join. Fails today (SS:267).
  - `shareFromTheWristWithNoMatchOn`: `.startHosting` from the host watch gives the watch a `hostingStatus` with a code and `canShare == true`. Fails today (SS:769).
  - `theFirstMatchReachesEveryGuest`.
  - `aGuestsPhoneStillCannotHost`.

  In `SyncTests/HostWatchSharingTests.swift`, rewrite `sharingStartsFromTheWristOnlyWithAMatchOn` (:41) to the new rule, as `sharingStartsFromTheWristWithOrWithoutAMatch`.
- [X] T034 [P] [US3] Write `SyncTests/StopBetweenMatchesTests.swift`:
  - `stopWithNoMatchOnReachesEveryGuest`: finish, have every guest choose Stay, then `sharing.stop()` on the host. Every guest gets `hostStoppedSharing`, forgets the code, has role `.solo`, and does not get the host's next match. Fails today (R-3).
  - `theStopSaysWhy`: the guests' `hostStopReason` is `.host`.
  - `aGuestStillJoiningIgnoresIt`.
  - `anOlderHostsStopReachesNewGuests`: deliver `Wire.sharingStopped(sessionID: UUID(), reason: nil)` on the host link to a waiting guest. It leaves.
- [X] T035 [P] [US3] Write `SyncTests/IdleStopTests.swift` on `TestClock` (FR-026, SC-008). Each fails today, except `matchesPauseTheClock`:
  - `thirtyMinutesWithNoMatchStopsSharing`: by 31 min after the last match, the host is not sharing, `stoppedForIdle` is true, and every guest got `reason == .idle`. The host's and guests' records hold `idleStop`.
  - `matchesPauseTheClock`: a 45-minute match, then a 25-minute break, is still sharing.
  - `aRelaunchAfterThirtyMinutesDoesNotShare`: `endApp` the host with no match on, advance 31 min, `relaunch`. Nothing goes back up.
  - `aResumeAfterThirtyMinutesDoesNotShare`: suspend the host, advance 31 min, `resume()`. Same result.
  - `aGuestLeavesByItself`: the host is out of range. At 30 min the waiting guest leaves on its own, keeps History, and forgets the code.
  - `aGuestRelaunchedAfterThirtyMinutesDoesNotRejoin`: `endApp` a waiting guest, advance 31 min, `relaunch`. It does not redial, and it has left.
  - `stayAndKeepDoNotResetTheClock`.

### Implementation for User Story 3

- [X] T036 [US3] Remove the need for a match on (D-8):
  - In `RekkertSync/SharedSession.swift`, drop the `store.state != nil` guard from `host(code:)` (SS:267).
  - In `startHostingFromTheWatch` (SS:769), guard only on `store.role != .guest`.
  - In `hostingStatus` (SS:763), set `canShare: store.role != .guest`.
  - In `RekkertSync/MatchStore.swift` `startSharing()`, call `betweenMatches.sharingStarted(now:)` when the log is empty.
- [X] T037 [US3] Let Stop reach a waiting guest (D-7):
  - In `MatchStore.handle(_:)` `.sharingStopped` (MS:1765-1771), also act when `role == .guest && log.isEmpty && !isJoining && !packet.isFromPairedDevice`, whatever session it names.
  - Pass `reason` to a widened `onStoppedByHost: ((SharingStopReason?) -> Void)?`.
  - On an empty log, leave without filing: `leaveSharedSession()` already files only a log with progress.
  - Call `betweenMatches.sharingEnded()`.
  - In `SharedSession.stoppedByHost`, take the reason and set a new `public private(set) var hostStopReason: SharingStopReason?`, cleared by `acknowledgeStoppedSharing()`.
  - In `Shared/AppModel.swift`, send `.hostStoppedSharing(host:, reason:)` to the watch (AM:182).
  - In `RekkertSync/WatchStandIn.swift`, keep the reason beside `hostStoppedSharing`.
- [X] T038 [US3] Add the idle watch to `RekkertSync/SharedSession.swift` (D-10):
  - A task on the injected `sleep`, every 30 s, while hosting or while the store is a guest with an empty log, that checks `store.betweenMatches.isIdleExpired(now:matchOn: store.state != nil)`. When it is expired:
    - **On the host**: `stop(reason: .idle)`, set `public private(set) var stoppedForIdle = true`, and note `idleStop`.
    - **On a guest**: run the stopped-by-host path locally with `.idle` (cut links, forget the code, `store.leaveSharedSession()`), and note `idleStop`.
  - Run the same check at the top of `restore()` (SS:295) and `resume()` (SS:368), before anything is revived.
  - Add `acknowledgeIdleStop()`.
  - Set `HostingStatus.endedBy = .idle` while `stoppedForIdle` is true.
- [X] T039 [US3] In `RekkertSync/MatchStore.swift`, make the paths T013 did not cover also call `betweenMatches.matchBegan()` and persist: the join adoption (MS:1803), T024's adoption, and History's resume, `MatchStore.resume(_:from:)`, which `AppModel.resume(_:)` calls (AM:850-855). Make `sharingEnded()` run on `stopSharing()`, `dropSession()` and `follow(_:)`.
- [X] T040 [US3] Add the host's rows to the "Play together" section of `App/Sources/Views/HomeView.swift`, per contracts/screens.md "Between matches: the phone's Home":
  - **Share**, when `model.sharing.code == nil` and the role is not `.guest`. It calls `model.sharing.host()` and sets `model.showingShareCode = true`.
  - "Sharing on 482 915" with "N on · until you stop", opening `ShareCodeSheet`.
  - **Stop sharing**, with the confirmation "Stop sharing? Everyone else stops following your matches.", then `model.sharing.stop()`.
  - The new footer text.
- [X] T041 [US3] Add the line "Shared with N on <code>" while `model.sharing.code != nil` (FR-020) in three places:
  - above **Start** in `App/Sources/Views/NewSessionView.swift`;
  - above the presets section in `HomeView.swift`;
  - beside **Resume** in `App/Sources/Views/HistoryDetailView.swift` (:138).

  Nothing offers to start unshared.
- [X] T042 [US3] Add the idle-stop alerts.
  - **On the phone**, in `App/Sources/Views/RootView.swift`:
    - the host's "Sharing stopped" alert, driven by `sharing.stoppedForIdle` and acknowledged with `acknowledgeIdleStop()`;
    - the guest's "Ada's sharing has ended" variant of the stop alert when `hostStopReason == .idle`.
  - **On the watch**, the same pair of messages in `WatchApp/Sources/Views/WatchRootView.swift`, from `standIn.hosting?.endedBy` and the kept reason.
  - Texts from contracts/screens.md "Sharing stopped".
- [X] T043 [US3] Add the host card to the top of `WatchIdleView` in `WatchApp/Sources/Views/WatchRootView.swift`:
  - **Share**, which calls `standIn.startHosting()` and opens the code page;
  - "Sharing · N on";
  - **Code**, which opens the `WatchCodeView` sheet;
  - **Stop sharing**, behind a confirmation;
  - shown only when the phone's side is not `.guest`.

  Put the "Sharing · N on" line at the top of `WatchPresetsView` (WatchRootView.swift:324-377) too, so a preset started there says it will be shared (FR-020). In `WatchApp/Sources/Views/WatchCodeView.swift`, `.nothingToShare` now means only "your iPhone is on someone else's sharing"; reword it to match.
- [X] T044 [P] [US3] Apply the wording table in contracts/screens.md, "Wording that moves from 'this match' to 'sharing'" (FR-022), to:
  - `App/Sources/Views/MatchOptionsMenu.swift` ("Share", "Share again");
  - `App/Sources/Views/ShareCodeSheet.swift` (title "Sharing");
  - `WatchApp/Sources/Views/WatchMenuView.swift` ("Share", the Stop confirmation and the Leave confirmation).
- [X] T045 [US3] Run `swift test --package-path Packages/RekkertKit --filter "HostWithNoMatch|StopBetweenMatches|IdleStop|HostWatchSharing"`. T033–T035 pass, and the whole package stays green.

**Checkpoint**: A host can share, show the code and stop with no match on, in at most two
taps (SC-005), and a forgotten share ends by itself (SC-008).

---

## Phase 6: User Story 4 - Guests join, wait and leave with no match on (Priority: P2)

**Goal**: A guest who joins with nothing on becomes a waiting guest at once, sees whose
sharing it is on, and can leave from the phone's Home or the watch's start screen.

**Independent Test**: With the host sharing and no match on, a guest joins from the phone.
Its phone and watch both show "On Ada's sharing · waiting". It leaves from the watch's start
screen, and the phone leaves too; the host's next match does not arrive.

### Tests for User Story 4 ⚠️

- [ ] T046 [US4] Write `SyncTests/JoinBetweenMatchesTests.swift`:
  - `aJoinWithNoMatchOnWaitsAsAGuest`: once the host's empty answer to the guest's hello arrives, the guest phone has role `.guest`, `isJoining == false`, `accessTable?.hostName` set, and `betweenMatches.idleSince` set. Fails today (R-5).
  - `aJoinMidMatchIsStillAJoin`: the host has a match on, and the guest's link comes up before the host's snapshot arrives (R-14). The guest never becomes a waiting guest, adopts the match through the join branch, and has no `newMatch`.
  - `itsWatchWaitsToo`: the watch's `pairedRole == .guest`, and it has the host's name.
  - `theFirstMatchArrives`: the host starts a match, and the waiting guest adopts it.
  - `leavingWhileWaitingTakesThePhoneAndTheWatch`: once from the phone and once from the watch. Both devices leave each time, the host drops the guest, and keeps sharing with the other guests.
  - `aJoinAskedForByTheWatchWaitsToo`: the watch asks its phone to join (`.join` over the pair) with the host between matches. The phone becomes a waiting guest with `joiningForThePair` cleared, and the host's first match arrives on both with the new-match notice.
  - `joinAgainWhileWaiting`: after leaving, the watch's `standIn.canJoinAgain` and the phone's `sharing.keptGuestCode` bring it back with no code typed.
  - `aJoinWithItsOwnMatchOnStillWaitsInTheSheet`: unchanged behaviour. The own match is filed when the host's arrives.
  - `startingOwnMatchWhileWaitingLeavesSharing`: `startingOwnMatchLeavesSharing` is true on the phone and the watch, and starting steps off.

### Implementation for User Story 4

- [ ] T047 [US4] Add a private `joinedBetweenMatches(access:)` to `RekkertSync/MatchStore.swift` (D-9). Call it from the `incoming.isEmpty` branch of `handle(_:)`'s `.snapshot` case (MS:1794-1802), when `isJoining && log.isEmpty && !packet.isFromPairedDevice`: the host has answered the guest's hello with nothing on. It then:
  - sets `role = .guest`;
  - sets `isJoining = false`, `joiningForThePair = false` and `joinRefuses = nil`, as `cancelJoining()` does;
  - takes the `access` that came with the snapshot, through `take(_:from:)`, now that the role admits it;
  - calls `betweenMatches.joinedBetweenMatches(now:)`;
  - calls `persist()`, `shareRole()` and `shareAccess()`.

  Do not call it from `SharedSession.noteProven()`, which runs before the host's match arrives (R-14). Keep that branch's `offerOurSession(live: !isJoining)` as it is.
- [ ] T048 [US4] Add `public var startingOwnMatchLeavesSharing: Bool` to `RekkertSync/MatchStore.swift`. It is `keepsHistory ? role == .guest : startingOwnMatchTakesPhoneOff` (D-15).
- [ ] T049 [US4] Add the guest's rows to the "Play together" section of `App/Sources/Views/HomeView.swift`:
  - "On Ada's sharing" with "Waiting for Ada's next match", when `model.store.role == .guest && model.store.state == nil`;
  - **Leave**, with the confirmation "Leave Ada's sharing? Your watch leaves too.", then `model.sharing.stop()`;
  - **Join again**, when `model.sharing.keptGuestCode` is set and the phone is not on it, which joins that code.
- [ ] T050 [US4] In `App/Sources/Views/ConnectionBadge.swift` `SharingBadge`, remove the between-matches guest `Menu` (55-70), since Home's section replaces it. Keep the glyph and every in-match branch.
- [ ] T051 [US4] In `App/Sources/Views/NewSessionView.swift` (**Start**), `App/Sources/Views/HomeView.swift` (preset taps) and `App/Sources/Views/HistoryDetailView.swift` (**Resume**, :138), when `model.store.startingOwnMatchLeavesSharing` is true, ask first with "Start your own match? This takes you off Ada's sharing.", offering **Start anyway** and **Cancel** (FR-021).
- [ ] T052 [US4] Add the guest card to `WatchIdleView` in `WatchApp/Sources/Views/WatchRootView.swift`:
  - "On Ada's sharing" and "Waiting for the next match";
  - **Leave**, with the confirmation "Leave Ada's sharing? Your iPhone leaves too.", then `model.sharing.leave()`.

  Reword `AsksBeforeTakingThePhoneOff` to "This takes your iPhone off Ada's sharing."
- [ ] T053 [US4] Run `swift test --package-path Packages/RekkertKit --filter JoinBetweenMatches`. T046 passes, and the whole package stays green.

**Checkpoint**: A guest can join, see the wait and leave between matches, in at most two
taps (SC-004).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Mixed versions, docs, accessibility, and the gate

- [ ] T054 [P] Write `SyncTests/OlderBuildBetweenMatchesTests.swift` (D-13). Each case works on payloads with the new keys stripped or with nil values, so no real older build is needed:
  - an older host never sets `keptSharingAfter`, so the guest's question asks only stay or leave;
  - an older host's `sharingStopped` without `reason` stops a waiting new guest, reading as `.host`;
  - a guest whose pair drops the `.answered` and `.newMatch` signals still leaves on Leave, through the existing path, and is asked on each device separately without stalling;
  - a guest card without `leaving` reads as an ordinary card, and a host that ignores the key shows the leaver out of reach after 15 s, as today.
- [ ] T055 [P] Update `README.md`'s "How syncing works" and the sharing sections around lines 339–423 and 748–762:
  - sharing lasts until it is stopped, or for 30 minutes with no match on;
  - the host and the guests are asked at the end of every match;
  - the next match arrives with a dialog;
  - Home and the watch's start screen carry the sharing controls.
- [ ] T056 Make an accessibility pass over every new row, card and alert (FR-023):
  - combined VoiceOver labels as in contracts/screens.md, with digits read one by one;
  - `scaledFont` on the watch;
  - check at the largest Dynamic Type size on both simulators that nothing truncates.
- [ ] T057 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh`. Both pass with no new Info.plist key or entitlement. If one turned out to be needed, add its assertion to `scripts/verify.sh` in the same change.
- [ ] T058 Walk [quickstart.md](quickstart.md) level 3 with `scripts/share.sh --keep`, steps 1–7, against contracts/screens.md. Note anything off as a new task.
- [ ] T059 Walk quickstart.md level 4, a real-device evening with a host and three guests, and record the outcome against SC-001 – SC-008 in `specs/004-match-end-sharing-prompt/validation.md`, in the shape of `specs/003-apple-watch-se-support/validation.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: needs Setup, and blocks every story.
- **US1 (Phase 3)** and **US2 (Phase 4)**: need Foundational.
  - US2's `keepIsToldToGuests` (T020) needs US1's T014, and its stop-replaces-question test uses today's Stop.
  - T027 needs T026: the watch's Leave reaches the host through the goodbye that `letGo()` sends.
  - US2's waiting state for a guest who chose Stay is drawn by US4's T049 and T052. Until US4 lands, a guest who stays sees Home as it does today, and US2's tests check the engine state (`isWaiting`).
  - Otherwise they are independent.
- **US3 (Phase 5)**: needs Foundational. T037's widened `onStoppedByHost` and T015's `stop(reason:)` meet in `SharedSession`, so do T015 first if US1 has not landed.
- **US4 (Phase 6)**: needs Foundational. It does not need US3, but the guest idle leave (T038) covers waiting guests from either story.
- **Polish (Phase 7)**: after the stories that are shipping.

### Within Each User Story

- Tests first, and they must fail for the stated reason.
- `RekkertCore` before `RekkertSync`, and `RekkertSync` before `Shared/` and the views.
- The story's test run (T019, T032, T045, T053) closes it.

### Parallel Opportunities

- **Phase 2**: T002, T004, T005, T006 and T007 touch different files and run in parallel. T003 follows T002. T008–T011 follow T003–T007, with T010 after T009.
- **The views** call only `SharedSession.answer` and `WatchStandIn.answer` for answers, so T017, T018, T030 and T031 need T010.
- **Phase 3 onwards**: within US2, T021 runs beside T020.
- **Phase 5**: T033, T034 and T035 are three new files and run in parallel. T044 is wording only, and can land any time after Phase 2.
- **Across stories**: US1 and US3 touch different views (`RootView`/`WatchResultView` against `HomeView`/`WatchRootView` idle), but both change `MatchStore.swift` and `SharedSession.swift`. Run them one after the other unless the store edits are coordinated.
- **Phase 7**: T054 and T055 run in parallel.

### Parallel Example: Foundational

```text
Task: "T002 Write CoreTests/BetweenMatchesTests.swift"
Task: "T004 keptSharingAfter in RekkertCore/Sync/ShareAccess.swift"
Task: "T005 Wire and SharingSignal additions in RekkertCore/Sync/Wire.swift"
Task: "T006 MatchMoment.nextFromHost in RekkertCore/Sync/MatchMoment.swift"
Task: "T007 LinkEvent kinds in RekkertCore/Sync/LinkRecord.swift"
```

### Parallel Example: User Story 3 tests

```text
Task: "T033 SyncTests/HostWithNoMatchTests.swift"
Task: "T034 SyncTests/StopBetweenMatchesTests.swift"
Task: "T035 SyncTests/IdleStopTests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1, then User Story 2)

1. Phase 1 and Phase 2.
2. Phase 3 (US1). The host is asked, and Stop is one tap. Ship-worthy on its own: it ends
   the evening cleanly.
3. Phase 4 (US2). This removes the reported surprise, the next match arriving unannounced.
   US1 and US2 together are the fix the user asked for first.

### Incremental Delivery

1. US1 → test → demo.
2. US2 → test → demo. This is the reported confusion, fixed.
3. US3 → test → demo. Sharing before the first match, Stop between matches that works, and
   the 30-minute stop.
4. US4 → test → demo. Waiting and leaving are visible on both devices.
5. Polish, then the real-device evening (T059).

### Notes

- Commit after each task or logical group with jj, in conventional style (`feat(sharing): …`,
  `test(sharing): …`, `fix(sharing): …` for R-3), with no AI attribution trailers.
- The reducer, the event format and the merge must not change. If a task seems to need
  that, stop and raise it against Principle II.
