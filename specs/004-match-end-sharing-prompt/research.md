# Research: Asking at the End of a Shared Match, and Sharing Between Matches

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

Line references are to the tree at `9d930e27` (this feature's spec commit). They abbreviate:

- **MS**: `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift`
- **SS**: `Packages/RekkertKit/Sources/RekkertSync/SharedSession.swift`
- **W**: `Packages/RekkertKit/Sources/RekkertCore/Sync/Wire.swift`
- **FO**: `Packages/RekkertKit/Sources/RekkertSync/FanOutTransport.swift`
- **AM**: `Shared/AppModel.swift`

## What the code does today

Each finding below was read in the code, not inferred from behaviour.

### R-1. Sharing outlives the match, and nobody is asked

`concludeIfFinished` (MS:945-985) runs on every device that sees the match end, host and
guest alike. Each one:

1. files the match, if it is kept;
2. sets `lastResult`;
3. sends a farewell snapshot;
4. retires the session;
5. starts an empty `MatchLog` with a fresh random id.

The host stays `.host`, the guest stays `.guest`, and the links stay up. MS:886-888 says so
in as many words: "the host's next match would land here". Nothing raises a question
anywhere.

### R-2. The host's next match lands silently, and only sometimes promptly

A guest with an empty log takes any snapshot it is handed at MS:1853-1876. Three things
then happen:

- `refresh()` clears the guest's `lastResult` (MS:2396-2399), so the result screen
  disappears from under it.
- `announceBegan()` fires `onMatch(.began)` (MS:2411-2414).
- Nothing else: there is no dialog and no notification.

The match reaches a guest by one of three paths:

- the published snapshot over the local network (MS:2350);
- `.events` on an unknown session, followed by `requestSnapshot` and the host's live
  offer (MS:1398, 1599, 1794-1802);
- the host's answer to the guest's next hello (MS:1584).

A guest on Bluetooth, or a watch without Rekkert in front, gets it on its next exchange.
That is why the match seems to arrive "sometimes".

### R-3. Stop sharing between matches does not reach the guests (defect)

`sayStoppedSharing` names the host's current log (MS:1506-1520). A guest acts on it only if
`sessionID == log.sessionID, !log.isEmpty, !canEndSession` (MS:1767).

Between matches, both logs are empty, and each has its own random id. Every waiting guest
therefore ignores the notice. It sees the host go out of reach, and then the "Still looking
for the shared match" alert (`hasLostTheMatch`, SS:613).

This breaks FR-017, FR-026 and User Story 3 scenario 4 as they stand.

### R-4. Hosting requires a match on

- **The phone's own start.** `SharedSession.host()` guards on `store.state != nil` (SS:267).
- **A start from the watch.** `startHostingFromTheWatch` guards the same way (SS:769), and
  otherwise answers `.nothingToShare` (WatchStandIn:236-241, WatchCodeView:35).
- **The menus.** The watch's Share sits in the match menu (WatchMenuView:290-304). The
  phone's sits in `SharingMenuItems` (MatchOptionsMenu:124-168). Both are match screens only.

Two places already work with no match on:

- `MatchStore.startSharing()` checks only `role != .guest` (MS:455-472).
- `restore()` brings hosting back with no match on (SS:295-317).

An existing test pins the old rule: `sharingStartsFromTheWristOnlyWithAMatchOn`
(HostWatchSharingTests:41).

### R-5. Joining with no match on never completes

A joining guest offered an empty log keeps looking. MS:1794-1802 says "that nothing is the
host between matches", and only the host's first match completes the join, through the
join branch at MS:1803. Until then:

- the guest's role is `.solo`, with `isJoining`;
- Home says nothing about whose sharing it is on;
- `.access`, which carries the host's name, is refused while joining (`takesAccess`,
  MS:574-577).

`SharedSession` does know the code was right. `noteProven()` (SS:320-326) runs when the join
link is proven, and that is what the join sheet's "Joined. Waiting for the match…" reads.

### R-6. Leaving between matches is hidden on the phone and missing on the watch

- On the phone, a guest leaves from a menu behind the sharing glyph in Home's toolbar
  (ConnectionBadge:55-70).
- On the watch, the idle screen (WatchRootView:254-320) has Join a match and Join again,
  but no Leave.

### R-7. There is no idle time

- `KeptCode` lasts 12 hours from `startedAt` (KeptCode.swift:13-26) and is never refreshed.
- `resume()` puts hosting back every time the app comes to the front (SS:368-379, AM:715),
  with no check on time.
- Neither "when the last match ended" nor "since when nothing has been on" exists.

### R-8. The host's word to guests travels in the access table

`ShareAccessTable` holds the host's name (ShareAccess.swift:51), an `id`, a `revision`, and
`supersedes` (101-104). It reaches guests three ways:

- on `.access`;
- inside the snapshot the host answers a hello with;
- with the published snapshot.

A guest takes it at MS:559, 1828 and 1926. A guest's phone passes it on to its own watch,
and it is persisted in `ActiveSession`.

### R-9. How older builds meet new messages

- **An unknown `Wire` case**, including any message carrying an unknown `SharingSignal`, does
  not decode. The receiver answers with a hello, and the link is kept (FO:43-46,
  MS:1539-1543).
- **A new case must be added to two exhaustive switches**: `Scope.sharedSession`
  (FO:49-63) and `keepsOverDelay` (FO:256-264).
- **The precedent for growing a message** is a new optional associated value on an existing
  case (W:189, 196, 209). Older decoders ignore the key, and newer ones read nil when it is
  absent.
- **There is no wire version.**

### R-10. On a watch, the phone's role is what counts

A watch on a shared match is `.solo` itself. Whether it is on the host's side or a guest's
comes from `pairedRole` (MS:104). The watch concludes the same match as its phone, but does
not file History (`keepsHistory` is false), and then shows `WatchResultView`. A watch that
stands in for its phone (WatchStandIn:468-474) has a radio link of its own to the host.

### R-11. Notifications are already wired

- **Posting.** `beckonTheWatch()` (AM:973-991) posts category `rekkert.followMatch`,
  identifier `follow-<session>`, on an immediate trigger.
- **Permission.** It asks once, through `RoundAlarmFollower.askToNotify()`.
- **Withdrawal.** A 2-second poll withdraws the notification once the watch is reachable
  (AM:995-1000).
- **A tap on the watch.** It runs `standIn.followThePhone()` (RekkertWatchApp.swift:41-47).
- **The phone itself** has no `UNUserNotificationCenterDelegate`.

### R-12. The tests can already play a whole evening

`CourtHarness` puts a host and N guests, each a phone with an optional watch, on
`SimulatedRadio`, with an injected `TestClock`. Its helpers cover what an evening needs:

- `startMatch`, `share`, `joinAll` and `score`;
- `run(for:)` and `until(within:)`;
- `endApp` and `relaunch`.

`SharedSession` takes its `sleep` and `now` by injection (SS:150-170), and so does
`MatchStore` (MS:159, 191). Existing suites that touch this work:

- `HostWatchSharingTests.betweenMatchesTheCodeStaysShared` (:96);
- `BetweenMatchesTests` (SharedSessionTests:305);
- `FinishTests`, `GuestWristTests` and `SharingSignalTests`.

There are no UI test targets. Strings are English literals in the views.

### R-13. The host never drops a guest who leaves

`Participants.remove` (ParticipantState.swift:88) has no caller. A guest's Leave cuts its
links and sends nothing to the host: `.left` goes only between a phone and its own watch
(FO:49-63). The host's list therefore shows a leaver as out of reach after 15 s, and never
as gone.

### R-14. A join is "proven" before the host's match arrives

`noteProven()` runs as soon as a link is up: on `.joined(count)` from the local network
(SS:655-665) and on Bluetooth reachability (SS:204). The host's match, if it has one, comes
after. A joining guest's hello is answered by `requestSnapshot` with the host's whole log,
an empty one included (MS:2268-2270), so a joining guest does hear when the host has nothing
on: an empty snapshot from a link that is not its pair's.

### R-15. A Leave from the watch does not reach the phone between matches

A watch's Leave tells its phone with `.left(sessionID:)`. The phone acts on it only when
`sessionID == log.sessionID, !log.isEmpty` (MS:1673-1677). Between matches, the phone and the
watch each hold an empty log with an id of its own, so the phone ignores it and stays on the
host's sharing. This is R-3's mismatch again, on the pair's own message.

A guest's Leave also cuts its links before the store hears of it: `leave()` and a guest's
`stop()` call `cutLinks()` before `store.leaveSharedSession()` (SS:439-449, 514-519). A Leave
that starts on the other half arrives through `onLeft`, which runs `letGo()` (SS:180), after
the store has already dropped the match. Anything a guest wants to say to its host on the way
out has to be said by `SharedSession`, before it cuts.

## Decisions

### D-1. One between-matches state, kept in RekkertCore

**Decision**: a pure value type, `BetweenMatches`, in `RekkertCore/Sync`. It holds:

- since when nothing has been on (`idleSince`);
- the end-of-match question still open (`ask`);
- the new-match notice still open (`newMatch`).

Its transitions are plain functions of events and time. `MatchStore` owns one, changes it
where the events happen, and persists it in `ActiveSession`.

**Rationale**:

- Principle I: the views only render it.
- It survives a relaunch, so a match already answered for is not asked about again.
- Every rule is testable on macOS.

**Alternatives considered**:

- View state: lost on relaunch, and it puts rules in views.
- Keeping it in `SharedSession`: the conclusion, and the next match's arrival, both happen
  in `MatchStore`. The question would be raised a hop away from the event that causes it,
  and would have to be replayed into the store's persistence anyway.

### D-2. Who is asked what

**Decision**: the side is the device's own role on a phone, and `pairedRole` on a watch:

| Side | Question |
|---|---|
| Host | Keep or stop, with the number of guests on (`participantStates().count` on the host's phone; the watch reads it from `HostingStatus`) |
| Guest | Stay or leave, with the host's name and whether the host has said Keep |

A device on neither side is not asked.

The question is raised in `concludeIfFinished`, for kept matches and called-off ones alike,
once per ended session id. A guest that hears of the ending late, through the host's retired
farewell (MS:1607-1626), concludes through the same function and is asked then. Rounds of a
tournament never conclude a session, so they never ask.

**Rationale**: one rule for both devices of a pair, keyed on the session that ended.

### D-3. Where the questions appear

**Decision**:

- **On the phone**: an alert from `RootView`, over `MatchResultView`, or over Home when a
  called-off match has no result. Its two buttons are the two answers. The result stays
  visible around it.
- **On the watch**: the two answers take the place of **Done** on `WatchResultView`, because
  an alert there would cover the whole result. With no result, a full-screen confirmation
  on the idle screen asks instead.

**Rationale**: the user asked for a popup, and FR-002 asks that the result stay readable.
On the phone an alert is both. On the watch it cannot be both, so the buttons go where Done
was.

**Alternatives considered**:

- An inline card on the phone: not the popup asked for.
- A sheet: hides the result.

### D-4. Answering once for the pair

**Decision**: a pair-only `SharingSignal.answered(BetweenMatchesAnswer)`, holding the session
and the choice. It is sent with `sendDurably`, and a device closes its own question or
notice when it hears an answer for the same session.

What each choice does:

| Choice | Effect |
|---|---|
| Stop sharing | On the watch, the existing `.stopHosting`, including its "Can't reach your iPhone" (FR-007) |
| Leave | The existing leave path; a watch's Leave already takes its phone (spec 001 FR-022) |
| Keep sharing | Nothing but the signal; for the guests, see D-5 |
| Stay, OK | Nothing but the signal |

"Leave wins" (FR-011) falls out of this: Stay changes nothing, so a Leave heard after a
Stay still leaves.

**Views never carry out a choice themselves.** Each device has one entry point:

- on the phone, `SharedSession.answer(_:)`;
- on the watch, `WatchStandIn.answer(_:)`.

Each first records the answer and tells the other device (`MatchStore.answer`), and only then
stops sharing or leaves. Done the other way round, leaving would clear the question before
the answer was recorded or sent. Views forward one call (Principle I).

A Leave carried out on the watch reaches the phone through `.left`, which D-17 makes work
with no match on. `.answered(.leave)` only closes the phone's question.

**Alternatives considered**: putting the answer in the application context. It is
overwritten by the next snapshot, and it is not heard live.

### D-5. Telling guests the host keeps sharing

**Decision**: `ShareAccessTable` gains an optional `keptSharingAfter: UUID?`, the session
that just ended. It is set, with a revision bump, when the host answers Keep, and sent the
way the table already goes.

A guest's question reads it. If it arrives while the question is open, the question's text
changes to "Ada is keeping it shared".

**Rationale**: the table already reaches every guest and its watch, survives reconnects and
relaunches, and is ordered by revision (R-8). Older builds ignore the new key.

**Alternatives considered**: a new `Wire.sharingContinues` case. It would need the two
exhaustive switches (R-9), a forwarding path to the watch, and replay on reconnect, all of
which the table already has.

### D-6. The next match: adopted at once, and announced

**Decision**:

- **It is adopted at once, as today** (MS:1853), so every device stays in step and points
  others score are not held back (Principle II, FR-014).
- **It carries a notice.** When it is the host's next match, the store also opens a
  `NewMatchNotice` with the session, the host's name and the time it arrived. The test is
  the existing one at MS:1874, widened to a watch standing in: `pairedRole == .guest` and
  not from the pair.
- **Scoring waits on it.** While the notice is open, `canScore` and `canRunRounds` are false
  on that device (FR-013).
- **The answers.** OK closes the notice; Leave is the existing leave.
- **The watch is told.** The phone sends the notice to its watch with
  `SharingSignal.newMatch(NewMatchNotice)`, durably, and the answer travels as in D-4.
- **An open question closes.** A still-open end-of-match question is closed and recorded as
  unanswered (FR-012).

**Rationale**: the dialog changes what this device lets its wearer do, not what the match
is.

**Alternatives considered**: holding the match unadopted until OK. Points scored on other
devices would have to be kept aside, a watch standing in could not follow, and FR-014's
times would depend on a tap. It also adds a convergence case that does not exist today.

### D-7. Stop reaches guests between matches, and says why

**Decision**: a guest acts on `.sharingStopped` also when all of these hold:

- its role is `.guest`;
- its log is empty;
- it is not joining;
- the notice came on a link that is not its pair's.

It then acts whatever session id the notice names. A guest's links reach only its own host;
codes keep two courts apart (spec 001 FR-029).

`.sharingStopped` gains an optional `reason: SharingStopReason?`, which is `.host` or
`.idle`. `SharingSignal.hostStoppedSharing` gains the same, so the watch can say it.

A failing test first: R-3 as it stands today.

**Rationale**: this fixes the defect for older hosts too. Their between-matches Stop now
reaches a new guest.

### D-8. Sharing with no match on

**Decision**:

- **The guards go.** Drop the `state != nil` guards in `host()` and
  `startHostingFromTheWatch`; keep `role != .guest`. `canShare` becomes `role != .guest`.
- **The phone's Home** gains a sharing section in "Play together":
  - not sharing: **Share** and **Join a match**;
  - hosting: the code, the number on, **Show the code** and **Stop sharing**;
  - a guest: "On Ada's sharing · waiting for the next match", with **Leave**, and
    **Join again** while a kept code allows it.
- **The watch's idle screen** gains the same card at its top. `HostingStatus` already
  carries the code and the participants to the host's watch.
- **The wording changes** to FR-022's. See [contracts/screens.md](contracts/screens.md).

`SharingBadge` keeps its glyph and its states during a match. Its between-matches menu goes:
the section replaces it.

### D-9. A join with no match on completes, into waiting

**Decision**: the join completes into waiting when the host says it has nothing on. That is
when a joining store with an empty log is handed an empty snapshot on a link that is not its
pair's: the `incoming.isEmpty` branch of `handle(.snapshot)` (MS:1794-1802). There the store
calls a new private `MatchStore.joinedBetweenMatches(access:)`, which:

1. sets the role to `.guest`, and clears `isJoining` and `joiningForThePair` as
   `cancelJoining()` does;
2. takes the access list that came with the snapshot, which `takesAccess` refused while
   joining, so the host's name arrives with it;
3. persists, and starts the idle clock.

If the host has a match on, its snapshot is not empty, and today's join branch (MS:1803)
adopts it as before, with no new-match notice. A guest that joins with a match of its own
still on keeps today's behaviour: it waits in the join sheet, and its match is filed when the
host's arrives.

**Rationale**: an empty answer from the host is the host saying it has nothing on, and only a
link sealed with the right code can deliver it. Waiting for a match is what leaves the guest
looking at nothing.

**Alternatives considered**: completing the join in `noteProven()`. It runs as soon as a link
is up, before the host's match arrives (R-14). A guest joining mid-match would become a
waiting guest first, and would then take the host's current match for its next one, with a
popup and without the join branch's work.

### D-10. Sharing stops after 30 minutes with no match on

**Decision**:

- **The limit.** `BetweenMatches.idleLimit` is 30 minutes. `idleSince` is set when sharing
  starts or a join completes with no match on, and when a match concludes. It is cleared
  when a match begins.
- **Checked twice.**
  - (a) a `SharedSession` task on the injected `sleep`, every 30 s, while hosting or waiting;
  - (b) at the top of `restore()` and `resume()`, before anything is put back up. An app
    that was suspended past the limit is caught there.
- **On the host**: `stop(reason: .idle)`. Guests in reach are told, and `stoppedForIdle` is
  set, so the phone and the watch tell the host at the next look.
- **On a guest**: it leaves by itself through the stopped-by-host path, with reason `.idle`
  and no host needed. It keeps History and forgets the code.
- **Persisted** in `ActiveSession` with the rest of `BetweenMatches`.

**Rationale**: "no match on" is the store's to know. The check-on-resume closes the morning
case in the spec's edge cases, where the app had no running time to notice in.

**Alternatives considered**:

- Shortening `KeptCode`'s 12 hours: the clock has to pause during matches, and the code's
  lifetime cannot.
- Only a timer: a suspended app never runs it.

### D-11. A notification when the next match lands out of sight

**Decision**: a guest's phone posts when it adopts the host's next match and neither of
these holds:

- the phone's app is active (scene phase);
- the watch is reachable (`isPairReachable`).

It reuses category `rekkert.followMatch` and the permission path of R-11, with identifier
`next-<session>`, the title "Ada started a new match" and the body "Tap to open it". It is
withdrawn when the notice is answered on either device. A tap on the watch goes the existing
`followThePhone` way, and the watch then shows the notice. If notifications are not allowed,
nothing more is needed: the notice is persisted state, and shows at the next open.

**Rationale**: FR-027 of this spec is spec 001's FR-027 for the next match. The posting,
the permission and the tap handling already exist.

### D-12. The sharing record learns the new moments

**Decision**: new `LinkEvent` cases, recorded on the `radio` link and tagged with the
session:

- `endOfMatchAsked`;
- `endOfMatchAnswered(choice)`;
- `endOfMatchUnanswered`;
- `newMatchShown`;
- `newMatchAnswered(choice)`;
- `idleStop`.

Each gets a `text` and a parse in `init(text:)`. They carry no names, so the record's
existing rule holds (Principle V). See [contracts/sharing-record.md](contracts/sharing-record.md).

### D-13. Older builds

| Older device | What happens |
|---|---|
| Guest | Ignores `keptSharingAfter` and the `reason` key, and behaves as today (FR-025) |
| Host | Never sets `keptSharingAfter`. A new guest's question just asks stay or leave. Its between-matches Stop now reaches new guests (D-7). It ignores a guest's goodbye, so it shows a leaver as out of reach rather than gone (D-16) |
| Watch or phone of the same pair | Fails to decode `.answered` and `.newMatch`, and answers with a hello (R-9). The other half asks on its own, which is harmless. Watch and phone ship together, so this lasts only until both update |

### D-14. Tests first, on the harness that exists

**Decision**:

- `BetweenMatches` rules go in `RekkertCoreTests`. They are pure: who is asked, the idle
  expiry, Leave winning, and the record round trip.
- Behaviour goes in `RekkertSyncTests`, on `CourtHarness` with `TestClock`. Each of R-2's
  silent arrival, R-3 and R-5 is a failing test first.
- `sharingStartsFromTheWristOnlyWithAMatchOn` is rewritten to the new rule, since the spec
  reverses it.

The UI has no test target. It is checked against [quickstart.md](quickstart.md) and
[contracts/screens.md](contracts/screens.md) on simulators and devices.

### D-15. Starting a match while sharing

**Decision**:

- **FR-020, a host.** `NewSessionView`, the presets on Home and the watch's start screen
  show "Shared with N" under the start whenever this device's side is hosting. Nothing
  offers to start unshared, as clarified.
- **FR-021, a guest.** A new `MatchStore.startingOwnMatchLeavesSharing` is true on a phone
  whose role is `.guest`. On a watch it is the existing `startingOwnMatchTakesPhoneOff`. Home's
  presets and `NewSessionView` ask once through a confirmation when it is true, as the watch
  already does with `asksBeforeTakingThePhoneOff`.
- **Both apply to History's Resume** too (HistoryDetailView.swift:138, `model.resume(record)`),
  which starts a match like any other.

### D-16. A leaving guest says goodbye

**Decision**: `GuestCard` gains an optional `leaving: Bool?`.

- **The guest.** `SharedSession` says it, because the store cannot: by the time the store
  hears of a Leave, the links are already cut or about to be (R-15).
  - A new `MatchStore.sayLeaving(within:) -> Task`, shaped like `sayStoppedSharing`, sends
    `guestCard(GuestCard(device:name:pairedTo:leaving: true))` live on each host link and
    finishes once each has answered, or after 2 s.
  - `SharedSession` calls it at the top of a guest's `stop()`, of `leave()` and of `letGo()`,
    and cuts the links once it finishes, as the host's `stop()` already does with its
    farewell. The store's own leaving runs at once, so nothing on screen waits.
  - `letGo()` is also how a guest steps off by starting a match of its own (MS:909), so that
    goodbye comes for free.
  - A watch standing in sends its own card, with `pairedTo`.
- **The host.** It calls `participants.remove(card.device)`, which also drops the paired
  watch, then `onParticipantsChanged`. The guest is gone from the list on the next read
  (FR-009).

**Rationale**: the guest card is already the message by which a guest names itself to the
host, and an optional key is the established way to grow a message (R-9). An older host
ignores the key, and the leaver shows as out of reach after 15 s, as today.

**Alternatives considered**:

- Sending `.left` on host links. It is a pair-only message (FO:49-63), and widening its scope
  would change what every build does with a message it already knows.
- Dropping a participant when its link closes. A link also closes when a phone is pocketed or
  out of range, and the guest is still on.
- Sending the card from `leaveSharedSession()`. It is synchronous, and every caller has
  already cut, or is about to cut, the links it would go out on (R-15).

### D-17. A Leave from the watch reaches the phone between matches

**Decision**: the phone's `.left` handler (MS:1673) also acts when all of these hold:

- the message came from its own watch;
- the phone's role is `.guest`;
- its log is empty;

whatever session the message names. It then takes the same steps as its own Leave, minus
telling the watch, which already knows: `dropSession()`, then `onLeft?()`. That sends
`SharedSession.letGo()` the goodbye of D-16, and cuts the links.

**Rationale**: it is D-7's fix for the pair's own message. The watch has no other way to
take its phone off a sharing with nothing on, and FR-009, FR-011 and FR-019 all need it.
There is no loop: the phone's `dropSession()` tells the watch nothing new, and the watch's
side is already `.solo` once its phone's role arrives.

**Alternatives considered**: carrying out `.answered(.leave)` on the phone. It covers only an
end-of-match answer, and not the watch's Leave from its start screen (FR-019), which answers
no question.
