# Feature Specification: Reliable Session Sharing, and Sharing from the Wrist

**Feature Branch**: `001-fix-session-sharing`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "Yesterday during a padel session we got into a state where my phone and watch (host) worked as expected, but others did not. We need to look into the session sharing again and find a solution for all these problems. There also was a problem where one of the users joined on the phone, but his watch did not (Can not confirm that it was not apple watch -> phone problems rather than rekkert). We were not on the same network (No wifi at the club) so this was the bluetooth path. I think this needs to be fixed in two ways. 1. track down the bug so it doesnt happen again. 2. Make it easier to share the code on the watch for the host. And make it easy to leave and join on the watches of the joiners."

## Clarifications

### Session 2026-10-27

- Q: If iOS ends the host's app in the background and it is reopened mid-match, should the
  match come back on the same code, so guests reconnect by themselves? → A: Yes. The code is
  kept on the host's phone until the host stops sharing, for at most 12 hours; a host whose
  app runs again in that time comes back on it, and guests get back on by themselves.
- Q: If the host's phone leaves the match for good mid-match, what should the guests'
  devices do? → A: Guests keep scoring on their own devices and are told the host is out of
  reach; they are not kept in step with each other meanwhile, and everything merges when
  the host is back. Guests relaying to each other, or a guest taking over as host, is out
  of scope.
- Q: How should the no-Wi-Fi requirements be proven, given the simulator can't run the
  phone-to-phone radio link? → A: Automated tests that simulate the radio link cover every
  requirement and run on every push; one real-device test of the incident setup (host and
  three guests) is required before release; the seven-guest case is shown by the automated
  tests and checked on real devices at a club night when one comes up.
- Q: How much extra battery may sharing use on a phone or watch over an evening? → A: No
  limit. Battery use is measured and reported, but does not hold the release.
- Q: Where should someone read and share the record of what happened to the links? → A: On
  the phone only, with its watch's record merged in once the two are back in touch. The
  watch shows its link state live, but not the record.
- Q: Should each guest's phone and watch also keep the code, so a guest whose app was ended,
  or who left, gets back on without typing? → A: Yes, under the same rules as the host: on
  that device only, never in a backup, at most 12 hours, forgotten on joining another match.
- Q: A phone cannot wake its watch app. When a guest joins on the phone and their watch is
  not showing Rekkert, what should happen? → A: The phone posts a notification that shows
  on the watch; one tap there opens Rekkert on the match. Otherwise the match appears the
  next time Rekkert is opened on the watch.

## User Scenarios & Testing *(mandatory)*

### The incident this starts from

On 2026-10-26, at a club with no Wi-Fi, a padel session was shared from the host's phone. The
host's phone and watch kept score as expected throughout. The other players' devices did not
stay on the match with it; what each of them showed is not known in detail, and different
players may have seen different things. Separately, one player joined on their phone but
their watch never showed the match; it is not known whether that was the link between that
watch and its own phone or Rekkert. With no shared network, every guest depended on the
direct phone-to-phone link, the only one that keeps working with phones locked in bags.

### User Story 1 - Every guest stays on the host's match without Wi-Fi (Priority: P1)

A host shares a match at a court with no Wi-Fi. The other players join on their phones, with
their watches on. For the whole match, with the phones locked in bags, every phone and every
watch shows the same score as the host's, whichever device a point is tapped on. A player
who wanders out of range, or whose phone drops off for a while, comes back by themselves
when back in range, without typing anything, and nothing they scored while away is lost.

**Why this priority**: this is the failure that happened. A shared match where only the host
is right is worse than no sharing at all, because the guests believe a score that is wrong.

**Independent Test**: On every push, automated tests that simulate the radio link play the
incident's setup and the two-court setup through drops, delays, suspended phones and an app
ended and run again. Before release, four iPhones, each with its Apple Watch, Wi-Fi off on
all of them: one hosts, three join, a full set is played with the phones locked in bags and
points tapped on every watch, and all eight devices are compared at every change of ends.

**Acceptance Scenarios**:

1. **Given** a host sharing a match and no shared Wi-Fi, **When** three guests join with
   their phones, **Then** the host lists all three as on the match and each guest's phone
   and watch shows the host's score.
2. **Given** all four players on the match with phones locked in bags, **When** a point is
   tapped on any watch, **Then** every phone and watch on the match shows it within the
   times in FR-002.
3. **Given** a guest whose phone has been out of range for several minutes while the others
   kept scoring, **When** it comes back in range, **Then** it catches up without anyone
   touching it, and any points it scored while away count on every device.
4. **Given** a guest that cannot get onto the match or stay on it, **When** that happens,
   **Then** the guest's phone and watch say so plainly and show the way back, rather than
   showing an old score as though it were current.
5. **Given** the conditions of the incident, **When** they are reproduced, **Then** every
   guest stays in step, and an automated check that failed on the old behaviour now passes.
6. **Given** an americano over two neighbouring courts with no Wi-Fi, **When** the host and
   seven guests are on it with phones in bags, **Then** every phone and watch shows the
   host's score.

---

### User Story 2 - See who is on, and why not (Priority: P2)

When sharing goes wrong, the people at the court can tell what is wrong: the host sees which
guests are in step and which are not, every device shows whether it can reach its own
phone or watch and whether it can reach the match, and afterwards each phone can show a
record of what happened to its links and its watch's, which the owner can choose to send to
the developer.

**Why this priority**: the incident could not be explained on the day, and the watch
failure still cannot be pinned on Rekkert or on the watch's link to its phone. Without this,
the next field failure will be just as hard to fix.

**Independent Test**: With the setup of User Story 1, walk one guest out of range, switch one
guest's Bluetooth off, and force-quit a third guest's app. Check that the host's list shows
each change, that each affected device says what is wrong, and that each phone's record,
with its watch's merged in, shows the events in order.

**Acceptance Scenarios**:

1. **Given** a shared match, **When** a guest drops out of reach, **Then** the host's list
   shows that guest as out of reach within 15 seconds, and back in step when it returns.
2. **Given** a guest's watch that cannot reach its own phone, **When** the guest looks at
   the watch, **Then** it says that the phone is out of reach, separately from whether the
   match is.
3. **Given** a shared match that has ended, **When** the owner opens the sharing record on
   the phone, **Then** it lists the phone's and its watch's joins, drops, reconnects,
   refusals and catch-ups with times, and offers to share the record, sending nothing
   unless the owner chooses to.

---

### User Story 3 - A guest's watch is on whatever its phone is on (Priority: P2)

A guest joins on their phone. Their watch shows the match without the guest touching it.
If the watch was showing a match of its own, the shared match takes over and the watch's
own is kept in History. If the watch cannot get the match, it says why and offers one tap to
get onto the match its phone is on, with no code to type.

**Why this priority**: this is the second failure seen, and the watch is where players
score from when the phones are in bags.

**Independent Test**: A guest joins on the phone with the watch app open, then with it
closed and opened later, then with a match of its own already running on the watch. In each
case the watch ends up on the shared match.

**Acceptance Scenarios**:

1. **Given** a guest whose watch has Rekkert in front, **When** they join on the phone,
   **Then** the watch shows the shared match within 10 seconds.
2. **Given** a guest whose watch did not have Rekkert in front when they joined, **When**
   they open it, **Then** it shows the shared match.
3. **Given** a guest's watch with a match of its own running, **When** the guest joins on
   the phone, **Then** the watch shows the shared match and its own match is filed in
   History, not lost.
4. **Given** a guest's watch that is not on the match its phone is on, **When** the guest
   opens the watch, **Then** it says why and offers a single tap to get on it.
5. **Given** a guest whose watch does not have Rekkert in front, **When** they join on the phone,
   **Then** a notification appears on the watch, and tapping it opens Rekkert on the
   shared match.

---

### User Story 4 - The host runs sharing from the wrist (Priority: P3)

The host shares the match, reads the code out, keeps an eye on who is on, and stops sharing,
all from the watch, without taking the phone out of the bag. The code is a glance away from
the match on the watch, in digits large enough to read out, and it can also be held up for a
guest's phone camera to scan.

**Why this priority**: it removes the main reason the host reaches for the phone at the
start of a session, but the match can be shared without it.

**Independent Test**: With the host's phone in a bag, the host starts sharing on the watch, a
guest joins using only what the host's watch shows, the host sees the guest arrive on the
watch, and then stops sharing from the watch.

**Acceptance Scenarios**:

1. **Given** a host with a match on and the phone in a bag, **When** the host starts sharing
   on the watch, **Then** the watch shows the code and guests can join with it.
2. **Given** a host whose phone is sharing, **When** the host opens the code on the watch,
   **Then** it shows the same six digits as the phone, in at most two taps from the
   watch's scoreboard.
3. **Given** the code on the host's watch, **When** a guest points their phone camera at it,
   **Then** the guest's phone offers to join that match.
4. **Given** a host who stopped sharing and then shared again on a new code, **When** the
   host looks at the code on the watch, **Then** it shows the new code.
5. **Given** a shared match, **When** a guest joins or drops out of reach, **Then** the
   host's watch shows it within 15 seconds.
6. **Given** a shared match, **When** the host stops sharing on the watch and confirms,
   **Then** the guests are told the match is no longer shared and each keeps its copy in
   History, and the host's match carries on.

---

### User Story 5 - Guests join and leave from the wrist (Priority: P3)

A guest whose phone stays in the bag joins, leaves, and joins again from the watch alone.
Leaving is easy to find, asks once, and takes that guest's phone off the match too. Joining
again while the match is still being shared does not need the code typed again.

**Why this priority**: it finishes making the watch enough for a guest, but every part of it
can already be done from the phone.

**Independent Test**: A guest joins from the watch with the phone in a bag, leaves from the
watch, and joins again from the watch; the phone follows each step.

**Acceptance Scenarios**:

1. **Given** a guest's watch on its start screen, **When** the guest types the code,
   **Then** the watch and the guest's phone are on the match.
2. **Given** a guest on a shared match, **When** they choose Leave on the watch and confirm,
   **Then** both the watch and the guest's phone leave the match, and the host's match
   carries on unchanged.
3. **Given** a guest who left a match that is still being shared, **When** they choose to
   join again on the watch, **Then** they are back on it without typing the code.

---

### Edge Cases

- A guest's phone app is ended by the system while in a bag. It is brought back by the
  radio or by its watch; until then, the guest's watch carries on with the match on its own
  if it can reach the host, and otherwise says that the phone needs opening (FR-009).
- The host's phone app is ended in the background and runs again mid-match. It comes back
  on the same code, and every guest gets back on by themselves (FR-025).
- The host's phone leaves the match for good mid-match: its battery dies, or the host walks
  off with it. Guests keep scoring and are told the host is out of reach; their scores may
  differ from each other until the host is back, when everything merges (FR-026).
- A guest's phone and watch both reach the host directly. The guest is counted once, no
  point is counted twice, and the other guests' links are not crowded out.
- More guests try to join than the match can carry without Wi-Fi. The one who cannot get on
  is told so, and the guests already on are unaffected (FR-001).
- Two courts nearby are each sharing a match. Every guest lands on the match whose code
  they typed (FR-029).
- A guest types a wrong code on the watch. The watch says no match was found on that code
  nearby, and nothing changes on the guest's phone.
- A guest leaves on the phone. The watch leaves with it.
- Guests run different versions of the app. An older version may not get the new watch
  features, but must not stop the match for anyone else.
- Bluetooth is off, or the app's permission for it is denied, on a guest's phone. The guest
  is told which, on the phone and on the watch.
- The host starts or stops sharing on the watch while the watch cannot reach the host's
  phone. The watch says so, and nothing changes.

## Requirements *(mandatory)*

### Functional Requirements

**Staying on the match**

- **FR-001**: Without a shared Wi-Fi network, a shared match MUST carry the host and up to
  seven guests, each with a phone and a watch, spread over two neighbouring courts, with
  every device showing the same score while the host can be reached (FR-026 covers the
  rest). A guest counts once whether they are on with their phone, their watch or both; a
  watch that joined without its phone, and a device on an older version, each count as one
  guest. An eighth guest MUST be turned away and told so (FR-008).
- **FR-002**: A point scored on any device on the match MUST show on every other device in
  range within 30 seconds, and within 5 seconds for at least 95% of points, counted from the
  tap that scored it, including with phones locked. A device is in range within about
  30 metres of whatever it reaches the match through: the host, or its own phone. A guest's
  watch counts while Rekkert is in front on it or a workout runs on it (FR-014); otherwise
  the point shows within 10 seconds of Rekkert coming in front.
- **FR-003**: A device that loses the match (out of range, phone locked, radio switched off
  and on, the host's app ended and run again) MUST get back on it by itself within
  30 seconds of the cause going away, without the code being typed again.
- **FR-004**: Getting back on MUST merge what each side scored while apart. Nothing scored
  on any device may be lost or counted twice.
- **FR-005**: One guest joining, dropping off or failing MUST NOT take any other guest off
  the match, nor push any other guest's points past the times in FR-002.
- **FR-006**: What the guests' devices showed on 2026-10-26 is not known, so each way it
  could have failed — never getting on, getting on and then no longer following the host,
  and ending up with a different score — MUST be investigated under the incident's
  conditions. Each failure found MUST be traced to its cause, and an automated check that
  fails on the old behaviour MUST guard against it coming back.
- **FR-007**: A device that has not been in step with the match for 15 seconds MUST NOT
  present its score as current: it MUST say that it is out of reach, since when, and show
  the way back.
- **FR-008**: When a guest cannot get on, the guest's phone and watch MUST say why within
  15 seconds, in plain words: no match found on that code nearby (a wrong code and a host
  out of range look the same to a guest), no room, Bluetooth off, or permission denied.
- **FR-009**: When a guest's phone app has been ended by the system, the guest's watch MUST
  carry on with the match on its own while it can reach the host and a workout runs on it
  or Rekkert is in front on it, and otherwise MUST say that the phone needs opening. Once
  the phone's app runs again, the phone MUST take the match back from the watch by itself,
  with nothing lost, and the sharing record MUST note the hand-back.
- **FR-025**: The code MUST be kept only on devices that have been on the match — the host's
  phone, and each guest's phone and watch — on that device alone and never in a backup, for
  at most 12 hours: on the host until it stops sharing, on a guest until it joins another
  match or is told sharing has stopped. A host whose app is ended and runs again in that
  time MUST come back on the same code, and a guest whose app is ended and runs again MUST
  get back on without the code being typed. An ended app MUST be brought back without
  anyone touching that phone, by the radio or by its own watch, unless its owner swiped it
  away. After 12 hours the code is no longer kept, but sharing carries on for as long as
  the host's app keeps running.
- **FR-026**: While the host is out of reach, every guest MUST be able to keep scoring on
  their own devices and MUST be told within 15 seconds that the host is out of reach, and
  since when. Finishing the match and settling its score stay the host's: no guest may do
  either meanwhile.
  Guests need not stay in step with each other; when the host is back, everything MUST
  merge as in FR-004.
- **FR-028**: When the host stops sharing, every guest in reach MUST be told before the host
  lets go; its copy of the match MUST be kept in its History as it stood, and it MUST
  forget the code.
- **FR-029**: With other matches being shared nearby, a guest MUST only ever join the match
  whose code it was given.

**Seeing what is wrong**

- **FR-010**: The host MUST be able to see each guest on the match and whether that guest
  is in step, catching up, or out of reach, with a change shown within 15 seconds.
- **FR-011**: Every phone and watch MUST show, separately, whether it can reach its own
  paired device and whether it can reach the match.
- **FR-012**: Every phone and watch MUST keep a record of what happened to its link during
  each shared match (joins, drops, reconnects, refusals, catch-ups, with times) for at
  least the last 7 days.
- **FR-013**: The owner MUST be able to read the record on the phone, with its watch's
  record merged in once the two are back in touch, and choose to share it from there. The
  watch need not show the record. The record MUST NOT leave the owner's phone and watch in
  any other way.

**A guest's watch**

- **FR-014**: When a guest's phone is on a shared match, the guest's watch MUST show that
  match whenever Rekkert is in front on the watch with the wrist raised, or a workout is
  running on it, and it can reach the phone or the host: within 10 seconds of the phone
  joining or of Rekkert coming in front, with nothing done on the watch. With the wrist
  down, the 10 seconds count from the next time the wrist is raised to Rekkert.
- **FR-027**: When a guest's phone joins a shared match and cannot reach Rekkert on its
  watch at that moment, the phone MUST post a notification that reaches the watch, and
  tapping it on the watch MUST open Rekkert on that match. If notifications are not
  allowed, the phone MUST say on joining that the watch will show the match once Rekkert is
  opened on it. If the phone is in use, the notification may show there instead; the match
  then reaches the watch once Rekkert is opened on it.
- **FR-015**: If the guest's watch has a match of its own at that moment, the shared match
  MUST take over, and the watch's own match MUST be kept in History.
- **FR-016**: A guest's watch that is not on its phone's match MUST say why — its phone is
  on a match the watch is not on, the watch cannot reach its phone, or its phone cannot
  reach the host — and, where its phone is on the match, MUST offer a single tap to get
  onto it without typing the code.
- **FR-030**: A guest's watch MUST ask once before starting a match of its own while its
  phone is on a shared match, since that takes the phone off the shared match.

**The host's watch**

- **FR-017**: While the host's phone is sharing, the host's watch MUST show the code as six
  digits spanning the width of the screen on every supported watch size, at most two taps
  from the watch's scoreboard.
- **FR-018**: The host's watch MUST also be able to show the code in a form an iPhone camera
  can scan from about 20 centimetres, on the smallest supported watch, to join the match.
- **FR-019**: When the host's phone starts sharing on a new code (after sharing was stopped,
  or after 12 hours), the host's watch MUST show the new code.
- **FR-020**: From the watch, with the phone left in the bag, the host MUST be able to start
  sharing while a match is on, stop sharing after confirming once, and see each guest's
  state as in FR-010. If the watch cannot reach the host's phone, it MUST say so and change
  nothing. These controls MUST appear only on the host's watch. Between the matches of a
  shared evening the code stays shared, as it does today.

**A guest's wrist**

- **FR-021**: A guest MUST be able to join from the watch's start screen and from its match
  menu, whether or not the guest's phone can be reached at that moment. A watch on the
  match without its phone stays on it while a workout runs on it or Rekkert is in front on
  it, and catches up when Rekkert next comes in front. A watch whose phone is hosting MUST
  ask once before joining another match, since that stops the sharing for everyone on it.
- **FR-022**: Leave MUST be at most two taps from the watch's scoreboard, MUST ask once
  before leaving, and MUST take that guest's phone and watch off the match together, leaving
  the host's match unchanged. Leave MUST appear only on a guest's watch.
- **FR-023**: Leaving on the guest's phone MUST take the guest's watch off the match too.
- **FR-024**: For as long as a match is being shared on the same code, a guest who left it
  MUST be able to join it again from the watch without typing the code. If the match is no
  longer being shared, joining again MUST say so in the words of FR-008, and forget the
  code.

**On every watch**

- **FR-031**: The watch's code, guest list and status lines MUST work with VoiceOver, with
  the code read out digit by digit, and with larger text sizes. The six digits beside the
  scannable code are its text alternative.
- **FR-032**: A watch MUST tap the wrist, following its haptics setting, when its wearer has
  been out of reach of the match for 15 seconds, and again when they are back in step.

### Key Entities

- **Shared match**: the host's match that others follow and score. It is known by its code
  for as long as the host's phone keeps sharing it.
- **Host**: the phone that shares the match, and its own watch.
- **Guest**: a player on someone else's shared match, with a phone and usually a watch. A
  guest's phone and watch join and leave together.
- **Code**: six digits that let a guest find and join a shared match. It lasts until the
  host stops sharing, at most 12 hours, including across any app on the match being ended
  and run again. It is kept only on the devices that have been on the match.
- **Link**: a connection between two devices — a phone and its own watch, or a guest and the
  host. Each link is **in step** (heard from within the last 15 seconds, and has every point
  the other end has), **catching up** (heard from within 15 seconds, but missing some), or
  **out of reach** (not heard from for 15 seconds). A guest's state on the host is the state
  of its link.
- **Sharing record**: a timed list of what happened to a phone's and its watch's links
  during a shared match, read on the phone. It stays on the owner's phone and watch unless
  the owner shares it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a real-device field test of the incident's setup before release (host and
  three guests, each with a phone and a watch, no Wi-Fi, phones in bags) over a full set of
  at least 45 minutes, every device shows the host's score at every change of ends, and
  nobody has to join again by hand.
- **SC-002**: In that test, 95% of points appear on every device in range within 5 seconds,
  and all of them within 30 seconds.
- **SC-003**: A guest out of range for up to 10 minutes is back in step within 30 seconds of
  returning, without touching anything.
- **SC-004**: No device shows an out-of-date score as current for more than 15 seconds.
- **SC-005**: Each cause of the incident found under FR-006 is reproduced by an automated
  check that fails before its fix and passes after it.
- **SC-006**: For each failure staged in the field test (the host's app ended, a guest out
  of range, a guest's Bluetooth off, a watch out of reach of its phone), the sharing records
  alone are enough to tell which link broke: a watch and its own phone, or a guest and the
  host.
- **SC-007**: With the phone in a bag, the host can start sharing and read the code out from
  the watch within 3 taps of the scoreboard.
- **SC-008**: A guest can join from the watch within 10 seconds of typing the last digit,
  with the phone in a bag, and can leave within 3 taps.
- **SC-009**: In automated tests that simulate the radio link, with its speed set from the
  measurements of the SC-001 field test, a host and seven guests, each with a phone and a
  watch, play at least 30 minutes; every device shows the host's score at every check, with
  points arriving within the times in SC-002. The same is checked on real devices at the
  first club night after release.
- **SC-010**: When the host's app is ended mid-match, every guest in range is back in step
  within 30 seconds of the next point scored on any device, without anyone typing anything
  or touching the host's phone.
- **SC-011**: Every requirement under "Staying on the match" is covered by an automated test
  that simulates the radio link — drops, delays, suspended phones, an app ended and run
  again, seven guests — and those tests run on every push.
- **SC-012**: The battery each phone and watch used during the release field test (SC-001)
  is measured and reported beside an unshared match of the same length on the same devices,
  with the same workout setting.

## Assumptions

- A guest's phone and watch are one participant: joining or leaving on either one applies to
  both.
- The host's phone does the hosting. A watch cannot host a match on its own; the host's
  watch starts, stops and shows the sharing that its phone does.
- The code is kept only on the devices that have been on the match, never in a backup, and
  for at most 12 hours. Sharing after the host stops draws a new code.
- A phone cannot wake its watch's app. A notification posted on the phone shows on the
  watch, and is the way to bring Rekkert to the watch's screen without touching the phone.
- Devices are within two neighbouring padel courts of each other, about 30 metres at most.
- Every guest reaches the match through the host. Guests passing points on to each other,
  and a guest taking over as host, are out of scope.
- An app the system has ended is brought back by the radio or by its own watch. One its
  owner has swiped away is not, until it is opened again; meanwhile its watch covers it
  where it can (FR-009).
- Taps on the watch are counted from its scoreboard. Reaching the match menu counts as one,
  whether by a tap or a swipe.
- Guests on an older version keep working as they do today, but do not get the new watch
  features.
- Sharing has no battery limit. What it costs is measured and reported (SC-012), not used to
  hold a release.
- The sharing record holds link events only, not scores or player names beyond what the
  device already shows. It is kept on the owner's phone and watch and sent nowhere else
  unless the owner shares it, in line with the project's local-first principle.
- The watch failure in the incident may have been outside Rekkert. The requirements for a
  guest's watch hold either way: the watch says what is wrong and offers the way on.
