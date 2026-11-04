# Feature Specification: Rekkert on Apple Watch SE (1st generation)

**Feature Branch**: `003-apple-watch-se-support`

**Created**: 2026-11-04

**Status**: Draft

**Input**: User description: "Lets look into what it takes to support apple watch se (1st generation)"

## Clarifications

### Session 2026-11-04

- Q: Apple Health on watchOS 10 has nowhere to save an effort rating. What happens to a
  rating for a workout recorded on such a watch? → A: Rekkert keeps it in its own workout
  history only. It is not saved to Apple Health, and Rekkert says so.

## User Scenarios & Testing *(mandatory)*

### Why the SE (1st generation) has no Rekkert today

The Apple Watch SE (1st generation), sold from 2020, cannot update past watchOS 10.6.1.
Rekkert's watch app asks for the newest watch software, watchOS 26, so the App Store never
offers it to that watch. The player's iPhone runs Rekkert normally, but everything that
depends on the watch app stays hidden: scoring from the wrist, the buzz when a timed round
ends, and recording the session as an Apple Health workout. Series 4 and Series 5 watches
stop at the same version and are left out in the same way.

### What it takes

A trial build of the current app, set to accept watchOS 10, shows the gap is small:

- **Unchanged.** The whole scoring, drawing, and syncing engine builds as it is, and so does
  nearly all of the watch app: the court and menu screens, joining a match, the Bluetooth link
  to other phones, and starting, mirroring, and saving a workout.
- **Needs an equivalent, nothing visible changes.** Two pieces use something that only exists
  in newer watch software. One is how the watch notices a timed round running out, which
  needs watchOS 26. The other is a small piece of bookkeeping inside the workout recorder,
  which needs watchOS 11. Both have watchOS 10 equivalents that behave the same for the
  player.
- **Has no watchOS 10 equivalent.** Saving the player's 1–10 effort rating to Apple Health,
  and asking Apple Health for permission to do so. Apple Health added a place for effort
  ratings in watchOS 11, so a watchOS 10 watch has nowhere to save one. On these watches the rating stays in Rekkert's own workout history
  and is not saved to Apple Health (FR-008).

Some things are outside the code. The current developer tools ship no simulator for the
SE (1st generation) or for watchOS 10, so only a real watch can show whether it works. Apple
also does not say how long a watchOS 10 watch can stay paired with an iPhone on the newest
iOS.

### User Story 1 - Score a match from an SE (1st generation) (Priority: P1)

A player whose iPhone is paired with an Apple Watch SE (1st generation) installs Rekkert. The
watch app arrives on the watch the same way it does on a newer one. They start a match on the
phone or the watch, tap points on the wrist, and the phone follows. Points tapped on the phone
show on the wrist. Every mode works from the wrist the same way it does on a current watch:
Match, Winner court (Our court and All courts), Friendly, and Americano/Mexicano.

**Why this priority**: Scoring from the wrist is the reason Rekkert has a watch app at all.
With only this story the SE (1st generation) owner already gets the core of the product, and
the story proves the app installs and runs on watchOS 10.

**Independent Test**: On a real SE (1st generation) running watchOS 10, paired with an
iPhone running the Rekkert iPhone app, install Rekkert, play a full match in each mode
tapping on both devices, and confirm both agree on every point.

**Acceptance Scenarios**:

1. **Given** an iPhone with Rekkert installed and paired with an SE (1st generation) on
   watchOS 10, **When** the player installs Rekkert or opens the Watch app's list of
   available apps, **Then** Rekkert can be installed on the watch and opens to the same
   start screen as on a current watch.
2. **Given** a match running on both devices, **When** the player taps a point on the watch,
   **Then** the phone shows the same score, server, and serve side.
3. **Given** a match running on both devices, **When** a point is tapped on the phone or
   undone there, **Then** the watch shows the same state.
4. **Given** an All courts ladder, a Friendly, or an Americano/Mexicano session, **When** it is
   played from the SE (1st generation), **Then** the watch offers and shows the same courts,
   rounds, and next-round prompts as a current watch.
5. **Given** the iPhone is left in a bag out of reach, **When** the watch keeps scoring over its
   own Bluetooth link to another phone at the court, **Then** the scores match on every device
   once they are back in contact, exactly as with a current watch.
6. **Given** a match scored across an SE (1st generation), a current watch, and two phones,
   **When** points arrive late or out of order, **Then** every device ends on the same score.

---

### User Story 2 - Record the session as an Apple Health workout (Priority: P1)

The player starts a workout on the SE (1st generation), from its menu, its idle screen, the
prompt when a match starts, or the phone's Start button. The watch shows heart rate, energy,
and heart-rate zones while they play. When they finish, the workout is saved to Apple Health
as tennis with its energy, and the summary shows up in Rekkert's Workouts list on the phone.

**Why this priority**: Recording the workout is the watch's other main job, and the
iPhone shows it as a headline feature whenever a watch with Rekkert is paired. An SE (1st
generation) that scores but cannot record would leave a visible hole.

**Independent Test**: On a real SE (1st generation), start a workout from the watch, play for
at least 30 minutes, end it, and confirm it is in Apple Health as tennis with heart rate and
energy, and in Rekkert's Workouts list on the phone. Repeat with the workout started from the
phone.

**Acceptance Scenarios**:

1. **Given** Apple Health permission has not been asked yet, **When** the player starts their
   first workout on the SE (1st generation), **Then** the permission request appears on the
   right device and, once granted, the workout starts.
2. **Given** the watch app is not open, **When** the player taps Start workout on the phone,
   **Then** the workout starts on the watch and the phone shows it as running, as on a current
   watch.
3. **Given** a workout is running and the wrist is lowered, **When** play continues for an hour,
   **Then** heart rate and energy keep being collected for the whole hour.
4. **Given** a running workout, **When** the player ends it, **Then** it is saved to Apple Health
   as tennis with active and resting energy, and its summary (duration, energy, heart rate)
   appears in Rekkert's Workouts list on the phone, as it does for a watch on watchOS 26.

---

### User Story 3 - Feel the end of a timed round on the wrist (Priority: P2)

In a timed Winner court round, every watch buzzes when the clock runs out. A player wearing an
SE (1st generation) feels the same buzz at the same moment as everyone else, and a lowered
wrist gets the notification, so nobody is left playing on after time.

**Why this priority**: This is one of the two places the trial build found an obstacle. If
nobody checks it, the SE (1st generation) would install and score but stay silent at the end
of a round, and nothing on screen would say so.

**Independent Test**: Run a short timed round with an SE (1st generation) and a current watch
on the same session. Confirm both buzz when time runs out, first with the app in front and then
with the wrist lowered.

**Acceptance Scenarios**:

1. **Given** a timed round with the Rekkert app in front on the SE (1st generation), **When**
   the countdown reaches zero, **Then** the watch buzzes and shows that time is up.
2. **Given** a timed round with the wrist lowered, **When** the countdown reaches zero, **Then**
   the notification is delivered to the watch.
3. **Given** time is added to a round after it has run out, **When** the new deadline passes,
   **Then** the watch buzzes again.

---

### User Story 4 - Rate how hard it was (Priority: P2)

When a workout ends, Rekkert asks how hard it was on a 1–10 scale, on the watch or the phone.
On a current watch the rating goes into Rekkert's workout history and into Apple Health. On an
SE (1st generation) it goes into Rekkert's workout history only, because Apple Health on
watchOS 10 has nowhere to put it. The Apple Health section in Settings says so, and the watch
does not ask for Apple Health permission to save something it never will.

**Why this priority**: This is the only part of the watch app that has no watchOS 10
equivalent. It matters less than scoring and recording, but it touches what Rekkert promises
about Apple Health, which App Review has already checked once (feature 002).

**Independent Test**: End a workout on an SE (1st generation) and give a rating on the watch.
End another and give the rating on the phone. Check that both ratings appear in the phone's
Workouts list, that Apple Health holds no rating from Rekkert for either workout, and that the
Apple Health section in Settings says ratings from this watch stay in Rekkert.

**Acceptance Scenarios**:

1. **Given** a workout just ended on an SE (1st generation), **When** the player gives a
   rating on the watch or on the phone, **Then** the workout's entry in the phone's Workouts
   list shows the rating, and Apple Health holds no effort rating from Rekkert for that
   workout.
2. **Given** an SE (1st generation) is paired, **When** the player reads the Apple Health
   section in Settings, **Then** it says that effort ratings for workouts recorded on this
   watch are kept in Rekkert and not saved to Apple Health.
3. **Given** a fresh install on an SE (1st generation), **When** the watch asks for Apple
   Health permission for the first time, **Then** the request does not ask to save or read
   effort ratings.

---

### User Story 5 - Keep the SE (1st generation) working after this release (Priority: P3)

Later changes to Rekkert should not quietly drop the SE (1st generation). If a change would
make the watch app need newer watch software, or would use something watchOS 10 does not have
without a fallback, it is caught before it merges.

**Why this priority**: A watch app that stops being offered to a watch fails without any
error. The players affected just stop seeing it, and nobody on a newer watch would notice.
Without this story the support would likely be lost again within a few releases.

**Independent Test**: On a scratch change, raise the watch app's minimum watch software, or use
a capability that exists only in newer watch software. Confirm the verification gate fails and
says why.

**Acceptance Scenarios**:

1. **Given** a change that raises the watch app's minimum watch software above watchOS 10,
   **When** the verification gate runs, **Then** it fails and names the problem.
2. **Given** a change to the watch app that uses something only newer watch software has,
   without a fallback, **When** the verification gate runs, **Then** it fails.

---

### Edge Cases

- **A watch on an earlier watchOS 10 release** (one that never updated to 10.6.1): supported
  the same as 10.6.1, as long as it can install the app.
- **Series 4 and Series 5**: they run the same watchOS 10 and are offered the app too. They get
  the same behaviour as the SE (1st generation), but they are not separately verified unless
  one is at hand.
- **iPhone on an iOS release older than the iPhone app requires** (for example an iPhone XS
  stuck on iOS 18): the iPhone app cannot be installed, so the watch app cannot be either. Out
  of scope; nothing changes for that player.
- **Phone and watch on different app versions** during a staggered update: the same rules apply
  as between a phone and a current watch today. Neither side may misread the other's scores.
- **Effort rating given on the phone** for a workout recorded on an SE (1st generation): kept in
  Rekkert's history only, the same as a rating given on the watch. The phone does not try to
  save it to Apple Health instead.
- **The player later moves to a watch on watchOS 11 or later**: ratings for workouts recorded
  on the new watch go to Apple Health as they do today. Ratings already given on the SE (1st
  generation) stay in Rekkert only and are not copied into Apple Health afterwards.
- **A workout started from the phone while the SE (1st generation) is locked or off the wrist**:
  the phone says the workout did not start, as it does for a current watch today (the recent
  fix for phone-started workouts must hold on watchOS 10 too).
- **A match drawn on one device and followed on the SE (1st generation)**: the watch takes the
  draw as sent. It must never draw a different round, and the player must never wait longer to
  see it than on a current watch.
- **Slower hardware**: on a long tournament with many rounds in history, the watch must stay
  usable. Opening the menu and taking a point must not visibly lag compared with short
  sessions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Rekkert watch app MUST be offered for, and installable on, an Apple Watch
  SE (1st generation) running any watchOS 10 release, when it is paired with an iPhone that
  can run the Rekkert iPhone app.
- **FR-002**: On an SE (1st generation), the watch app MUST offer everything it offers on a
  current watch. The only exception is the effort rating (FR-008) and the Apple Health wording
  that follows from it (FR-009).
- **FR-003**: Scores, rounds, and draws MUST stay in step between an SE (1st generation), the
  paired phone, and every other device in the session, with the same guarantees as for a
  current watch: devices that have seen the same events show the same state, and a late event
  never re-partners or redraws a round that has started.
- **FR-004**: The SE (1st generation) MUST keep following a match over its own Bluetooth
  link when its iPhone is out of range, as a current watch does.
- **FR-005**: An SE (1st generation) MUST be able to record a workout from every place a
  current watch can start one (watch menu, idle screen, match-start prompt, the phone's Start
  button). It MUST keep collecting heart rate and energy with the wrist lowered, and save the
  workout to Apple Health as tennis with active and resting energy.
- **FR-006**: The phone MUST show workouts recorded on an SE (1st generation) in its Workouts
  list with the same summary as one from a watch on watchOS 26: duration, energy, and heart
  rate. The watch MUST place the live heart rate in zones when the player's age is in Apple
  Health. The time spent in each zone comes from Apple Health only on watchOS 27 and later,
  so it is absent here, just as it is on a watchOS 26 watch today.
- **FR-007**: When a timed round runs out, the SE (1st generation) MUST buzz and show that time
  is up if the app is in front, and MUST receive the time-up notification if the wrist is
  lowered, at the same moment as a current watch.
- **FR-008**: An effort rating given for a workout recorded on an SE (1st generation), on the
  watch or on the phone, MUST be kept in Rekkert's own workout history and shown there as for
  any other workout. It MUST NOT be saved to Apple Health by any device. The player MUST still
  be asked for a rating when the workout ends, as on a current watch.
- **FR-009**: What Rekkert tells the player about Apple Health MUST be accurate for an SE (1st
  generation): the Apple Health section in Settings, the text on workout controls, and the
  watch's Apple Health permission request. It MUST NOT claim or ask permission to save or read
  anything the watch does not, and it MUST say that effort ratings from this watch stay in
  Rekkert.
- **FR-010**: Supporting the SE (1st generation) MUST NOT remove or degrade anything on
  current watches. Players on watchOS 26 or later MUST see no change in behaviour.
- **FR-011**: Every watch screen MUST be legible and fully usable on the 40 mm and 44 mm SE
  (1st generation) screens, which have no always-on display, using that watch's own system
  look.
- **FR-012**: The project's verification gate MUST fail when a change raises the watch app's
  minimum watch software above watchOS 10, or uses a watch capability that watchOS 10 lacks
  without a fallback.
- **FR-013**: The README MUST name watchOS 10 as the watch app's minimum and mention the SE
  (1st generation). The App Store's compatibility line, which the store derives from the
  build, MUST read watchOS 10. The privacy page and the App Review notes MUST stop saying
  every watch saves the effort rating to Apple Health.

### Key Entities

- **Supported watch range**: the oldest watch software the watch app accepts (watchOS 10). In
  practice this decides which watches can have Rekkert: SE (1st generation), Series 4, Series 5,
  and everything newer.
- **Workout effort rating**: the player's 1–10 answer to "how hard was it", tied to one recorded
  workout. For a workout recorded on a current watch it lives in Rekkert's own workout
  history and in Apple Health. For one recorded on a watchOS 10 watch it lives in Rekkert's
  history only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a real SE (1st generation) running watchOS 10, a tester installs Rekkert and
  plays a full match in every mode from the wrist with no step that fails or needs a
  workaround.
- **SC-002**: Across a full best-of-three match tapped on the SE (1st generation), the phone
  shows every point, with no point missing, doubled, or out of order, and each one appears
  on the phone within 2 seconds of the tap.
- **SC-003**: On the SE (1st generation), the score on the wrist changes within half a second
  of a tap, at the start of a session and after 20 rounds of a tournament.
- **SC-004**: Three workouts of at least 30 minutes recorded on the SE (1st generation), at
  least one started from the phone, all reach Apple Health as tennis with heart rate and energy,
  and all show up in Rekkert's Workouts list on the phone.
- **SC-005**: At the end of a timed round, the SE (1st generation) buzzes within 2 seconds of a
  current watch on the same session, with the app in front and with the wrist lowered.
- **SC-006**: Starting from a full charge, an SE (1st generation) still has at least 40% battery
  after a 2-hour session scored on the wrist with a workout recording throughout.
- **SC-007**: On a current watch, a full regression pass (scoring, workout, timed round, effort
  rating) shows no difference from the release before this change.
- **SC-008**: A deliberate trial change that drops watchOS 10 support makes the verification
  gate fail, and the failure message names the problem.
- **SC-009**: For three workouts recorded on the SE (1st generation) and rated, at least one on
  the phone, all three ratings appear in the phone's Workouts list and none appear in Apple
  Health.

## Assumptions

- "Apple Watch SE (1st generation)" means the 2020 model, in 40 mm and 44 mm, GPS and cellular.
  Apple lists watchOS 10.6.1 as its last version.
- Support is defined by watch software, not by model. Accepting watchOS 10 also brings in
  Series 4 and Series 5, which stop at the same version. They are welcome but not a verification
  target.
- The iPhone side keeps its current requirement (iOS 26). Supporting iPhones that cannot reach
  it, such as the iPhone XS and XR on iOS 18, would be a separate and much larger project.
- Apple publishes no maximum iOS version for a watchOS 10 watch. Community reports say an
  SE (1st generation) still pairs with iPhones on iOS 26, with occasional trouble. Rekkert
  cannot affect pairing, and verification uses a pair that works.
- On watchOS 10 the watch app takes that system's look rather than the newest one. Nothing
  needs to imitate newer system styling, only stay legible and usable (FR-011).
- The SE (1st generation) has the same screen sizes and the same lack of an always-on display
  as the SE (2nd generation), which Rekkert already supports. Layout and wrist-down behaviour
  are therefore known territory. Its older chip is the main hardware difference, hence SC-003
  and SC-006.
- The current developer tools have no SE (1st generation) or watchOS 10 simulator. A physical
  SE (1st generation) on watchOS 10 is assumed to be available for verification, and simulator
  builds on current watches still cover everything else. Whether the current tools can install
  and debug directly on a watchOS 10 watch has not been confirmed. If they cannot, a TestFlight
  build is the fallback.
- The way devices exchange events and draws does not need to change. The SE (1st generation)
  runs the same engine as every other device, so convergence (constitution Principle II) holds
  without new rules, and FR-003 checks it.
- The trial build's findings (one place with no equivalent, two with equivalents) reflect the
  code as of the `main` commit this branch started from. Anything added to the watch app since
  must be checked again during planning.
