# Feature Specification: Steadier, Measurable Sharing for Two Full Courts

**Feature Branch**: `005-steady-sharing-nine-guests`

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description: "Let users connect more than 7 guests with session sharing, without much delay or battery consumption", assessed and approved as Option A in `.specify/assessments/session-sharing-limits/decision.md`. Option A has three steps: see what is happening, steady the links, then measure and raise the limit, stopping if the measurements say no.

## Clarifications

### Session 2026-11-10

- Q: What share of points must arrive within 1 second when nothing is wrong? → A: At least
  95%, and all of them within 2 seconds (FR-010).
- Q: How much extra battery may sharing use, and does missing a bar hold the release? → A: No
  limit. Battery is measured on every phone and watch, the host's included, and reported, but
  it holds back nothing, as in spec 001 (FR-019).
- Q: Must a real two-court evening confirm the raised limit before it is released? → A: No.
  It ships once the calibrated simulation shows nine guests fit, and is confirmed at the first
  two-court evening after release, as spec 001 did for seven. The small real-device run that
  calibrates the simulation still comes before release (FR-016, FR-018).
- Q: When one of a guest's two connections to the host drops but the other stays up, must
  points still arrive within the 1-second and 2-second times? → A: Yes. While any connection
  to the host is up, FR-010's times apply in full. A second connection dropping is not
  "something wrong" (FR-008, FR-010, FR-011).
- Q: How should a run decide, for each arriving point, whether "nothing is wrong" held for the
  device it arrived on? → A: Nothing is wrong for a point when its receiving device had a
  connection to the host up, and had not been out of reach (15 s unheard) or caught up a batch,
  in the 30 seconds before it arrived. All of this is read from the sharing record (FR-010).
  This was extended to watches in FR-010 after analysis: a watch following its phone counts its
  link to that phone, and the phone must meet the same condition.
- Q: How many points on a device may have an unknown delay before a run can no longer be
  judged against the 1-second and 2-second times? → A: At most 10% per device. Above that, the
  run cannot be judged on FR-010 for that device until the clock bounds are fixed
  (FR-006, FR-010).
- Q: Should "at most 5 drops per guest per hour" hold back a release, or be a target the field
  runs report against? → A: A target, not a gate. Drops per guest per hour are reported on
  every run against the goal of 5, and a release is held only by the delay times (FR-007,
  FR-008, FR-010).
- Q: For a guest still on version 1.0, what must FR-015's "never appear to be on while getting
  no points" guarantee? → A: Nothing beyond today. FR-015 covers 1.1 and later. A 1.0 guest is
  out of scope: the host lists it as catching up, never as in step, and its own screen stays as
  it is (FR-015).

## User Scenarios & Testing *(mandatory)*

### What this starts from

Groups of more than eight regularly play together: two full courts, with two people sitting
out, is ten people including the host. Today the host takes at most seven guests, so at every
such evening at least two people cannot follow on their own phone and watch. Seven was never
measured. Spec 001 chose it as a safe placeholder until a real-device test, and that test was
skipped.

Those who can follow have seen the score arrive slowly. The sharing records from 8 and
9 November show why. Every guest that was connected over both Bluetooth and Wi-Fi had its
second connection to the host drop about once a minute all evening: 56–70 times an hour. That
happened with only four guests on, and on 8 November with a single guest standing next to the
host. A guest on Bluetooth alone did not drop once. The records cannot show how late points
were, because only developer builds note that. Nobody has measured what sharing costs in
battery.

### User Story 1 - Points show on every device within a second, even in a busy hall (Priority: P1)

A host shares a match at a hall with no venue Wi-Fi, with other people and their phones
around. Guests are on with their phones in bags and their watches on, some with Wi-Fi switched
on and some without. A point tapped on any device shows on every other phone and watch on the
match within about a second. That still holds when one of a guest's connections drops, when
strangers come into the hall, and an hour into the evening.

**Why this priority**: this is the pain players have now, at any group size, and raising the
limit would only spread it to more people.

**Independent Test**: On every push, automated tests simulate a host and four guests in a
busy hall. Each guest is connected over both radios, and one connection to each guest keeps
dropping. The tests check every point's delay against FR-010. Before release, a host and three
guests in a real hall, with their phones in bags and Wi-Fi on, play an hour, and their sharing
records are compared against FR-010 and FR-006.

**Acceptance Scenarios**:

1. **Given** a host and four guests on a match, each connected over both Bluetooth and Wi-Fi,
   **When** points are tapped on watches for an hour, **Then** every point shows on every other
   phone and watch within the times in FR-010.
2. **Given** a guest connected over both radios, **When** one of its connections drops,
   **Then** points keep showing on that guest's phone and watch within the times in FR-010
   while it reconnects.
3. **Given** a match in a hall, **When** many other people's phones come into range, **Then**
   points still show within the times in FR-010.
4. **Given** a guest with Wi-Fi switched off, **When** points are tapped, **Then** that guest's
   devices meet the same times as everyone else's.
5. **Given** a shared match, **When** the host's phone turns Bluetooth off and on by itself,
   **Then** every guest is back in step within 10 seconds without anyone touching anything.

---

### User Story 2 - The sharing record says how late points were and which link dropped (Priority: P1)

After an evening where sharing felt slow, anyone who was on the match opens the sharing record
on their phone. It shows how long each point took to arrive, whether over Bluetooth or Wi-Fi,
and which connection dropped and when. At the top, a short summary of each shared session says
whether points were on time. The owner can share the record with the developer, as today. This
works in the builds people actually play with, not only developer builds.

**Why this priority**: every other part of this feature has to be proven with these numbers.
Without them, nobody can tell whether a change made sharing faster, and the next slow evening
will be as hard to explain as the last one.

**Independent Test**: In the simulated tests of User Story 1, and in the real-device run,
export the record from each phone. Check that every point that arrived from another device
lists its delay and radio, that every drop and reconnect names its radio, and that the summary
matches the entries.

**Acceptance Scenarios**:

1. **Given** a guest's phone on a shared match, **When** a point arrives from another device,
   **Then** the phone's record notes how long after the tap it arrived, and over which radio.
2. **Given** a guest's watch on a shared match, **When** points arrive there, **Then** their
   delays are noted too, and appear in the phone's record once the two are back in touch.
3. **Given** a link that drops and reconnects, **When** the owner reads the record, **Then**
   each drop and reconnect says whether it was the Bluetooth or the Wi-Fi connection.
4. **Given** a shared session that has ended, **When** the owner opens the record, **Then**
   the summary shows, for that session, the typical and slowest delay, the share of points
   within the FR-010 times, and how often each connection dropped.
5. **Given** an exported record, **When** anyone reads it, **Then** it contains no scores,
   names or codes, and it left the phone only because the owner shared it.

---

### User Story 3 - Two full courts and two sitting out, all on one match (Priority: P2)

At an americano over two side-by-side courts with ten players, the host shares the match and
all nine others join with their phones and watches. Everyone follows the score on their own
devices, within the same times as in User Story 1. Anyone beyond the limit is told plainly
that there is no room, and why.

**Why this priority**: it is what was asked for, but it is only worth doing once points are
fast and the numbers show the host can carry nine guests in time (FR-016). If they cannot,
User Stories 1 and 2 ship without it.

**Independent Test**: On every push, automated tests simulate a host and as many guests as the
limit allows (nine once raised), each with a phone and a watch, in a two-court americano in a
busy hall for at least 30 simulated minutes. They check FR-010 on every device, and the next
guest is refused and told so. Before the limit is raised, the same setup is run once with nine
guests as a prediction (FR-016). After release, it is confirmed on real devices at the first
two-court evening (FR-018).

**Acceptance Scenarios**:

1. **Given** a host sharing a two-court americano, **When** nine guests join with their phones
   and watches, **Then** the host lists all nine as on the match, and every phone and watch
   shows the host's score within the times in FR-010.
2. **Given** a match at its limit, **When** one more guest tries to join, **Then** that guest
   is told on phone and watch, within 15 seconds, that the match is full.
3. **Given** a match at its limit, **When** a guest already on also gets on with their watch,
   **Then** the watch is not turned away, because one person counts once.
4. **Given** a guest on Rekkert 1.1, **When** they try to join a match whose
   host has the raised limit, **Then** they either get on as a guest counted once, or are told
   plainly that they need to update. They are never silently left behind.

---

### User Story 4 - Know before a club night whether sharing will hold up (Priority: P3)

Before taking a change to a club night, the developer can tell from the simulated tests
whether a full two-court evening will get its points within the FR-010 times. The simulated
speeds are set from a real run, so they can be trusted. After the evening, the sharing records
and the battery readings confirm it or show where it fell short.

**Why this priority**: it is how the team avoids finding out on court. It matters most at the
point of raising the limit.

**Independent Test**: Run the small real-device test (a host and three guests in a hall), set
the simulated speeds from its records, and run the simulation of that same setup. Compare the
delays the simulation predicts with those the real records show.

**Acceptance Scenarios**:

1. **Given** the records of a real run, **When** the simulated speeds are set from them and
   that run is replayed in the simulation, **Then** the simulated delays match the real ones
   within the tolerance in FR-017.
2. **Given** a calibrated simulation, **When** it runs the two-court, nine-guest setup,
   **Then** it gives a clear prediction of whether FR-010 will hold.
3. **Given** a real-device run, **When** it ends, **Then** each phone's and watch's battery use
   over the run is known and reported (FR-019).

### Edge Cases

- **Only one radio available.** A guest with Wi-Fi switched off, or one whose Wi-Fi cannot
  reach the host, follows over Bluetooth alone and meets the same times.
- **A venue Wi-Fi network everyone has joined.** Sharing works at least as well as with none.
- **Device clocks that disagree.** Delays in the record are counted from the tap. A difference
  between two devices' clocks must not make a point look faster or slower than it was by more
  than FR-006 allows. If the clocks cannot be reconciled, the record says the delay is unknown
  rather than giving a wrong one.
- **A device's clock changing mid-evening**, set by hand or corrected by the network. Delays
  across the change read unknown, never wrong.
- **The host's Bluetooth restarting by itself**, as at 19:54 on 9 November. Guests come back
  by themselves (Story 1 scenario 5), and the record notes the restart. Stopping the system
  from doing it is out of scope.
- **Strangers' phones and watches nearby**, including other people sharing with Rekkert on the
  next court. They neither slow the match down nor get onto it.
- **A guest's watch standing in for its phone** while the phone is away still counts once
  toward the limit, and still gets points within the FR-010 times.
- **A point tapped while a connection is dropping** is never lost and never shown twice. It
  arrives over the other connection or as soon as the link is back.
- **A long evening.** Delay entries for a two-hour evening with ten people fit in the record,
  and the 7-day limit still applies.
- **The measurements say no.** If the calibrated simulation shows the host cannot carry nine
  guests within the FR-010 times, the limit stays at seven. If the first two-court evening after
  release shows it instead, the next release lowers the limit to what that evening supported
  (FR-016).

## Requirements *(mandatory)*

### Functional Requirements

**Seeing what happened**

- **FR-001**: Each phone's and each watch's sharing record MUST note, for every point that
  arrives from another device, how long after the tap it arrived. This MUST be in every build
  distributed to players, not only developer builds. Only point taps are timed. An undo or a
  correction is not timed, and does not count toward FR-010.
- **FR-002**: Every entry in the record about a connection to the host or a guest MUST say
  which radio it was on, Bluetooth or Wi-Fi: proven, dropped, reconnected, out of reach, back in
  step. A delay entry MUST also say which radio the point came over.
- **FR-003**: The phone's record MUST start each shared session with a summary. A shared
  session (a "stint") is one stretch of sharing: from starting, restoring or joining it, until
  it stops or the guest leaves. It can span several matches. The summary holds:
  - the typical and the slowest delay;
  - the share of points within each FR-010 time;
  - the share of points whose delay is unknown;
  - how many times each radio's connection dropped (as FR-007 counts drops), and separately,
    how many times the host's Bluetooth restarted by itself;
  - how long each guest or the host was unreachable: from being out of reach (15 s unheard)
    until back in step;
  - up to when the watch's entries are included, when the watch has not been in touch since,
    as the export's header already says.
- **FR-004**: The record MUST keep holding no scores, no names and no codes, MUST stay on the
  owner's devices, and MUST leave them only when the owner shares it, as spec 001 FR-012 and
  FR-013 set out.
- **FR-005**: The watch's delay entries MUST reach the phone's record the same way its other
  entries do today: whenever the two are in touch. Until they have, the phone's summary says
  up to when the watch's half is included (FR-003).
- **FR-006**: A delay in the record MUST be within 0.1 seconds of the true time from tap to
  arrival, whatever the difference between the two devices' clocks. If that cannot be
  guaranteed for a point, the record MUST mark that point's delay as unknown. At most 10% of
  the points arriving on a device in a run may be unknown. Above that, FR-010 cannot be judged
  for that device, and the run does not count as meeting it.

  Points from, or relayed through, a device on 1.1 carry no clock readings. They are recorded
  as unknown for that reason, and left out of both the 10% cap and FR-010.

**Steady links and fast points**

- **FR-007**: While every device on the match is in range, a guest's connections to the host
  SHOULD drop no more than 5 times an hour on average, in a busy hall (FR-010) with both radios
  in use. This is a target, not a release gate: every field run MUST report drops per guest per
  hour against it, and only the delay times (FR-008, FR-010) hold a release back.
  - **In range** means anywhere on the two side-by-side courts the match is played on.
  - **A drop** is any one connection to the host ending, counted per connection. Drops caused
    by the host's Bluetooth restarting by itself (FR-009) are counted separately, and not
    against the target.
  - **On average** means across every guest on the match, over the whole run.
- **FR-008**: When one of a guest's connections drops while another to the host is still up,
  points MUST keep arriving within the FR-010 times. A dropping connection costs no one time.
- **FR-009**: After the host's phone loses Bluetooth for a short while and gets it back by
  itself, every guest MUST be back in step within 10 seconds, without anyone touching anything.
- **FR-010**: When nothing is wrong, a point tapped on any device on the match MUST show on
  every other phone and watch on it within 1 second for at least 95% of points, and within
  2 seconds for all of them. "Every other" includes the scorer's own paired phone or watch. That
  holds with phones locked in bags, in a busy hall, and whichever radios each guest has on.
  - **A busy hall** is a hall in use, with other players and their phones and watches present.
    In the simulated tests, it is the busy-hall settings.
  - **A point that never arrives** on a device counts there as later than 2 seconds.
  - **Enough points to judge.** FR-010 is judged for a device only once it has at least 100
    timed points in the run.

  "Nothing is wrong" holds for a point when:
  - the device it arrived on had a connection up:
    - to the host, for a guest's phone;
    - to the guest the point came from, for the host;
    - to its own phone, for a watch following that phone, and that phone met this condition
      at the same moment;
  - and in the 30 seconds before the point arrived, the device had neither been out of reach
    (15 s unheard) nor caught up a batch of points.

  All of this is read from the sharing records. A guest that loses one connection while
  another to the host is still up counts as nothing wrong.
- **FR-011**: For any point where FR-010's "nothing is wrong" does not hold, spec 001's FR-002
  times still hold: within 30 seconds for every point, and within 5 seconds for at least 95%,
  counted from the tap. That covers a device with no connection to the host, out of reach,
  catching up, or just back. FR-010 and FR-011 together cover every point.

**Room for two full courts**

- **FR-012**: Once FR-016 allows it, a shared match MUST carry the host and at least nine
  guests. Until then, it carries as many as the current limit. Each guest has a phone and a
  watch, the match is on two side-by-side courts, and there is no shared Wi-Fi.
  FR-010 holds for every device. A guest counts once whether on with their phone, their watch
  or both, as in spec 001 FR-001.
- **FR-013**: The guest after the limit MUST be turned away within 15 seconds, and told on
  phone and watch that the match is full, as in spec 001 FR-008.
- **FR-014**: The host's list of who is on, and the share sheet, MUST show how many are on out
  of how many fit, on the phone and on the watch.
- **FR-015**: A device on version 1.1 or later MUST either be on the match as a guest counted
  once, or be told plainly that it needs updating to join. It MUST never appear to be on while
  getting no points. Older versions do not have to be able to join. A guest on 1.0 is out of
  scope: the host lists it as catching up, never as in step, and its own screen stays as it is.
  In detail:
  - **1.1 keeps working.** Nothing in this release may stop a 1.1 guest from following a match.
  - **A full match.** A 1.1 guest turned away from it is told so in 1.1's own "no room"
    wording, without the number.
  - **A 1.1 host.** A guest from this release on it follows as today. The count shows without
    a limit, and delays relayed through that host read unknown (FR-006).
  - **Mixed versions.** A phone and its watch on different versions still count as one guest.
    The phone's record keeps the watch entries it can read.
  - **Later breaks.** From this release on, a later breaking change MUST be able to tell guests
    plainly that they need to update.
- **FR-016**: A released build MUST NOT take more guests than the calibrated simulation
  (FR-017) shows meet FR-010 together. If it shows fewer than nine, the limit stays at seven,
  and FR-001–FR-011 ship without it. If the two-court evening in FR-018 later shows the limit
  falls short, the next release MUST lower it to what that evening supported.

**Knowing before, and confirming after**

- **FR-017**: The simulated radio's speeds MUST be set from the records of a real-device run
  with a host and at least three guests in a hall. Replaying that run in the simulation MUST
  give a 95th-percentile delay within 25% of the real one.
  - **Replaying** means the same devices, the same taps at the same times, and the same
    connection drops as the records show.
  - **The run includes a burst.** Two guests walk out of range for about two minutes and come
    back, so the host is loaded enough to calibrate from.
- **FR-018**: The real-device run in FR-017 MUST happen before release, with its records kept
  as evidence. This is the field test spec 001 skipped (its T078). The raised limit MUST then
  be confirmed at the first two-court evening with a host and nine guests after release, as
  spec 001 did for seven guests, with that evening's records kept as evidence.
- **FR-019**: Battery use on every phone and watch, the host's included, MUST be measured
  during the real-device runs, with and without sharing, and reported. There is no limit, and
  the result holds back nothing, as in spec 001.
- **FR-020**: Automated tests that simulate the radio link MUST cover every requirement in this
  spec and run on every push. They include a host and as many guests as the limit allows
  (nine, once FR-016 raises it), each with a phone and a watch, in a two-court americano in a
  busy hall, with connections that keep dropping. Until the limit is raised, nine guests are
  checked as a prediction (FR-016), not on every push.

### Key Entities

- **Delay entry**: one point arriving on one device. It records when it arrived, how long
  after the tap, over which radio, and from which link. It holds no score.
- **Connection entry**: a connection to the host or a guest being proven, dropped,
  reconnected, unreachable or back in step. It names the radio.
- **Session summary**: per shared session (stint, FR-003), on the phone. It holds:
  - the typical and slowest delay;
  - the share of points within the FR-010 times, and the share unknown;
  - drops per radio;
  - unreachable time per guest;
  - battery per hour.
- **Arrival condition**: for one point on one device, whether nothing was wrong (FR-010). It is
  worked out from that device's sharing record, and for a watch, from its phone's record too.
- **Guest limit**: how many guests a host takes, one person counting once. It is set no higher
  than the measurements support (FR-016).
- **Field run**: a real-device test. It records which devices took part, where, how long it
  lasted, each device's sharing record, and battery readings with and without sharing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: At a two-court evening, ten people including the host follow one match on their
  own devices, and nobody is told the match is full. Baseline: eight.
- **SC-002**: In a real-device run in a hall with other people around, points show on every
  device within the FR-010 times. Baseline: unknown, as today's builds do not record delay.
- **SC-003**: In that run, drops per guest per hour are reported against FR-007's target of 5.
  Baseline: 56–70 an hour for guests on both radios on 9 November.
- **SC-004**: After the host's Bluetooth drops out and comes back by itself, every guest is
  back in step within 10 seconds.
- **SC-005**: The extra battery sharing uses over a 2-hour session is known and reported for
  every phone and watch in the real-device runs, the host's included. Baseline: never measured.
- **SC-006**: Replaying a real run in the simulation predicts its 95th-percentile delay
  within 25%. Baseline: the simulation's speeds have never been checked against devices.
- **SC-007**: Reading only an exported sharing record, the owner can tell how late points were
  and which connection dropped, without help from the developer.
- **SC-008**: Every functional requirement is covered by an automated test that runs on every
  push.

## Assumptions

- **The target is the host and nine guests on two side-by-side courts.** More courts or a
  whole venue are out of scope. Ten people is the floor the requester gave, and nothing larger
  was asked for.
- **"Nothing is wrong" (FR-010) is read per point from the sharing record**, so a field run
  can be judged afterwards without anyone watching. The slower times of spec 001 FR-002 still
  bound everything else.
- **The healthy drop rate of 5 an hour (FR-007, SC-003) is an informed guess.** Guests on one
  connection dropped 0–5 times an hour on 4 and 9 November. It is a target that runs report
  against, not a release gate.
- **Some players have Wi-Fi switched on and some do not**, and most halls have no Wi-Fi to
  join. Both cases must work.
- **Finding why the second connection drops is time-boxed.** The requirement is the outcome in
  FR-007 and FR-008, not the cause.
- **The system turning Bluetooth off and on by itself cannot be prevented from inside the
  app**, only recovered from (FR-009) and recorded.
- **Delay entries are times, not scores**, so they fit the record's existing privacy rules and
  7-day limit.
- **About ten players with phones and watches can be gathered** for a two-court run at a regular
  evening.
- **Matching the 95th percentile on the small run (FR-017) is trusted to predict nine
  guests.** That trust is checked on the first two-court evening (FR-018), and the limit is
  lowered if the prediction was wrong (FR-016).
- **Delays are bounded from round trips between the devices.** With no network time at
  court, there is no other clock to trust. Each device asks the devices it is linked to the
  time now and then, in a message small enough to make the round trip short, and keeps the
  narrowest bound; points then carry those bounds on. Where the bounds are still too wide, the
  delay reads unknown (FR-006, research D-2).
- **The minimum of 100 timed points per device (FR-010) is an informed default.** An hour's
  play at the field run's pace gives several hundred.
- **Nothing in this feature leaves the devices at court.** A server, account or internet relay,
  per-guest channels and Wi-Fi Aware were considered and left out (decision.md). Guests passing
  the score on to each other, and a guest taking over as host, stay out of scope.
- **Breaking changes for older versions are acceptable**, as long as FR-015 holds.
