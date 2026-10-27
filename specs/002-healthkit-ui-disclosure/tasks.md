---

description: "Task list for Name Apple Health Wherever Rekkert Uses It"
---

# Tasks: Name Apple Health Wherever Rekkert Uses It

**Input**: Design documents from `specs/002-healthkit-ui-disclosure/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required for the three `RekkertCore` rules and for the wording scan. The
constitution (Principle III) asks for tests first, and SC-005 asks for proof that what is
collected did not change. In every phase, the test tasks come first and **must fail on the
code as it is before that phase's implementation**. Screens are proved by the walkthroughs in
[quickstart.md](quickstart.md), since the apps have no UI test target.

**Organization**: Tasks are grouped by user story, in the spec's priority order, so each
story can be built and checked on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: The user story the task belongs to (US1–US4, as in spec.md)
- **[Manual]**: Must be done by the developer: it needs Apple's terms accepted, a physical
  device, or App Store Connect. An agent stops at these and asks.

**Path shorthands**: paths are from the repository root.

| Shorthand | Path |
|---|---|
| `RekkertCore/` | `Packages/RekkertKit/Sources/RekkertCore/` |
| `CoreTests/` | `Packages/RekkertKit/Tests/RekkertCoreTests/` |

**References**:

- `D-n` is a decision in research.md.
- `P-n` and `W-n` are identification points in
  [contracts/identification-points.md](contracts/identification-points.md). The **words**
  for every screen are taken from that file verbatim, and are not to be reworded in a task.

**Build notes**:

- Tuist globs `App/Sources/**`, `WatchApp/Sources/**` and `Shared/**`, and SwiftPM picks up
  new files in existing targets, so new files need no project or package changes.
- `Shared/` is compiled into both apps.
- `RekkertCore` must not import HealthKit, SwiftUI or WatchKit (Principle I).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A known-good baseline, and the one asset no code can produce

- [ ] T001 Run `swift test --package-path Packages/RekkertKit` and `./scripts/verify.sh` on
  the current commit and confirm both pass. Any failure found here is not this feature's, and
  must be raised before going on.
- [X] T002 [P] [Manual] Download the Apple Health icon from Apple Design Resources
  (https://developer.apple.com/design/resources/, Technologies section, "Apple Health
  Icon"), accepting Apple's terms. Apple ships it as a 1920×1920 PNG with transparency,
  inside a `.dmg`. Add it, unaltered, as an image set named `AppleHealth` in both
  `App/Resources/Assets.xcassets/AppleHealth.imageset/` and
  `WatchApp/Resources/Assets.xcassets/AppleHealth.imageset/`:
  - one universal, single-scale `AppleHealth.png`, scaled down where it is drawn;
  - no tint, mask or rendering-mode override;
  - one appearance for light and dark, as Apple ships only one.

  T043 makes the gate fail without it (D-3).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The single disclosure that every screen reads and both apps' Apple Health
requests are built from, plus the mark that draws Apple's icon. After this phase the apps
collect exactly what they did before, built from the disclosure instead of literal sets.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the foundation ⚠️

> Write these first. They must fail (not compile) before T006–T008.

- [ ] T003 [P] Write `CoreTests/HealthDisclosureTests.swift` (Swift Testing, `@testable
  import RekkertCore`). It asserts:
  - `HealthDisclosure.saved(on: .phone) == [.workout]`
  - `HealthDisclosure.saved(on: .watch) == [.workout, .activeEnergy, .restingEnergy, .effort]`
  - `HealthDisclosure.read(on: .phone) == []`
  - `HealthDisclosure.read(on: .watch) == [.heartRate, .activeEnergy, .restingEnergy, .restingHeartRate, .dateOfBirth, .workout, .effort]`
  - every `HealthData` case has a non-empty `title` and `reason`, matching the "Shown as" and
    "Why Rekkert uses it" columns of data-model.md;
  - `summary`, `when`, `whereItGoes` and `changeAccess` are non-empty, and `summary` equals
    the P-01 body text;
  - no string anywhere in the disclosure contains "HealthKit", and every "Health" in it is
    preceded by "Apple ", except in `changeAccess`, whose lines quote system menu names
    such as "Settings › Privacy & Security › Health" verbatim (FR-013);
  - the union of both devices' `saved` and `read` is `Set(HealthData.allCases)`, so the page
    lists everything and nothing else.

  Add a comment on the two `watch` assertions: these are the sets at `rtxlwlsn`, and
  changing them changes what Rekkert collects (FR-019, SC-005).
- [ ] T004 [P] Write `CoreTests/HealthReachTests.swift`. For all 16 combinations of
  `healthAvailable`, `canPairWatch`, `isPaired`, `watchAppInstalled`, it asserts the result
  of `HealthReach(...)`, evaluated top to bottom as in data-model.md:
  - `.unavailable` when `!healthAvailable`;
  - `.cannotPair` when `!canPairWatch`;
  - `.noWatch` when `!isPaired`;
  - `.watchAppMissing` when `!watchAppInstalled`;
  - `.canRecord` otherwise.

  It also asserts:
  - `.canRecord` holds exactly when all four inputs are true (today's `isAvailable`);
  - each non-`.canRecord` case's `line` equals the data-model "Settings line" text;
  - `.canRecord.line == nil`.
- [ ] T005 [P] Write `CoreTests/HealthAskTests.swift`. It asserts
  `HealthAsk.explainFirst(.wouldAsk) == true`, `HealthAsk.explainFirst(.unknown) == true`
  and `HealthAsk.explainFirst(.alreadyAsked) == false`.

### Implementation for the foundation

- [ ] T006 [P] Create `RekkertCore/Health/HealthDisclosure.swift`, per data-model.md:
  - `public enum HealthData: CaseIterable, Sendable` with `title` and `reason` (the
    data-model table, verbatim);
  - `public enum HealthDevice { case phone, watch }`;
  - `public enum HealthDisclosure` with `saved(on:)`, `read(on:)`, `summary`, `when`,
    `whereItGoes` and `changeAccess: [String]`.

  `changeAccess` starts as the two *Draft* lines of P-02, and is settled in T040. Make T003
  pass.
- [ ] T007 [P] Create `RekkertCore/Health/HealthReach.swift`:
  - `public enum HealthReach: Equatable, Sendable { case canRecord, unavailable, cannotPair, noWatch, watchAppMissing }`;
  - `public init(healthAvailable:canPairWatch:isPaired:watchAppInstalled:)`;
  - `public var line: String?`, with the data-model "Settings line" text verbatim.

  Make T004 pass.
- [ ] T008 [P] Create `RekkertCore/Health/HealthAsk.swift`: `public enum HealthAsk` with a
  nested `public enum Status: Sendable { case wouldAsk, alreadyAsked, unknown }`, and
  `public static func explainFirst(_ status: Status) -> Bool` returning
  `status != .alreadyAsked`. Make T005 pass.
- [ ] T009 Create `Shared/HealthTypes.swift`, the only place `HealthData` meets HealthKit:
  - `extension HealthData { var objectType: HKObjectType; var sampleType: HKSampleType? }`,
    an exhaustive `switch` with no `default`:
    - `.workout` → `HKQuantityType.workoutType()`;
    - `.activeEnergy` → `.activeEnergyBurned`;
    - `.restingEnergy` → `.basalEnergyBurned`;
    - `.effort` → `.workoutEffortScore`;
    - `.heartRate` → `.heartRate`;
    - `.restingHeartRate` → `.restingHeartRate`;
    - `.dateOfBirth` → `HKCharacteristicType(.dateOfBirth)`, with `sampleType` nil.
  - `extension HealthDisclosure { static func toShare(on:) -> Set<HKSampleType>; static func toRead(on:) -> Set<HKObjectType> }`;
  - `extension HealthAsk.Status { init(_ status: HKAuthorizationRequestStatus) }`, mapping
    `.shouldRequest` → `.wouldAsk`, `.unnecessary` → `.alreadyAsked`, and anything else →
    `.unknown`;
  - `extension HKHealthStore { func askStatus(on device: HealthDevice) async -> HealthAsk.Status }`,
    wrapping `statusForAuthorizationRequest(toShare:read:)` with the device's sets and
    returning `.unknown` on a thrown error.

  Depends on T006 and T008.
- [ ] T010 In `App/Sources/WorkoutController.swift`, replace both literal
  `toShare: [HKQuantityType.workoutType()], read: []` sets (in `prepare()` and `start()`)
  with `HealthDisclosure.toShare(on: .phone)` and `HealthDisclosure.toRead(on: .phone)`. Add
  `var reach: HealthReach`, built from:
  - `HKHealthStore.isHealthDataAvailable()`;
  - `WCSession.isSupported()`;
  - `WCSession.default.isPaired`;
  - `WCSession.default.isWatchAppInstalled`.

  Keep `#if DEBUG pretendsAvailable` returning `.canRecord`. Redefine
  `isAvailable` as `reach == .canRecord`, so every existing gate behaves as before (D-11).
  Depends on T007 and T009.
- [ ] T011 [P] In `WatchApp/Sources/WorkoutController.swift`, replace the bodies of
  `private static var shared` and `private static var read` with
  `HealthDisclosure.toShare(on: .watch)` and `HealthDisclosure.toRead(on: .watch)`. Keep the
  existing doc comments that explain why each type is there, moved onto
  `RekkertCore/Health/HealthDisclosure.swift`'s cases if they no longer sit next to code.
  Depends on T009.
- [ ] T012 [P] Create `Shared/AppleHealthMark.swift`: `struct AppleHealthMark: View` with a
  `size: CGFloat` parameter (default: the body line height through `@ScaledMetric`). It draws
  `Image("AppleHealth").resizable().scaledToFit()` at `size`, then `Text("Apple Health")`, in
  an `HStack`. The HIG rules apply (D-3):
  - padding of `size / 10` around the image;
  - no `clipShape`, tint, shadow, border or overlay;
  - `.accessibilityElement(children: .ignore)` with label "Apple Health".

  Add a doc comment saying it must never be put inside a `Button`, `NavigationLink` or menu
  item.

**Checkpoint**: `swift test` is green, with T003–T005 passing. Both apps build. What the
apps ask Apple Health for is unchanged (T003 pins it).

---

## Phase 3: User Story 1 - Anyone can find what Rekkert does with Apple Health, watch or no watch (Priority: P1) 🎯 MVP

**Goal**: An Apple Health section in Settings, with Apple's icon, on every iPhone and iPad,
leading to a page with the full disclosure (P-01, P-02, P-12 first row).

**Independent Test**: [quickstart.md](quickstart.md) §3. On an unpaired iPhone simulator and
an iPad simulator, tap the gear: the section is there with the icon, the summary and the
right reach line. "What Rekkert saves and reads" opens the page. Reached in two taps and
under 30 seconds.

### Tests for User Story 1 ⚠️

- [ ] T013 [US1] Add `## Apple Health` to `README.md`, directly after the `## Workouts`
  section. Cover:
  - where the Settings section is, and why it shows with no watch (2.5.1, D-1);
  - that every screen reads the one `HealthDisclosure` (D-2);
  - the explainer before the first request (D-5).

  Five to ten lines, in the README's voice. Then run `swift test`: `HelpTests.everyFeatureInTheReadmeHasAPage`
  must now **fail**, because no help page lists "Apple Health".

### Implementation for User Story 1

- [ ] T014 [US1] In `RekkertCore/Help/HelpCatalog.swift`, page `phone.settings`:
  - append `"Apple Health"` to `readme`;
  - add `HelpItem("Apple Health", what: "What Rekkert saves to and reads from Apple Health, and where to change it.", example: "You want to know what the workout reads before you start one.")`
    with no `symbol` and `needsWatch` left `false`.

  `what` must stay ≤ 80 characters and `example` ≤ 100 (`HelpTests.noWallsOfText`). Make
  T013's failure pass.
- [ ] T015 [P] [US1] Add `case appleHealth` to `enum HomeRoute` in
  `App/Sources/Views/HistoryView.swift`. Route it to `AppleHealthView()` in the
  `navigationDestination` switch in `App/Sources/Views/HomeView.swift`.
- [ ] T016 [P] [US1] Create `App/Sources/Views/AppleHealthView.swift`, the P-02 page. It is a
  `List` titled "Apple Health" (inline), containing in order:
  1. A header row: `AppleHealthMark(size: 48)`, centred. It is not a button.
  2. A section "Saved to Apple Health": one row per kind in the union of
     `HealthDisclosure.saved(on: .phone)` and `.saved(on: .watch)`, in `HealthData.allCases`
     order, with `title` as the headline and `reason` as secondary text.
  3. A section "Read from Apple Health": the same, from `read(on: .watch)`.
  4. A section "When", with `HealthDisclosure.when`.
  5. A section "Where it goes", with `HealthDisclosure.whereItGoes`.
  6. A section "Change access", with each line of `HealthDisclosure.changeAccess`.

  It has no toggles, buttons or links (FR-005), and nothing on it triggers a request (FR-006).
  Depends on T012.
- [ ] T017 [US1] In `App/Sources/Views/SettingsView.swift`, add the Apple Health section
  (P-01). It goes after the whole `if AppModel.canPairWatch { … }` block and before the
  `CommitLabel` section, with no condition around it (D-1). It contains:
  - **Header**: `AppleHealthMark()`.
  - **Rows**:
    - `Text(HealthDisclosure.summary)`;
    - `Text(line)` in secondary style, when `model.workout.reach.line` is non-nil;
    - `NavigationLink("What Rekkert saves and reads", value: HomeRoute.appleHealth)`.

  It must not call `prepare()`, `start()` or any request (FR-006). Depends on T010, T012 and
  T015.
- [ ] T018 [US1] In `App/Sources/Views/DemoLaunch.swift`, add
  `static var openAppleHealth: Bool` for `-rekkert-demo-apple-health`. In `HomeView`'s
  `#if DEBUG` launch `.task`, set `path = [.settings, .appleHealth]` when it is on, beside
  the existing `openSettings` branch. Depends on T015.

**Checkpoint**: Run [quickstart.md](quickstart.md) §1 and §3. US1 is shippable on its own as
the minimum 2.5.1 fix.

---

## Phase 4: User Story 2 - Every workout control and prompt says it goes to Apple Health (Priority: P1)

**Goal**: Apple Health named at every point of use on both devices, with the icon only in
non-interactive places (P-03 to P-09, P-12 second row, W-01 to W-04, W-07).

**Independent Test**: [quickstart.md](quickstart.md) §4 steps 1, 5, 6 and 7 on paired
simulators. Every listed point shows its words from the contract.

### Tests for User Story 2 ⚠️

- [ ] T019 [US2] Write `CoreTests/HealthWordingTests.swift`, modelled on `HelpTests`' file
  scan, with the same `root` computation and `.swift` filter. It scans `App/Sources`,
  `WatchApp/Sources`, `Shared` and `Packages/RekkertKit/Sources/RekkertCore/Help` for string
  literals (`/"([^"\n]*)"/`). It fails a literal that contains "HealthKit" or "the Health
  app", or that still contains "Health" after every "Apple Health" is removed. Swift `Regex`
  has no lookbehind, so remove-then-search is the method. Report file and literal.

  It must **fail** now, on exactly these six literals:
  - `App/Sources/Views/WorkoutsView.swift` ("…stays in the Health app.");
  - `App/Sources/Views/HomeView.swift` (the Workout footer);
  - `App/Sources/Views/WorkoutDetailView.swift` ("Worked out by Health…");
  - `WatchApp/Sources/WorkoutController.swift` ("Health access is off for Rekkert");
  - `RekkertCore/Help/HelpCatalog.swift`, twice ("…in Health while you play.", "…saves it to
    Health.").

### Implementation for User Story 2 (iPhone)

- [ ] T020 [P] [US2] In `App/Sources/Views/HomeView.swift`, change the Workout section:
  - **Header**: `HStack { Text("Workout"); Spacer(); AppleHealthMark() }`.
  - **Footer**: the P-03 text, keeping the `model.workout.failure ??` fallback.

  The mark is in the header, never in the Start/Hold buttons (D-3).
- [ ] T021 [P] [US2] In `App/Sources/Views/MatchOptionsMenu.swift`, give the "Start workout"
  `Button` a two-`Text` label, so the menu shows "Saves to Apple Health" as its subtitle
  (P-04). Keep `systemImage` `figure.tennis` through a `Label`. "Stop workout", "Pause
  workout" and "Resume workout" are unchanged.
- [ ] T022 [P] [US2] In `App/Sources/Views/RootView.swift`, change the "Start a workout?"
  alert message to the P-05 text.
- [ ] T023 [US2] In `App/Sources/Views/SettingsView.swift`, append the P-06 sentence to
  every non-empty `workoutFooter` result, including the nothing-chosen fallback. Depends on
  T017 (same file).
- [ ] T024 [P] [US2] In `App/Sources/Views/WorkoutsView.swift`, use the P-07 footer and
  empty-state description.
- [ ] T025 [P] [US2] In `App/Sources/Views/WorkoutDetailView.swift`, add
  `LabeledContent("Saved in", value: "Apple Health")` directly after the "Saved as" row, and
  change the effort footnote to the P-08 text.
- [ ] T026 [P] [US2] In `App/Sources/Views/MatchTimelineSection.swift`:
  - inside `heartRate(domain)`, add a caption "Heart rate from Apple Health" in
    `.caption`/secondary, above or below the chart to match the momentum chart's caption
    style;
  - change the footer hint to the P-09 text.
- [ ] T027 [P] [US2] In `App/Sources/WorkoutController.swift`, in `start()`'s `catch`, map
  `HKError.errorAuthorizationDenied` and `.errorAuthorizationNotDetermined` to "Turn on
  Apple Health access for Rekkert in Settings." All other errors keep "Couldn't start on your
  watch" (FR-012).

### Implementation for User Story 2 (Apple Watch)

- [ ] T028 [P] [US2] In `WatchApp/Sources/Views/WatchWorkoutButton.swift`, add a caption
  under `button` reading "Saves to Apple Health" (W-01). Show it only when
  `!model.workout.isTracking && model.workout.failure == nil`, so it shares the failure
  text's slot. Use the failure text's styling (`.system(size: 10)`, secondary, centred) and
  let it wrap. This covers the menu page, the idle screen and the result screen at once.
- [ ] T029 [P] [US2] In `WatchApp/Sources/Views/WatchRootView.swift`, give the "Start a
  workout?" alert a `message:` reading "It's saved to Apple Health." (W-02).
- [ ] T030 [P] [US2] In `WatchApp/Sources/Views/WatchWorkoutPage.swift`, add the caption
  "Saving to Apple Health" (W-03) above the `Spacer`, in `.system(size: 10)`, secondary,
  `lineLimit(1)`, `minimumScaleFactor(0.7)`. The page's "nothing scrolls" rule stands: check
  on a 40 mm simulator at the largest text size. If the page no longer fits without
  scrolling, stop and ask, rather than dropping the caption (FR-011) or making the page
  scroll.
- [ ] T031 [P] [US2] In `WatchApp/Sources/WorkoutController.swift`, change
  `stopped(with:)`'s authorization case to the W-04 *Draft* text, "Turn on Apple Health
  access for Rekkert in Settings on your iPhone." It is settled in T040.
- [ ] T032 [US2] In `RekkertCore/Help/HelpCatalog.swift`, reword three items: `watch.workout`
  "Start workout" and "Stop workout" to the W-07 texts, and the `phone.home` "Start a
  workout" item to the P-12 second-row text (≤ 80 characters each). Depends on T014 (same
  file). With T020, T024, T025 and T031 this makes T019 pass.

**Checkpoint**: `swift test` is green, including T019. [quickstart.md](quickstart.md) §4
steps 1 and 5 to 7 pass on paired simulators.

---

## Phase 5: User Story 3 - Rekkert explains itself before Apple Health asks for access (Priority: P2)

**Goal**: One explanation screen before the first system request on each device, shown only
while Apple Health would show its sheet, and permission strings that name Apple Health
(P-10, P-11, W-05, W-06; D-5, D-7).

**Independent Test**: [quickstart.md](quickstart.md) §4 steps 2 to 4. On a fresh install:
- Start workout shows the explainer.
- Not now shows no system sheet and starts nothing.
- Continue shows the system sheet, whose text names Apple Health.
- The explainer is gone after that.

### Implementation for User Story 3 (iPhone)

- [ ] T033 [US3] In `App/Sources/WorkoutController.swift`, route every request through
  `HealthAsk`:
  - Add `enum PendingAsk { case start, prepare(onGo: @MainActor () -> Void) }` and
    `var explaining: PendingAsk?`, observable.
  - Add a private `ask(_ pending: PendingAsk)` that does
    `let status = await health.askStatus(on: .phone)`. If
    `HealthAsk.explainFirst(status)`, it sets `explaining = pending` and returns; otherwise
    it goes on at once.
  - Going on means: for `.prepare`, call `onGo` and then request access; for `.start`,
    request access and then `startWatchApp`, as today.
  - `start()` and `prepare(onGo:)` call `ask`.
  - Add `func answerExplainer(_ go: Bool)`. It clears `explaining`. On `true` it goes on.
    On `false` it does nothing at all, so no `onGo`, no request and no start (FR-016).

  `isTracking` and `failure` behave exactly as before, once past the explainer.
- [ ] T034 [P] [US3] Create `App/Sources/Views/HealthExplainer.swift`, the P-10 sheet:
  - `AppleHealthMark(size: 60)` at the top, not a button;
  - the title "Rekkert works with Apple Health";
  - the body;
  - the note in secondary style;
  - "Continue" (`.borderedProminent`) and "Not now", taking `onAnswer: (Bool) -> Void`.

  No toggles or per-item rows (FR-015). `.presentationDetents([.medium, .large])`;
  `.interactiveDismissDisabled()` is not used, and a swipe-down counts as Not now.
- [ ] T035 [US3] Wire up the explainer. Depends on T033 and T034.
  - In `App/Sources/Views/RootView.swift`, present `HealthExplainer` as a sheet bound to
    `model.workout.explaining != nil`. Follow the comment at line 148 about holding back
    while another sheet is up, and calling `answerExplainer(false)` on dismiss without an
    answer.
  - In `App/Sources/Views/SettingsView.swift`, change `workoutOnMatchStart`'s setter:
    - for `.off`, store it at once, as today;
    - for any other value, call
      `model.workout.prepare(onGo: { model.store.setHaptics(workoutOnMatchStart: value) })`
      and do not store it yet.

    The picker keeps showing the stored value while the explainer is up. Not now leaves the
    setting, and what the watch has been told, exactly as they were (FR-016).
  - In `App/Sources/Views/DemoLaunch.swift`, add `-rekkert-demo-health-explainer`, which sets
    `model.workout.explaining = .start` on launch in `#if DEBUG`.

### Implementation for User Story 3 (Apple Watch)

- [ ] T036 [US3] In `WatchApp/Sources/WorkoutController.swift`, apply the same gate as T033
  with `askStatus(on: .watch)`. `PendingAsk` is `.start`, `.prepare` or `.ratings`, and
  every `requestAuthorization` goes through it: `start()`, `prepare()` and
  `writeWaitingRatings()`. `answerExplainer(false)` drops the pending action and changes
  nothing; it asks again on the next `becameActive`. Leave `Shared/AppModel.swift`'s
  `becameActive` calls as they are, since the gate lives in the controller. Then:
  - Create `WatchApp/Sources/Views/WatchHealthExplainer.swift` (W-05). It is a
    `ScrollView` with the mark at the watch body size, the title, the body, and two
    full-width buttons, "Continue" and "Not now".
  - Present it from `WatchApp/Sources/Views/WatchRootView.swift` as a sheet bound to
    `model.workout.explaining != nil`.
  - In `WatchApp/Sources/Views/WatchDemoLaunch.swift`, add `-rekkert-demo-health-explainer`.
- [ ] T037 [P] [US3] In `Project.swift`, replace the four `NSHealth*UsageDescription`
  strings with the P-11 texts (iOS target) and W-06 texts (watch target), verbatim. Update
  the comment above the iOS pair if it no longer matches. Run `tuist generate` (through
  `mise`) to check.
- [ ] T038 [US3] In `scripts/verify.sh`, under "Assert both apps may talk to Health", assert
  that each of the four keys' values contains "Apple Health", in `$plist` (watch) and
  `$iosplist` (iOS). Use `plutil -extract <key> raw -o -` on each and `grep -q 'Apple Health'`,
  printing `ok:` or `FAIL:` like the surrounding checks (D-7). Depends on T037.

**Checkpoint**: `./scripts/verify.sh` is green. [quickstart.md](quickstart.md) §4 steps 2 to
4 and the watch explainer in step 6 pass.

---

## Phase 6: User Story 4 - The next submission carries the proof (Priority: P2)

**Goal**: Review notes that lead App Review to Apple Health on any device, a recording on
physical devices, and settled access paths (FR-020 to FR-022).

**Independent Test**: someone with an iPhone and no watch follows the notes alone and
reaches the Apple Health section on the first try (SC-006). The recording shows every P- and
W- point (SC-003) in under three minutes (SC-007).

- [ ] T039 [P] [US4] In `fastlane/metadata/review_information/notes.txt`, replace the
  "WORKOUTS (HEALTHKIT)" part (heading and paragraphs, up to "SHARING A MATCH") with the
  text block in [contracts/review-notes.md](contracts/review-notes.md), verbatim. Leave every
  other part unchanged.
- [ ] T040 [US4] [Manual] On an iPhone running iOS 26 with a paired Apple Watch on watchOS
  26, find where Rekkert's Apple Health access is changed. This is quickstart R-3: the
  Settings route, the Apple Health app's own route, and where the watch app's access lives.
  Then update all of these to the paths found, and drop the *Draft* marks in the contract:
  - `HealthDisclosure.changeAccess` in `RekkertCore/Health/HealthDisclosure.swift`;
  - the W-04 text in `WatchApp/Sources/WorkoutController.swift`;
  - the T027 text in `App/Sources/WorkoutController.swift`;
  - P-02 and W-04 in [contracts/identification-points.md](contracts/identification-points.md).

  Re-run `swift test`.
- [ ] T041 [US4] [Manual] On the real pair, with a release-configuration or TestFlight build
  of this branch that includes T002's icon:
  1. Follow [quickstart.md](quickstart.md) R-1 and R-2.
  2. Do the two checks listed after the notes in
     [contracts/review-notes.md](contracts/review-notes.md):
     - confirm the watch menu page's side;
     - have someone who has not used Rekkert follow the notes alone, on an iPhone with no
       watch, to the Apple Health section (SC-006).

     Correct the notes, and T039's copy, if either check fails.
  3. Make the recording per R-4 and the shot list, and tick every P- and W- point against
     it.
- [ ] T042 [US4] [Manual] In App Store Connect, for the next build:
  - paste the review notes from T039;
  - attach the recording under App Review Information;
  - reply to the build 70 rejection with the same notes and a line saying the recording is
    attached;
  - submit.

  Confirm the App Store description still names Apple Health in WORKOUTS and PRIVACY
  (FR-022).

**Checkpoint**: Submission ready. SC-001 is known only when App Review answers.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: The gates and documents that span stories

- [ ] T043 In `scripts/verify.sh`, assert that the `AppleHealth.imageset` folder holds a
  `.pdf`, `.svg` or `.png` beside its `Contents.json`, in both
  `App/Resources/Assets.xcassets/` and `WatchApp/Resources/Assets.xcassets/`. Fail with
  "FAIL: Apple Health icon missing from <catalog>; see specs/002-healthkit-ui-disclosure
  T002". Depends on T002 and T038 (same file).
- [ ] T044 [P] In `docs/privacy/index.html`:
  - replace every bare "Health" that means the service with "Apple Health", and "the Health
    app" with "the Apple Health app";
  - add active and resting energy to what a workout saves, in the "Your workouts, to Apple
    Health" paragraph.

  Change no other claim (D-9).
- [ ] T045 [P] In `README.md`, add `-rekkert-demo-apple-health` and
  `-rekkert-demo-health-explainer` to the debug launch-argument list.
- [ ] T046 Run `swift test --package-path Packages/RekkertKit` and `./scripts/verify.sh`,
  then [quickstart.md](quickstart.md) §3 and §4 in full. Fix anything they find.
- [ ] T047 If `001-fix-session-sharing` has reached `main` meanwhile, rebase this branch
  onto it with `jj rebase` and resolve the overlaps listed in plan.md Constraints. Keep both
  sides' strings and sections, and re-run T046.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 first. T002 is manual, can happen any time before T041 and T043,
  and blocks no code.
- **Foundational (Phase 2)**: depends on T001, and blocks every story.
- **US1 (Phase 3)**: depends on Phase 2.
- **US2 (Phase 4)**: depends on Phase 2. T023 waits for T017 and T032 for T014 (same
  files); otherwise independent of US1.
- **US3 (Phase 5)**: depends on Phase 2. T035 touches `SettingsView` and `RootView` after
  US1 and US2's edits there.
- **US4 (Phase 6)**: T039 any time. T040 to T042 need US1 to US3 done and T002 in place.
- **Polish (Phase 7)**: T043 needs T002 and T038. T046 runs after everything wanted is in.

### Within the Foundation

- T003, T004 and T005 come first and fail.
- Then T006, T007 and T008 run in parallel.
- Then T009, then T010, T011 and T012 in parallel (T010 after T007 too).

### Same-File Chains (not parallel)

| File | Tasks, in order |
|---|---|
| `SettingsView.swift` | T017, T023, T035 |
| `HelpCatalog.swift` | T014, T032 |
| `App/Sources/WorkoutController.swift` | T010, T027, T033, T040 |
| `WatchApp/Sources/WorkoutController.swift` | T011, T031, T036, T040 |
| `RootView.swift` | T022, T035 |
| `WatchRootView.swift` | T029, T036 |
| `scripts/verify.sh` | T038, T043 |
| `README.md` | T013, T045 |
| `HomeView.swift` | T015, T018, T020 |

---

## Parallel Example: Foundation

```bash
# Tests first, together:
Task: "Write CoreTests/HealthDisclosureTests.swift (T003)"
Task: "Write CoreTests/HealthReachTests.swift (T004)"
Task: "Write CoreTests/HealthAskTests.swift (T005)"

# Then the three rules, together:
Task: "Create RekkertCore/Health/HealthDisclosure.swift (T006)"
Task: "Create RekkertCore/Health/HealthReach.swift (T007)"
Task: "Create RekkertCore/Health/HealthAsk.swift (T008)"
```

## Parallel Example: User Story 2

```bash
# After T019 fails, these touch different files:
Task: "HomeView Workout header and footer (T020)"
Task: "MatchOptionsMenu subtitle (T021)"
Task: "RootView alert message (T022)"
Task: "WorkoutsView footer and empty state (T024)"
Task: "WorkoutDetailView Saved in row (T025)"
Task: "MatchTimelineSection caption (T026)"
Task: "WatchWorkoutButton caption (T028)"
Task: "WatchRootView alert message (T029)"
Task: "WatchWorkoutPage caption (T030)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 and Phase 2.
2. Phase 3 (US1): the Apple Health section and page.
3. **Stop and validate** with quickstart §1 and §3. This alone is likely enough for 2.5.1,
   since it is what a reviewer without a watch was missing.

### Incremental Delivery (Recommended for Build 71)

1. **Foundation and US1**: the always-visible section.
2. **US2**: names Apple Health at every control. This is cheap, and covers a reviewer who
   does have a watch.
3. **US3**: the explainer and the purpose strings.
4. **US4**: notes, recording, submit.

US1 and US2 together make the strongest case. US3 matters most for a reviewer who tests
with a watch. Submit with all four rather than splitting across builds: a second rejection
costs more than the extra day.

---

## Notes

- Commit with jj, conventional style, one logical group per commit (for example,
  `feat(health): …`, `test(health): …`, `docs: …`). No AI trailers.
- Unrecognised changes in the working copy are probably the parallel session in
  `~/dev/rekkert`. Leave them alone, and stop and ask if they get in the way.
- Words on screen come from the contract verbatim. If a word must change, change the
  contract in the same commit.
