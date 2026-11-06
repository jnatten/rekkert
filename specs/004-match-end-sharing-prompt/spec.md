# Feature Specification: Asking at the End of a Shared Match, and Sharing Between Matches

**Feature Branch**: `004-match-end-sharing-prompt`

**Created**: 2026-11-06

**Status**: Draft

**Input**: User description: "Can we add a popup dialog whenever a match ends when we are currently sharing to stop the sharing session? Currently there is a weird behavior where the next one is auto launched on other devices sometimes and it can be a bit confusing without a popup of sorts. I think we also should have a popup on the devices that have joined as well if they want to leave. Maybe we at the same time add hosting, joining and leaving without being in a match since that is appearently the way it works?"

## Clarifications

### Session 2026-11-06

- Q: When a guest has not answered "stay or leave" by the time the host starts the next match,
  what should their phone and watch do? → A: Treat it as Stay. The next match arrives
  automatically, with a notice naming the host, a tap on the wrist, and Leave on the notice.
- Q: If a host never stops sharing, it comes back whenever their app reopens within 12 hours,
  and earlier guests could get the next match. Should sharing stop by itself after a while
  with no match on? → A: Yes. After 30 minutes with no match on, sharing stops and guests are
  told, as if the host had stopped it.
- Q: What form should the notice take when the host's next match lands on a guest? → A: A
  dialog naming the host, with OK and Leave: one tap before scoring, so nobody misses it.
- Q: If Rekkert is not on screen on a guest's phone or watch when the host's next match lands,
  should the guest get a system notification? → A: Yes. A notification naming the host, which
  shows on the watch; tapping it opens Rekkert on the new-match dialog.
- Q: When a host who is sharing starts a new match, should the start offer to play it without
  sharing? → A: No. A match started while sharing is always shared; to play one unshared, the
  host stops sharing first.
- Q: Should the sharing record also log the new events? → A: Yes: each end-of-match answer,
  each new-match dialog and how it was answered, and sharing stopping after 30 minutes with
  no match on.

## User Scenarios & Testing *(mandatory)*

### How sharing behaves today

Sharing outlives the match. When the host finishes a shared match, the code stays shared and
every guest stays linked to the host. When the host then starts another match, it appears on
every guest still linked, in place of whatever that guest was looking at, with nothing to say
it is coming or whose it is. Guests whose devices were asleep or out of reach get it later, or
only when Rekkert is next opened, which is why it seems to happen only sometimes.

Nobody is asked at the end of a match whether to carry on. A host who meant to stop has to
find Stop sharing behind the sharing glyph. A guest who wants to go home has to find Leave in a
menu behind a glyph on the phone's Home screen, and the watch has no Leave at all between
matches. Sharing can only be started from inside a match ("Share this match"), although it then
carries on between matches; joining already works with no match on, and the guest then waits
for the host's next match.

This feature keeps sharing lasting across matches, but makes it visible and asked about: the
host and each guest are asked at the end of every shared match, the next match is announced when
it lands, sharing can be started, joined, watched and left with no match on, and a forgotten
share stops by itself 30 minutes after the last match.

### User Story 1 - The host is asked at the end of a shared match (Priority: P1)

A host finishes a match they have been sharing. Alongside the result, Rekkert asks whether to
keep sharing for the next match or stop sharing. One tap stops it, and the guests are told; one
tap keeps it, and the guests are told the host is staying on.

**Why this priority**: this is what was asked for. Stopping at the end of an evening today
takes a hunt through a menu, so sharing is often left on, and that is what lets the next match
land on phones whose owners thought they were done.

**Independent Test**: A host shares a match with two guests and finishes it. The host's
device asks; choosing Stop sharing leaves both guests told that sharing stopped and holding the
finished match in History. Repeated with Keep sharing, both guests stay on and the next match
the host starts reaches them.

**Acceptance Scenarios**:

1. **Given** a host sharing a match with guests on it, **When** the host finishes the match,
   **Then** the device it was finished on asks whether to keep sharing for the next match or
   stop sharing, says how many guests are on, and the result stays readable.
2. **Given** that question on the host's device, **When** the host chooses Stop sharing,
   **Then** sharing stops as it does today: every guest in reach is told, keeps the finished
   match in History, and forgets the code.
3. **Given** that question on the host's device, **When** the host chooses Keep sharing,
   **Then** the code stays the same, every guest stays on, and each guest is told the host is
   keeping it shared.
4. **Given** a host who finished the match on the watch with the phone in a bag, **When** the
   host answers on the watch, **Then** the answer takes effect without the phone being touched,
   and the phone does not ask again.
5. **Given** a host who calls a shared match off rather than saving it, **When** the match
   ends, **Then** the host is asked in the same way.

---

### User Story 2 - Each guest is asked, and the next match never arrives unannounced (Priority: P1)

A guest's shared match ends. Their phone or watch shows the result and asks whether to stay for
the host's next match or leave. A guest who leaves is off and stays off. A guest who stays sees
that they are waiting for the host's next match, and when it starts, a dialog says whose it is,
and one tap on OK has them scoring it.

**Why this priority**: this is the confusion that was reported. A match appearing on a guest's
screen with no warning, and only on some of them, is what makes the evening feel broken.

**Independent Test**: A host shares a match with three guests and keeps sharing at the end.
One guest chooses Leave, one chooses Stay, and one does not answer. The host starts the next
match. The guest who left never sees it; the other two see it arrive with the new-match dialog
naming the host, and the unanswered question is gone.

**Acceptance Scenarios**:

1. **Given** a guest on a shared match, **When** the host finishes it, **Then** within
   15 seconds the guest's phone or watch shows the result and asks whether to stay for the
   host's next match or leave, naming the host where the host gave a name.
2. **Given** that question, **When** the guest chooses Leave, **Then** the guest's phone and
   watch both leave, the finished match stays in the guest's History, and the host's list shows
   the guest gone within 15 seconds while the other guests stay on.
3. **Given** a guest who chose Leave and is still in range, **When** the host starts the next
   match on the same code, **Then** that match does not appear on the guest's phone or watch.
4. **Given** a guest who chose Stay, **When** the host starts the next match, **Then** it
   appears on the guest's phone and watch with a dialog naming the host, with OK and Leave, and
   the watch taps the wrist, following its haptics setting; one tap on OK and the guest is
   scoring it.
5. **Given** a guest who stayed, with the phone in a bag and the watch showing the time,
   **When** the host starts the next match, **Then** a notification naming the host shows on
   the watch, and tapping it opens Rekkert on the new-match dialog.
6. **Given** a guest who has the question open, **When** the host stops sharing, **Then** the
   question is replaced by the notice that the host stopped sharing, and the guest is not asked
   anything further.
7. **Given** a guest who answers on the watch with the phone in a bag, **When** they choose
   Leave or Stay, **Then** the phone follows that answer and does not ask again.

---

### User Story 3 - The host shares with no match on (Priority: P2)

Before the first match of the evening, the host opens Rekkert, starts sharing from the Home
screen (or the watch's start screen), and reads out the code while everyone is still getting
their racquets out. The guests join and wait. When the host starts the first match, it reaches
everyone who is on. Between matches, the host's Home screen says plainly that sharing is on,
on which code, and who is on, with Stop sharing right there.

**Why this priority**: sharing already lasts across matches, so it may as well start before
one. It also removes the awkward step of starting a match just to get a code, and gives the
host one obvious place to stop. But every part of the evening already works without it once a
match is on.

**Independent Test**: With no match on, the host starts sharing from Home, two guests join, the
host starts a match and both guests get it. With no match on again, the host stops sharing from
Home and both guests are told.

**Acceptance Scenarios**:

1. **Given** a host with no match on, **When** the host starts sharing from the phone's Home
   screen or the watch's start screen, **Then** the code shows as it does when sharing a match,
   and guests can join with it.
2. **Given** a host sharing with no match on, **When** the host looks at the phone's Home
   screen or the watch's start screen, **Then** it shows that sharing is on, how many guests
   are on, the code within one tap, and Stop sharing.
3. **Given** a host sharing with guests on and no match on, **When** the host goes to start a
   match, **Then** the start makes clear the match will be shared with the guests who are on,
   and once started it reaches each of them as in User Story 2.
4. **Given** a host sharing with no match on, **When** the host chooses Stop sharing and
   confirms, **Then** every guest in reach is told and forgets the code.

---

### User Story 4 - Guests join, wait and leave with no match on (Priority: P2)

A guest joins before the host has started anything. Their phone and watch say they are on the
host's sharing and waiting for the next match, rather than looking as though nothing happened.
Between matches, Leave is right there on the phone's Home screen and on the watch's start
screen.

**Why this priority**: joining with no match on already works, but the guest is left looking
at a waiting spinner or their own Home screen with no sign of whose sharing they are on, and on
the watch there is no way off between matches.

**Independent Test**: With the host sharing and no match on, a guest joins from the phone,
checks both phone and watch show the waiting state naming the host, leaves from the watch's
start screen, and confirms the phone left too and the host's next match does not arrive.

**Acceptance Scenarios**:

1. **Given** a host sharing with no match on, **When** a guest joins from the phone or the
   watch, **Then** the guest's phone and watch both show that they are on the host's sharing,
   naming the host, and waiting for the next match.
2. **Given** a guest waiting between matches, **When** they choose Leave on the phone's Home
   screen or the watch's start screen and confirm, **Then** both the phone and the watch leave,
   and the host's sharing carries on for everyone else.
3. **Given** a guest waiting between matches, **When** they start a match of their own on the
   phone or the watch, **Then** they are asked once first, since that takes them off the
   host's sharing.
4. **Given** a guest who left while the host is still sharing, **When** they choose Join again,
   **Then** they are back on without typing the code, whether or not a match is on.

---

### Edge Cases

- The host finishes a match and starts the next one straight away, before some guests have
  answered. Starting the next match counts as the host keeping sharing; each guest who had not
  answered gets it as though they had chosen Stay, with the new-match notice (FR-012).
- A guest is out of reach when the match ends. If the host is still sharing when they come back
  in reach, they are asked then; if the host has started another match by then, they get it with
  the new-match notice (FR-012); if the host stopped sharing, they get that notice instead.
- A guest's phone says Stay and its watch says Leave before the two are back in touch. Leave
  wins: leaving is the answer that is harder to undo by accident and easy to undo on purpose
  (Join again).
- The host finishes on the watch, chooses Stop sharing, and the watch cannot reach the host's
  phone. The watch says so and nothing changes, as for Stop sharing on the watch today; the
  phone asks the question when it is next opened.
- The host's app is ended by the system between matches. Run again within 30 minutes of the
  last match, it comes back sharing on the same code, as today, and does not ask again about a
  match already answered for; run again later, it does not share (FR-026).
- A tournament or americano reaches the end of a round. That is not the end of the match; only
  finishing or calling off the whole tournament asks.
- The host is sharing but nobody has joined. The host is still asked, and the question says
  nobody is on.
- A guest leaves at the end of a match, then the host keeps sharing and starts the next one.
  The guest who left does not get it, even standing next to the court.
- A guest is on an older version of Rekkert. They are not asked, and behave as today; the host
  and the other guests are unaffected.
- Two hosts nearby are each sharing between matches. A guest waiting on one only ever gets that
  host's next match.
- The host leaves without answering the end-of-match question and opens Rekkert the next
  morning. Sharing stopped 30 minutes after the last match (FR-026), so the morning's first
  match goes to nobody, and the evening's guests were told when it stopped.
- The break between two matches runs past 30 minutes. Sharing stops and everyone is told; the
  host shares again and the guests join again with the code.

## Requirements *(mandatory)*

### Functional Requirements

**The host, at the end of a shared match**

- **FR-001**: When a match the host is sharing ends — finished and saved, or called off — the
  device it was ended on MUST ask the host whether to keep sharing for the next match or stop
  sharing, and MUST say how many guests are on at that moment.
- **FR-002**: The question MUST NOT hide or replace the result: the match's result stays
  readable while it is asked, and answering it changes nothing about the result.
- **FR-003**: Choosing Stop sharing MUST stop sharing exactly as stopping does today (every
  guest in reach told before the host lets go, each keeping the finished match in History and
  forgetting the code). It MUST NOT ask a second time.
- **FR-004**: Choosing Keep sharing MUST leave the code, the guests on it and their access
  unchanged.
- **FR-005**: The question is asked once per match for the host's phone and watch together:
  an answer on either MUST take effect for both, and the other MUST stop asking within
  10 seconds of the two being in touch.
- **FR-006**: If the host leaves the question unanswered, sharing MUST carry on as if Keep
  sharing had been chosen, until FR-026 stops it. Starting another match MUST count as Keep
  sharing.
- **FR-007**: Stop sharing chosen on the host's watch while the watch cannot reach the host's
  phone MUST say so and change nothing, as stopping from the watch does today.

**Each guest, at the end of a shared match**

- **FR-008**: When the host's shared match ends, each guest in reach MUST, within 15 seconds,
  see the result and be asked whether to stay for the host's next match or leave, naming the
  host where the host gave a name. If the host has already chosen Keep sharing, the question
  MUST say so. If the host chose Stop sharing, the guest MUST get only the notice that the host
  stopped sharing, not the question.
- **FR-009**: Choosing Leave MUST take the guest's phone and watch off the host's sharing
  together, keep the finished match in the guest's History, and forget the code. The host's
  sharing MUST carry on for everyone else, and the host's list MUST show the guest gone within
  15 seconds.
- **FR-010**: Choosing Stay MUST keep the guest on the host's sharing, showing the waiting
  state of FR-018 until the host's next match arrives or sharing stops.
- **FR-011**: A guest's phone and watch are asked once together: an answer on either MUST take
  effect for both, and the other MUST stop asking within 10 seconds of the two being in touch.
  If they answered differently while apart, Leave MUST win.
- **FR-012**: A guest who has not answered by the time the host starts the next match MUST be
  treated as having chosen Stay: the match arrives on their phone and watch automatically, with
  the notice of FR-013, and the unanswered question is replaced by that notice.
- **FR-013**: Whenever the host's next match arrives on a guest, the guest's phone and watch
  MUST show a dialog naming the host and saying a new match has started, with OK and Leave,
  and the watch MUST tap the wrist, following its haptics setting. The match MUST NOT take
  scoring taps on that device until the dialog is answered. OK or Leave on either device of the
  pair answers for both, and the other MUST close its dialog within 10 seconds of the two
  being in touch. A new match MUST never replace what a guest is looking at without that
  dialog.
- **FR-027**: When the host's next match arrives on a guest whose phone and watch do not have
  Rekkert in front, the guest's phone MUST post one notification naming the host that reaches
  the watch, and tapping it MUST open Rekkert on the new-match dialog. If notifications are not
  allowed, the dialog MUST show the next time Rekkert is opened. The notification MUST be
  withdrawn once the dialog is answered on either device.
- **FR-014**: Every guest who is on when the host starts the next match MUST get it in the
  same way, within the times of spec 001 (FR-002 and FR-014 there); a guest out of reach at
  that moment MUST get it on coming back in reach.
- **FR-015**: A guest who has left MUST NOT get the host's next match, whether or not it is in
  range and whether or not the host is still sharing on the same code, until they join again.

**Sharing with no match on**

- **FR-016**: The host MUST be able to start sharing from the phone's Home screen and from the
  watch's start screen with no match on. The code MUST show as it does when sharing a match
  (scannable and in digits on the phone; as spec 001 FR-017 and FR-018 require on the watch),
  and guests MUST be able to join with it.
- **FR-017**: While the host is sharing with no match on, the phone's Home screen and the
  watch's start screen MUST show that sharing is on, how many guests are on, the code within
  one tap, and Stop sharing, which asks once. These MUST appear only on the host's devices.
- **FR-018**: A guest on a host's sharing with no match on — having just joined, or having
  stayed after a match — MUST see on the phone's Home screen and on the watch's start screen
  that they are on that host's sharing, naming the host, and waiting for the next match. It
  MUST NOT show an earlier score as though it were current.
- **FR-019**: Leave MUST be available from that waiting state on both the phone and the watch,
  at most one tap from where it is shown, MUST ask once, and MUST take the guest's phone and
  watch off together.
- **FR-020**: Starting a match while sharing MUST make clear, before it starts, that it will be
  shared with the guests who are on, and how many there are. Every match started while sharing
  is shared; the start MUST NOT offer to play it unshared. A host who wants that stops sharing
  first.
- **FR-021**: A guest who starts a match of their own while on a host's sharing with no match
  on MUST be asked once first, on the phone as well as the watch, since it takes them off the
  host's sharing.
- **FR-022**: Wherever sharing is started, shown or stopped, its wording MUST describe it as
  lasting across matches until it is stopped, not as belonging to the match on screen.
- **FR-026**: Sharing MUST stop by itself once 30 minutes have passed with no match on,
  counted from the end of the last match, or from when sharing started if no match has been
  played since. Guests in reach MUST be told as when the host stops sharing, with the reason;
  the host MUST be told the same the next time they look at the phone or the watch. A host's
  app that comes back after those 30 minutes MUST NOT start sharing again by itself, and a
  guest still waiting after those 30 minutes MUST leave by itself, keep its History and forget
  the code, whether or not it can reach the host.

**Throughout**

- **FR-023**: The questions, notices and waiting states of this feature MUST work with
  VoiceOver and with larger text sizes, on the phone and on the watch.
- **FR-024**: What spec 001 requires of sharing stays true unless a requirement here changes
  it: how long the code is kept, getting back on after an app is ended, telling guests when the
  host is out of reach, and which controls appear only on the host's or only on a guest's
  devices.
- **FR-025**: A guest on an older version of Rekkert need not be asked or notified, but MUST
  keep working as it does today and MUST NOT disturb the host or any other guest.
- **FR-028**: The sharing record of spec 001 (FR-012 and FR-013 there) MUST also note, with
  times: each end-of-match answer given on that phone or its watch (keep sharing or stop, stay
  or leave, or none before the next match arrived), each new-match dialog shown and how it was
  answered, and sharing stopping after 30 minutes with no match on (FR-026). It stays on the
  owner's phone and watch unless the owner shares it, as there.

### Key Entities

- **Sharing**: the host's offer for others to follow and score their matches, from when it is
  started until the host stops it or 30 minutes pass with no match on, known by one code. It
  spans any number of matches, including none yet. Guests are on it or not; being on it is what
  makes the host's next match arrive.
- **Host**: the phone that shares, and its own watch.
- **Guest**: a player on someone else's sharing, with a phone and usually a watch, which join,
  stay and leave together.
- **End-of-match question**: asked once per shared match of the host (keep sharing or stop) and
  of each guest (stay or leave), shown beside the result, answered on either device of a pair.
- **Waiting state**: what a guest's phone and watch show while on a host's sharing with no match
  on: whose sharing it is, that the next match will come from them, and the way to leave.
- **New-match notice**: the dialog a guest sees when the host's next match arrives: whose it
  is, that it has started, and OK or Leave, answered once for the phone and watch together.
- **Sharing record**: the phone's timed log from spec 001, which now also holds the
  end-of-match answers, the new-match dialogs, and sharing stopping by itself.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Over an evening of three shared matches with a host and three guests, every guest
  who chose Stay gets each following match, and no guest who chose Leave gets one.
- **SC-002**: In that evening, no guest's phone or watch changes to a new match without the
  new-match notice naming the host.
- **SC-003**: A host can stop sharing at the end of a match in one tap from the result,
  where today it takes at least two after finding the sharing glyph.
- **SC-004**: A guest can leave between matches in at most two taps, including the
  confirmation, from the phone's Home screen or the watch's start screen.
- **SC-005**: With no match on, a host can show the code in at most two taps from the phone's
  Home screen or the watch's start screen.
- **SC-006**: Every guest in reach is asked within 15 seconds of the host ending the match.
- **SC-007**: Asked afterwards whether anything appeared on their phone or watch that they did
  not expect, players in that evening report no match arriving by surprise.
- **SC-008**: A share left on with no match on stops within 31 minutes of the last match, with
  every guest in reach told, and the host's next match after that reaches none of them.

## Assumptions

- A match ends when it is finished and saved or called off as a whole. The end of a set, a
  game, or a round of a tournament or americano is not the end of a match.
- When the host does not answer, sharing carries on (FR-006). That is today's behaviour, and a
  host playing with the phone in a bag may not see the question before starting the next match.
  A forgotten share ends 30 minutes after the last match instead (FR-026).
- The host is asked even when nobody is on, because the code may have been read out to people
  who have not joined yet.
- The question shows on whichever device of the pair the match was ended on, or is in front,
  and is answered once for both.
- The phone does the hosting. The host's watch starts, shows and stops sharing through it, now
  also with no match on, as spec 001 assumes for sharing a match.
- Joining with no match on already works; this feature makes it visible and adds the way off.
- The code is kept and drawn as spec 001 describes. Stopping and starting again may give a new
  code.
- This feature builds on specs/001-fix-session-sharing; requirement numbers from there are
  quoted as "spec 001 FR-…".
