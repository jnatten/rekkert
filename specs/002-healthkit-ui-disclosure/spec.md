# Feature Specification: Name Apple Health Wherever Rekkert Uses It

**Feature Branch**: `002-healthkit-ui-disclosure`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "I want to make this app pass review stage in app-store. I submitted build 70 for review and i got this feedback: Guideline 2.5.1 - Performance - Software Requirements. Issue Description: The app uses the HealthKit or CareKit APIs but does not clearly identify the HealthKit and CareKit functionality in the app's user interface. Apps using these APIs should be clearly indicated to provide transparency and valuable information to users. Next Steps: To resolve this issue, it would be appropriate to clearly identify the HealthKit and CareKit functionality in the app's user interface. If the app already clearly identifies the HealthKit and CareKit functionality in the app's user interface, reply to this message and provide a screen recording on a physical device showing where this identification can be found. Include the recording in the Notes field of the App Review Information section in App Store Connect for future submissions. Help me achieve this."

## User Scenarios & Testing *(mandatory)*

### The rejection this starts from

Build 70 was rejected under App Store guideline 2.5.1: the app uses Apple Health but, as far
as the reviewer could see, never says so on screen. Apple offers two ways out: identify the
Apple Health functionality in the app, or reply with a screen recording on a physical device
showing where it already is, and keep that recording in the review notes for every later
submission.

Rekkert's Apple Health use is real and narrow. A workout the player starts is recorded on the
Apple Watch and saved to Apple Health as indoor tennis, with the active and resting energy it
burned and an effort rating if they give one. While it runs, and once more when it ends, the watch reads heart rate and active and
resting energy; it also reads date of birth and the latest resting heart rate to place the
heart rate in zones. Nothing is read unless a workout is started.

What a reviewer sees today depends entirely on having an Apple Watch:

- On an iPhone with a paired Apple Watch that has Rekkert, the main menu has a Workout
  section whose footnote says the workout is saved "to Health", Settings has "Workout on your
  watch", and History gains a Workouts list once one has been recorded.
- On an iPhone with no paired Apple Watch, and on every iPad, all of that is hidden. There is
  not a single mention of Health anywhere in the app.
- On the watch, Start workout says nothing about Health at all.
- Where it is mentioned, it is called "Health", never "Apple Health", and the Apple Health
  icon appears nowhere.

The most likely reading of the rejection is that the reviewer had no paired watch, or used an
iPad, and so never saw any of it. The fix therefore has to work without a watch.

### User Story 1 - Anyone can find what Rekkert does with Apple Health, watch or no watch (Priority: P1)

A reviewer installs Rekkert on an iPhone with no Apple Watch paired, or on an iPad, opens
Settings, and finds a section called Apple Health, with the Apple Health icon. It says, in a
few plain sentences, that Rekkert can save the workouts an Apple Watch records to Apple
Health, what it saves and what it reads, that it reads only while a workout the player
started is running, that the data stays on the player's own devices, and that recording a
workout needs an Apple Watch paired with an iPhone. It also says where to review or turn off
Rekkert's access. The same section is there, with the same content, for a player who does
have a watch.

**Why this priority**: This is the one change that makes the Apple Health use visible to a
reviewer regardless of the hardware they test on. On its own it is likely enough to clear
2.5.1, and it is the anchor every other story and the review notes point to.

**Independent Test**: Fresh install on an iPhone with no paired Apple Watch, and on an iPad.
From the start screen, open Settings: the Apple Health section is there, with the icon, and
answers what is saved, what is read, when, where it goes, and where to change access.

**Acceptance Scenarios**:

1. **Given** a fresh install on an iPhone with no paired Apple Watch, **When** the user opens
   Settings, **Then** an Apple Health section with the Apple Health icon is shown, and it says
   that recording a workout needs a paired Apple Watch.
2. **Given** a fresh install on an iPad, **When** the user opens Settings, **Then** the same
   Apple Health section is shown, and it says workouts are recorded by an Apple Watch paired
   with an iPhone.
3. **Given** an iPhone with a paired Apple Watch, **When** the user opens Settings, **Then**
   the Apple Health section is shown alongside the existing "Workout on your watch" settings.
4. **Given** the Apple Health section and the page it opens, **When** the user reads them,
   **Then** they list what is
   saved to Apple Health (workouts as indoor tennis, with their active and resting energy,
   and effort ratings), what is read (heart
   rate, active and resting energy, resting heart rate, date of birth, and Rekkert's own
   workouts and ratings), and when (only while a workout the player started is running, and
   once when it ends).
5. **Given** the Apple Health section, **When** the user wants to change Rekkert's access,
   **Then** the section tells them where to do it.

---

### User Story 2 - Every workout control and prompt says it goes to Apple Health (Priority: P1)

A player with an Apple Watch starts a workout from the iPhone's menu, from a match's menu,
from the watch's menu page or its idle screen, or answers "Start a workout?" when a match
starts. Each of these says, on the control or right beside it, that the workout is saved to
Apple Health, using the name "Apple Health" and, where there is room, the icon. Screens that
show what came out of Apple Health — the Workouts list, a workout's page, the heart rate on a
match's timeline, the watch's workout page — say so too.

**Why this priority**: Guideline 2.5.1 asks for the functionality to be identified in the
interface, not only in one settings screen. A reviewer who does have a watch will look at
the controls that trigger it, and today those never name Apple Health.

**Independent Test**: On an iPhone with a paired Apple Watch, walk through every place a
workout can be started or is shown and confirm each names Apple Health on that screen.

**Acceptance Scenarios**:

1. **Given** the iPhone's main menu Workout section, **When** it is shown, **Then** it names
   Apple Health and shows the Apple Health icon.
2. **Given** a match's menu offers Start workout, **When** it is shown, **Then** the
   option or its subtitle says the workout is saved to Apple Health.
3. **Given** the watch's menu page or idle screen shows Start workout, **When** it is shown,
   **Then** Apple Health is named on or directly beside the button.
4. **Given** Settings has a match start or end set to ask, **When** "Start a workout?" is
   shown on the phone or the watch, **Then** its message says the workout is saved to Apple
   Health.
5. **Given** the Workouts list or a workout's page, **When** it is shown, **Then** it says the
   workout is in Apple Health.
6. **Given** a filed match shows the heart rate from a workout, **When** the chart is shown,
   **Then** it says the heart rate came from Apple Health.

---

### User Story 3 - Rekkert explains itself before Apple Health asks for access (Priority: P2)

The first time a player chooses something that needs Apple Health — pressing Start workout,
or setting a match start to Ask me or Start workout — Rekkert shows a short explanation of
its own before the system's permission request: what it is about to ask for, why, and that
nothing is read unless a workout is running. The player continues to the system request or
backs out. The watch does the same the first time it needs to ask. The system request's own
text also names Apple Health.

**Why this priority**: Reviewers regularly check that the permission request makes sense in
context, and a request that appears with no lead-in is the moment a player most wonders what
an app is up to. It strengthens the case, but the identification in stories 1 and 2 is what
2.5.1 asks for.

**Independent Test**: On a fresh install with a paired Apple Watch, press Start workout on
the phone, and separately on the watch: an explanation from Rekkert appears before the
system's Apple Health request, and backing out of it leaves no request shown and no workout
started.

**Acceptance Scenarios**:

1. **Given** Rekkert has never asked for Apple Health access on this device, **When** the
   player presses Start workout, **Then** Rekkert's explanation appears before the system
   request.
2. **Given** the explanation is shown, **When** the player backs out, **Then** no system
   request is shown, no workout starts, and the explanation appears again next time.
3. **Given** the explanation is shown, **When** the player continues, **Then** the system
   request appears, and its text names Apple Health.
4. **Given** Rekkert has already asked once on this device, **When** the player presses
   Start workout, **Then** no explanation appears and the workout starts as it does today.
5. **Given** a start was handed to the watch from the phone while the watch app was not on
   screen, **When** the watch app is next opened and still needs to ask, **Then** the watch
   shows its explanation before the system request.

---

### User Story 4 - The next submission carries the proof (Priority: P2)

The developer submits the next build with review notes that tell the reviewer exactly where
to find Apple Health in the app, starting with the Settings section that needs no watch, and
with a screen recording made on a physical iPhone and Apple Watch that walks through every
place it is named. The same notes and recording go with every later submission.

**Why this priority**: Apple asked for the recording explicitly, and notes that lead the
reviewer straight to the Apple Health section remove the chance that the next reviewer, too,
tests without a watch and finds nothing.

**Independent Test**: Hand the review notes to someone who has never used Rekkert, with an
iPhone and no watch; following the notes alone, they reach the Apple Health section on the
first try. Watch the recording and tick off every location the notes list.

**Acceptance Scenarios**:

1. **Given** the review notes, **When** a reviewer without an Apple Watch follows them,
   **Then** they reach the Apple Health section in Settings.
2. **Given** the review notes, **When** a reviewer with an Apple Watch follows them, **Then**
   they can start a workout, see Apple Health named at each step, and find the workout in the
   Health app afterwards.
3. **Given** the screen recording, **When** it is played, **Then** it shows, on a physical
   iPhone and Apple Watch: the Apple Health section in Settings, starting a workout from the
   phone and from the watch with Apple Health named, the explanation before the permission
   request, the workout in Rekkert's Workouts list, and the same workout in the Health app.
4. **Given** the App Store listing, **When** it is read, **Then** it still names Apple Health
   in the Workouts and Privacy paragraphs.

---

### Edge Cases

- **No paired Apple Watch, or a paired watch without Rekkert**: the Apple Health section is
  shown and says a watch is needed; the workout controls stay hidden, as today, rather than
  shown and doing nothing.
- **iPad**: the Apple Health section is shown; nothing else changes, since an iPad cannot
  pair a watch.
- **Apple Health not available on the device at all** (for example restricted by device
  management): the section still explains what Rekkert would do and says Apple Health is not
  available on this device.
- **Access turned down, in part or in full**: Apple Health does not tell an app whether a
  read was allowed, so the section does not claim to know; it says where to check. A start
  that fails because saving is not allowed names Apple Health in its message and says where
  to turn access on.
- **Player who never uses workouts**: the section is there but nothing is ever asked of
  Apple Health, exactly as today; reading Settings does not trigger a permission request.
- **VoiceOver and larger text**: the Apple Health icon is announced as "Apple Health", and
  the section and every caption added by this feature remain readable at the largest text
  sizes and on the smallest supported watch.
- **Light and dark appearance**: the icon follows Apple's rules for both.
- **Demo and screenshot launches**: the Apple Health section appears in them as it would on
  a real device, so App Store screenshots and the recording can show it.
- **Older watch app build paired with a newer phone app, or the other way round**: each side
  shows its own identification; nothing here travels between the devices.

## Requirements *(mandatory)*

### Functional Requirements

**Apple Health section (iPhone and iPad)**

- **FR-001**: Settings MUST include a section named "Apple Health", shown on every iPhone and
  iPad whether or not an Apple Watch is paired, a workout has been recorded, or access has
  been asked for.
- **FR-002**: The section MUST show the Apple Health icon beside its name, using Apple's own
  artwork as Apple's guidelines allow.
- **FR-003**: The section, or the page it opens, MUST say, in plain language: what Rekkert saves to Apple Health
  (workouts, as indoor tennis, with their active and resting energy, and effort ratings);
  what it reads (heart rate, active and
  resting energy, resting heart rate, date of birth, and its own workouts and ratings); that
  it reads only while a workout the player started is running and once when it ends; why it
  reads date of birth and resting heart rate (to place heart rate in zones); and that
  nothing read from Apple Health leaves the player's own iPhone and Apple Watch.
- **FR-004**: The section MUST say that recording a workout needs an Apple Watch paired with
  the iPhone, and, on a device where workouts cannot be recorded, why not (no paired watch,
  watch without Rekkert, iPad, or Apple Health unavailable).
- **FR-005**: The section, or the page it opens, MUST tell the player where to review or turn off Rekkert's Apple
  Health access in the system's own settings. It MUST NOT offer switches of its own that
  change what flows to or from Apple Health.
- **FR-006**: Opening or reading the section or its page MUST NOT trigger an Apple Health permission
  request.

**Naming Apple Health at the point of use**

- **FR-007**: Every control that starts a workout — the iPhone main menu, a match's menu, the
  watch's menu page and its idle screen — MUST name Apple Health on the control or directly
  beside it.
- **FR-008**: The iPhone main menu's Workout section MUST show the Apple Health icon.
- **FR-009**: Every "Start a workout?" prompt, on the phone and on the watch, MUST say the
  workout is saved to Apple Health.
- **FR-010**: The "Workout on your watch" settings MUST say that the workouts they start are
  saved to Apple Health, and MUST point to the Apple Health section.
- **FR-011**: The Workouts list, a workout's page, the heart-rate chart on a filed match, and
  the watch's workout page MUST each say that the workout or heart rate is from, or saved
  in, Apple Health.
- **FR-012**: Messages about Apple Health access failing, on either device, MUST name Apple
  Health and say where to turn access on.
- **FR-013**: User-facing text MUST call the service "Apple Health", or "the Apple Health
  app" when it means the app itself, as Apple's guidelines ask; bare "Health" and
  "HealthKit" MUST NOT be used for it. A system menu quoted as a path to follow, such as
  "Settings › Privacy & Security › Health", keeps the system's own names.
- **FR-014**: The in-app help MUST describe the Apple Health integration, and every help
  entry that mentions it MUST use the same name.

**Before the permission request**

- **FR-015**: The first time on a device that Rekkert would ask Apple Health for access, it
  MUST first show its own explanation of what it will ask for and why, with a way to continue
  to the system request and a way to back out. The explanation MUST NOT repeat the system
  request's own choices (no per-item switches), so it never reads as a second permission
  screen.
- **FR-016**: Backing out MUST leave no system request shown, no workout started and no
  setting changed, and the explanation MUST appear again the next time.
- **FR-017**: Once the system request has been shown on a device, the explanation MUST NOT
  appear again on that device, unless Apple Health cannot report whether it has asked. In
  that case Rekkert explains again, rather than risk asking with no lead-in.
- **FR-018**: The text in the system's Apple Health permission request, on the phone and on
  the watch, MUST name Apple Health and say what is saved and what is read.

**No change to what is collected**

- **FR-019**: The data Rekkert saves to and reads from Apple Health, when it does so, and
  where that data goes MUST be unchanged by this feature.

**Submission**

- **FR-020**: The review notes MUST list, for a device without an Apple Watch and for one
  with, the exact path to every place Apple Health is identified, starting with the Settings
  section.
- **FR-021**: A screen recording made on a physical iPhone with a paired Apple Watch MUST
  show every location the review notes list, the explanation before the permission request,
  and the recorded workout in the Health app; it MUST be attached to the App Review
  Information and kept there for later submissions.
- **FR-022**: The App Store description MUST continue to name Apple Health, and the
  description, the review notes, the privacy page and the Apple Health section MUST NOT
  contradict each other about what is saved or read.

### Key Entities

- **Apple Health disclosure**: the single statement of what Rekkert saves to Apple Health,
  what it reads, when, why, and where it goes. The Settings section, the permission request
  text, the review notes, the App Store description and the privacy page all say the same
  thing in their own length.
- **Identification point**: a place in the app where Apple Health is named — its screen,
  device, how it is reached, and whether it needs an Apple Watch. The review notes and the
  recording are built from the full list of them.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The next build submitted is not rejected under guideline 2.5.1 for Apple Health
  identification.
- **SC-002**: On a fresh install on an iPhone with no Apple Watch and on an iPad, a person who
  has never used Rekkert finds a screen naming Apple Health and saying what Rekkert does with
  it within 30 seconds, and within two taps of the start screen.
- **SC-003**: Every screen that starts a workout, asks whether to start one, asks for Apple
  Health access, or shows data from Apple Health names Apple Health on that screen: 100% of
  the identification points, checked one by one.
- **SC-004**: No first-time Apple Health permission request, on the phone or the watch,
  appears without Rekkert's own explanation immediately before it.
- **SC-005**: The set of data Rekkert saves to and reads from Apple Health is identical
  before and after the change.
- **SC-006**: Someone following the review notes alone reaches the Apple Health section on
  the first try, without an Apple Watch.
- **SC-007**: The screen recording shows every identification point in under three minutes.

## Assumptions

- The reviewer of build 70 most likely tested without a paired Apple Watch or on an iPad,
  where today the app shows no sign of Apple Health. Identification that does not depend on a
  watch is therefore the core of the fix.
- "CareKit" in the rejection is standard wording; Rekkert does not use CareKit and nothing
  needs to change for it.
- Apple's Human Interface Guidelines allow the Apple Health icon inside the app to show it
  works with Apple Health, provided it is Apple's own artwork, sits beside the name "Apple
  Health", keeps clear space around it, and is never used as a button or in place of words.
  The "Works with Apple Health" badge is for marketing, not the app, and is not used here.
- The app's text is English only; no other languages are in scope.
- The workout controls stay hidden where no workout can be recorded, as today. The Apple
  Health section is what explains their absence.
- The privacy page already describes the Apple Health use in detail and needs at most a
  wording check against the Settings section.
- The App Store description already names Apple Health; it is kept, not rewritten.
- The screen recording is made by the developer on their own iPhone and Apple Watch; it
  cannot be produced by an automated test.
- The fix ships in the next build after 70, through the usual TestFlight release, with the
  review notes and the recording added by hand in App Store Connect.
- Session sharing work (`001-fix-session-sharing`) is changing the watch's menu page in
  parallel. The watch requirements here apply to the menu page as it stands when both are
  merged.
- Out of scope: new kinds of Apple Health data, reading workouts recorded by other apps,
  recording workouts without a watch, and any workout features on iPad.
