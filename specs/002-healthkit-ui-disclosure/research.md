# Research: Name Apple Health Wherever Rekkert Uses It

**Feature**: `002-healthkit-ui-disclosure` | **Date**: 2026-10-27

## Why build 70 was rejected

All of this was checked in the code at `rtxlwlsn`, the base of this branch.

- **R-1: Nothing mentions Health without a paired watch.** `WorkoutController.isAvailable` on
  the phone (`App/Sources/WorkoutController.swift`) is true only when Health is available
  *and* a watch is paired *and* Rekkert is installed on it. These are gated on it:
  - the Home Workout section (`HomeView`);
  - the workout items in a match's menu (`MatchOptionsMenu`);
  - "Workout on your watch" in Settings (`SettingsView`, also behind `canPairWatch`).

  The Workouts row appears only once a workout exists, and the timeline's heart-rate hint
  needs `canPairWatch`. On an iPhone without a watch, or on any iPad, no screen mentions
  Health.
- **R-2: It says "Health", never "Apple Health".** That applies to the three places the
  phone mentions it: the Home Workout footer, the Workouts footer, and the workout page's
  "Worked out by Health". The watch's failure text says "Health access is off for Rekkert".
  The help says "in Health" and "saves it to Health". The Apple Health icon appears nowhere.
- **R-3: The watch's Start workout never names Health.** That covers the menu page, the idle
  screen and the result screen (`WatchWorkoutButton`). "Start a workout?" on both devices
  says only "It runs on your watch while you play" (phone) or nothing (watch).
- **R-4: The permission request has no lead-in.** On the phone it comes on the first Start
  workout press, or on choosing a start in Settings (`prepare()`). On the watch it comes on
  the first press or whenever the app opens with a start set (`Shared/AppModel.swift`,
  `prepare()` and `writeWaitingRatings()`).
- **R-5: The App Store description and privacy page already name Apple Health.** The review
  notes describe the workouts under "WORKOUTS (HEALTHKIT)", but they never say where in the
  app to look, nor that a watch is needed to see any of it.

Most likely the reviewer used a device with no paired watch (R-1) and never saw R-2 or R-3
at all.

## What other developers found

Developer Forums threads on the same rejection
([813897](https://developer.apple.com/forums/thread/813897),
[802626](https://developer.apple.com/forums/thread/802626)) show three things:

- **Explanations alone were rejected again.** A permission primer, a "sourced from Apple
  Health" label and a mention in the description did not clear it.
- **The one reported approval had a persistent place.** That developer added an Apple Health
  place in the app's settings, with its permission request, plus an indicator in the main
  interface.
- **App Review only repeats the boilerplate.** The fix has to be unmistakable without
  further guidance from them.

That points at a persistent, always-visible Apple Health place in Settings (D-1), not at
onboarding or one-off prompts.

## Apple's rules that constrain the design

From the HIG's HealthKit page
([JSON source](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/healthkit.json)):

- **Icon**:
  - Use only Apple's artwork, from Apple Design Resources.
  - Show the name *Apple Health* close to it, with clear space of 1/10 of its height.
  - Never use it as a button, inside text, or in place of the words.
  - Don't mask, tint, border or composite it. In a row of icons, it is no smaller than the
    others.
- **Wording**: refer to "Apple Health" or "the Apple Health app". Don't say "HealthKit" to
  users. It is two words, both capitalised.
- **Permission**:
  - Ask only when needed, in context.
  - Explain in the system sheet's purpose strings.
  - Don't add custom screens that replicate the standard permission screen's behaviour or
    content.
- **Privacy**:
  - Manage sharing only through the system's privacy settings. Don't build screens in the
    app that affect the flow of health data.
  - After access is granted, show people how their data is used.

## Decisions

### D-1: An Apple Health section in Settings, on every iPhone and iPad

- **Decision**: Settings gains an Apple Health section, shown unconditionally. It sits
  after the watch-only sections, directly below "Workout on your watch" where that shows,
  and before the build label. That keeps it outside the `canPairWatch` and `isAvailable`
  gates, and on a phone without a watch it ends the list.
  - **Header**: the icon beside the name, through `AppleHealthMark` (D-3). The header is not
    interactive, so the icon is never a button.
  - **Body**: a two-sentence summary from `HealthDisclosure`, and the device's reach line
    from `HealthReach` (D-4).
  - **A row, "What Rekkert saves and reads"**: opens `AppleHealthView`. That page carries the
    mark again at the top, then sections for what is saved, what is read, when, why, where it
    goes, and "Change access" with the system path (D-12).

  It is reached in two taps from Home: the gear, then the row (SC-002). The summary and mark
  are there after one.
- **Rationale**: This is the one surface a reviewer can reach on any hardware, and the
  forums show a persistent settings place clears the rejection. Keeping the long list on its
  own page keeps Settings readable.
- **Alternatives considered**:
  - **The whole disclosure inline in Settings**: rejected as a wall of text in a screen
    people visit for toggles.
  - **A row on Home**: rejected. Home is for playing, and a row that does nothing for most
    people is clutter.
  - **Onboarding**: rejected. Rekkert has none, a one-time screen is not persistent, and the
    forums show onboarding alone failed.
  - **Putting the section first in Settings**: rejected as pushing the everyday settings
    down for a reviewer's sake. The review notes give the exact path instead (D-10).

### D-2: One disclosure, in `RekkertCore`, that the requests are built from

- **Decision**: `HealthDisclosure` is a platform-free value in `RekkertCore/Health/`. It
  lists every kind of Apple Health data Rekkert touches (`HealthData`), each with its words,
  why it is used, and whether it is saved, read, or both, per device. The phone and watch
  `WorkoutController`s build their `toShare`/`read` sets by mapping these kinds to HealthKit
  types in an exhaustive `switch`, instead of their own literal sets. Adding a kind without
  wording, or a type without a kind, then fails to compile.

  Today's sets, unchanged:
  - **Phone saves**: workouts only (needed to hand a start to the watch). It reads nothing.
  - **Watch saves**: workouts, active energy, resting energy and effort.
  - **Watch reads**: heart rate, active energy, resting energy, resting heart rate, date of
    birth, workouts and effort.

  `HealthDisclosureTests` pins both lists exactly. That is the guard behind FR-019 and SC-005:
  a change to what is collected has to change a test, in plain sight.
- **Rationale**: FR-022 asks that the description, notes, page and requests never contradict
  each other. A single list that the requests are built from makes the in-app words true by
  construction (Principle I).
- **Alternatives considered**:
  - **Words in the views, sets in the controllers**: rejected. That is how it is today, and
    it already lags: the help says the watch "records a tennis workout in Health" but not
    that it reads date of birth.
  - **The disclosure as a string catalogue only**: rejected. It cannot be tested against the
    request.

### D-3: Apple's icon, added by hand, drawn only through one non-interactive view

- **Decision**: The developer downloads the Apple Health icon from Apple Design Resources
  (Technologies section), accepting Apple's terms. They add it, unaltered, as
  `AppleHealth.imageset` in both `App/Resources/Assets.xcassets` and
  `WatchApp/Resources/Assets.xcassets`. Apple ships it as a 1920×1920 PNG, which goes in as
  one universal, single-scale image.

  `AppleHealthMark` draws it:
  - beside the text "Apple Health", with padding of a tenth of its height;
  - at no less than the size of the line it sits on;
  - as one accessibility element labelled "Apple Health";
  - with no clip shape, tint or shadow.

  It is used only in non-interactive places: the Settings section header, the top of
  `AppleHealthView`, the Home Workout section header, and both explainers. Everywhere else,
  the name is written out. `verify.sh` asserts the imageset holds an image in both catalogs
  (D-7), so a missing manual step fails the gate rather than shipping a blank space.
- **Rationale**: These are the HIG's icon rules, and only Apple's artwork may be used. It
  cannot be fetched by the build or by an agent, because downloading it means accepting
  Apple's terms. It is not an SF Symbol, so `HelpTests`' symbol scan does not see it and no
  waiver is needed.
- **Alternatives considered**:
  - **An SF Symbol heart in its place**: rejected. The HIG forbids imitating the icon, and a
    reviewer looks for the real one.
  - **The icon inside the Start workout button or the Settings row**: rejected, because the
    icon must not be a button.
  - **No icon at all, name only**: viable, but weaker. The icon is the most recognisable
    signal of the integration, and the forums suggest weak signals were not enough.

### D-4: `HealthReach`: can this device record a workout, and if not, why

- **Decision**: A `RekkertCore` function takes four inputs:
  - whether Apple Health is available;
  - whether this device can pair a watch at all (an iPad cannot);
  - whether a watch is paired;
  - whether Rekkert is on it.

  It returns one of: `.canRecord`, `.unavailable` (Apple Health off or restricted),
  `.cannotPair` (iPad), `.noWatch`, `.watchAppMissing`. Each comes with the sentence the
  Settings section shows. On the phone, `isAvailable` becomes `reach == .canRecord`, the same
  truth as today.
- **Rationale**: FR-004 needs the reason shown, and the iPad, no-watch and no-app cases need
  different words. As a pure function it is tested for every combination (Principle III),
  and the workout controls' gate stays exactly as it was.
- **Alternatives considered**: deciding the sentence in `SettingsView`. Rejected under
  Principle I: it is a rule, and the help and review notes need the same cases.

### D-5: Explain before the first request, only while Apple Health would show its sheet

- **Decision**: Before any request, the controller asks Apple Health,
  through `getRequestStatusForAuthorization(toShare:read:)`, with the exact sets that device
  is about to ask for. The result is mapped into `HealthAsk.Status`
  (`.wouldAsk`, `.alreadyAsked`, `.unknown`), and the pure rule `HealthAsk.explainFirst(_:)`
  returns `true` for `.wouldAsk` and `.unknown`.
  - **When it returns true**, the device shows its explainer: the mark, "Rekkert works with
    Apple Health", two or three sentences from `HealthDisclosure`, and Continue / Not now.
    There are no per-item switches. Continue goes on to the system request; Not now changes
    nothing.
  - **Phone, Start workout** (Home, a match's menu, or answering "Start a workout?"): the
    explainer is a sheet; Not now starts nothing.
  - **Phone, Settings picker set to Ask me or Start workout**: same sheet. The new value is
    stored only on Continue, so Not now leaves the setting, and the watch, as they were
    (FR-016).
  - **Watch, Start workout press, the automatic start, and the ask on opening the app**
    (`AppModel`): the explainer is a full-screen sheet. Not now leaves everything as it was,
    and it asks again next time.
  - **Once the system sheet has been shown**, Apple Health reports `.unnecessary`, so the
    explainer never appears again on that device (FR-017). Deleting the app resets both
    together.
- **Rationale**: This meets FR-015 to FR-017 and SC-004 with no stored flag that could
  disagree with Apple Health's own record. Treating `.unknown` as "explain" errs toward never
  showing a first request without a lead-in. It is only one extra screen, and only on the
  rare query error. One screen with no switches keeps within the HIG's "don't replicate the
  permission screen".
- **Alternatives considered**:
  - **A UserDefaults "explained" flag**: rejected. It survives an Apple Health reset it
    should not, and is lost on reinstall when the sheet would show again.
  - **Purpose strings only**, the HIG's minimum: kept (D-7), but not enough alone. The spec
    asks for Rekkert's own lead-in, and the forums show reviewers check for one.
  - **Explaining at launch**: rejected. The HIG says ask in context, and Rekkert's promise is
    that someone who never starts a workout is never asked.

### D-6: Naming Apple Health at the point of use

- **Decision**: Every identification point and its exact words are listed in
  [contracts/identification-points.md](contracts/identification-points.md). The patterns:
  - **Buttons**: a subtitle or caption beside them reads "Saves to Apple Health". This covers
    a match's menu (a `Button` whose label has a second `Text`, which iOS renders as the menu
    item's subtitle) and the watch's Start workout (a 10 pt caption under the button,
    matching the failure text and hidden while it shows).
  - **Section headers**: carry the mark (Home Workout).
  - **Prompts and footers**: say "Apple Health" in their text.
  - **Data screens**: say where the data lives ("Saved in Apple Health", "Heart rate from
    Apple Health").

  "Health" alone is replaced everywhere it means the service. A test in `HelpTests`' style
  scans `App/Sources`, `WatchApp/Sources` and `Shared` for user-facing string literals
  containing "Health" not preceded by "Apple ", and for "HealthKit" in them, so the old word
  cannot come back (FR-013).
- **Rationale**: This covers FR-007 to FR-013 with the smallest change to each screen, and
  never puts the icon in a button.
- **Alternatives considered**: a "Works with Apple Health" banner on the scoreboard.
  Rejected: the badge is for marketing only, and the scoreboard is the one screen that must
  stay clean.

### D-7: Purpose strings name Apple Health, and `verify.sh` holds them to it

- **Decision**: The four `NSHealth*UsageDescription` strings in `Project.swift` are reworded
  to name Apple Health and say what is saved and read (FR-018). The wording is in
  [contracts/identification-points.md](contracts/identification-points.md). `verify.sh`, in
  its existing "Assert both apps may talk to Health" step, checks two more things:
  - each of the four keys in the built plists contains "Apple Health";
  - `AppleHealth.imageset` in both catalogs contains an image file.
- **Rationale**: Principle IV. A purpose string or a missing asset does not fail a compile,
  only a review.

### D-8: Help and README

- **Decision**:
  - `phone.settings` gains a help item, "Apple Health": "What Rekkert saves to and reads from
    Apple Health, and where to change it." It is *not* `needsWatch`, so the help shows it on
    every device. Its `readme` gains "Apple Health".
  - The watch and phone help items that say "Health" are reworded.
  - `README.md` gains a short "## Apple Health" section after "## Workouts". It covers where
    the section is, why it shows without a watch, the explainer, and the single disclosure.
    `HelpTests.everyFeatureInTheReadmeHasAPage` then holds the two together.
- **Rationale**: FR-014. The README is the project's running record of behaviour.

### D-9: Privacy page and App Store description

- **Decision**:
  - **Privacy page**: wording only. "the Health app" becomes "the Apple Health app", and the
    list of what is saved gains active and resting energy, which the watch already saves but
    the page omits.
  - **App Store description**: unchanged. It already names Apple Health in WORKOUTS and
    PRIVACY. Keywords and subtitle are unchanged.
- **Rationale**: FR-022, with the least churn to the listing.

### D-10: Review notes and the recording

- **Decision**: `fastlane/metadata/review_information/notes.txt` gets its Health part
  rewritten as "APPLE HEALTH", per [contracts/review-notes.md](contracts/review-notes.md).
  The notes open with the path that needs no watch, then the path with a watch, and say
  that a recording on a physical iPhone and Apple Watch is attached. The recording follows
  the shot list in that contract and in [quickstart.md](quickstart.md).

  The developer does three things by hand:
  - uploads the notes and attaches the recording in App Store Connect's App Review
    Information;
  - replies to the build 70 rejection in App Store Connect with the same text;
  - submits the next build.
- **Rationale**: Apple asked for the recording explicitly. Notes that start with the no-watch
  path stop the next reviewer repeating the last one's experience. The constitution keeps
  listing uploads manual.

### D-11: Workout controls stay hidden where nothing can be recorded

- **Decision**: No change to the gates in R-1. The Apple Health section explains their
  absence through `HealthReach`.
- **Rationale**: This is the spec's assumption, and today's deliberate behaviour: "not shown
  at all, rather than shown and then doing nothing when pressed".

### D-12: Where to change access

- **Decision**: The page states the system path in words, with no link. The expected path
  on iPhone is **Settings › Privacy & Security › Health › Rekkert**, which also covers what
  the watch app may read and save. The Apple Health app's own route (profile picture ›
  Apps) is given as a second line. Both paths were confirmed on a real iPhone and Apple
  Watch on 2026-10-27 ([quickstart.md](quickstart.md), step R-3, task T040). The watch
  failure text says "Turn on Apple Health access for Rekkert in Settings on your iPhone",
  short enough for the smallest watch.
- **Rationale**: The HIG says access is managed only in the system's settings. The
  `x-apple-health://` scheme is undocumented, and no deep link into an app's access page is
  reported to work reliably
  ([forum 61442](https://developer.apple.com/forums/thread/61442)). A dead or private link
  is a review risk of its own.
- **Alternatives considered**:
  - **`UIApplication.openSettingsURLString`**: rejected. It opens Rekkert's own Settings
    page, which has no Health switches, so it would point at the wrong place.
  - **An "Allow Apple Health" button in the section**: rejected. It is not needed on a
    device that cannot record, and where it can, Start workout already asks with the
    explainer in front.

## Sequencing with `001-fix-session-sharing`

001 is a large change still in progress, while this one unblocks the store. This branch is
based on `main` plus the speckit docs, independent of 001, so it can ship first as build 71.
Whichever lands second rebases. The overlap is in ten files (listed in
[plan.md](plan.md) Constraints). The edits here are additive strings, a section, and two
call sites routed through `HealthAsk`, so the rebase is expected to be mechanical.
