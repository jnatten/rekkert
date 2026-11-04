---

description: "Tasks for Rekkert on Apple Watch SE (1st generation)"
---

# Tasks: Rekkert on Apple Watch SE (1st generation)

**Input**: Design documents from `specs/003-apple-watch-se-support/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: The constitution requires Swift Testing for `RekkertCore` changes, written first
(Principle III). That covers the `HealthDisclosure` change in US4. Everything else is app-shell
code with no test target, so it is checked by `scripts/verify.sh`, the watchOS 26 simulator
and the on-wrist rows in [quickstart.md](quickstart.md).

**Organization**: The watch app does not build at watchOS 10 until all four blockers in
research R-3 are fixed, so lowering the floor and fixing them is the Foundational phase. The
user-story phases then add what each story needs on top and verify it on the watch.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5)
- **[Manual]**: Needs a person with the hardware (a real SE 1st generation on watchOS 10,
  paired with an iPhone on iOS 26+). An agent cannot do it.
- Line numbers refer to the base commit `uwrmmsmp`. Find the symbol named if the line has
  moved.

---

## Phase 1: Setup

**Purpose**: Make the new floor part of the constitution before any code relies on it
(research D-10).

- [X] T001 Amend `.specify/memory/constitution.md`.
  - Replace the Platforms bullet's first sentence, "Targets build for iOS, watchOS, and
    macOS 26.", with the text in `specs/003-apple-watch-se-support/contracts/watch-floor.md`
    § Constitution. Keep the bullet's second sentence ("The engine must keep building…").
  - Bump the footer to `**Version**: 1.1.0`, `**Last Amended**: <today>`.
  - Add a Sync Impact Report as an HTML comment at the very top of the file (`<!-- Sync
    Impact Report … -->`). It records version 1.0.0 → 1.1.0 (MINOR: a materially changed
    platform rule), the changed section (Platform & Technical Constraints), and the reason
    (Apple Watch SE 1st generation, Series 4 and 5 stop at watchOS 10.6.1).

---

## Phase 2: Foundational (the watch app builds at watchOS 10)

**Purpose**: Lower the floor and fix the four places from research R-3, each in its final form
(D-1, D-2, D-5, D-6). Nothing can be tried on an SE (1st generation) until this phase builds.

**⚠️ CRITICAL**: No user-story verification can begin until T009 passes.

- [X] T002 [P] In `Packages/RekkertKit/Package.swift`, change `platforms` from
  `[.iOS(.v26), .watchOS(.v26), .macOS(.v26)]` to `[.iOS(.v26), .watchOS(.v10), .macOS(.v26)]`.
  Nothing else changes.
- [X] T003 [P] In `Project.swift`, change the `RekkertWatch` target's
  `deploymentTargets: .watchOS("26.0")` to `deploymentTargets: .watchOS("10.0")`. The
  `Rekkert` and `RekkertWidgets` targets stay at `.iOS("26.0")`.
- [X] T004 [P] In `WatchApp/Sources/WorkoutController.swift`, `first(of:orNilAfter:)`
  (~line 882), replace `Mutex<CheckedContinuation<Value?, Never>?>(continuation)` with
  `OSAllocatedUnfairLock<CheckedContinuation<Value?, Never>?>(initialState: continuation)`.
  Keep `pending.withLock { waiting in … }` as it is, since the closure shape is the same
  (`inout` state). Replace `import Synchronization` (line 5) with `import os`. No
  `#available` branch (D-6).
- [X] T005 In `WatchApp/Sources/WorkoutController.swift`, keep the effort rating out of Apple
  Health below watchOS 11 (D-2, contracts/apple-health-access.md § Effort rating behaviour).
  Same file as T004, so do it after T004.
  - `save(_:to:)` (~line 280): after the existing `guard WorkoutEffort.range.contains(effort)`,
    add `guard #available(watchOS 11, *) else { return }`. On watchOS 10 nothing is stored in
    `waiting` and nothing is queued.
  - Mark `enqueue(_:)` (~288), `writeWaiting(_:)` (~297) and `write(_:to:)` (~322)
    `@available(watchOS 11, *)`.
  - `writeWaitingRatings()` (~275): return at once unless `#available(watchOS 11, *)`, so
    `ask(.ratings)` never fires on watchOS 10.
  - `carryOn(_:)`, `.ratings` case: wrap the `for id in waiting.keys… { enqueue(id) }` loop in
    `if #available(watchOS 11, *)`.
  - Leave `rate(_:)`, `skipEffort()` and `heard(_:)` as they are. They still publish `.rated`
    or `.skipped` and clear the question. Only the Apple Health write is skipped.
- [X] T006 [P] In `Shared/HealthTypes.swift`, make `HealthData.objectType` return
  `HKObjectType?`.
  - `.effort` returns `HKQuantityType(.workoutEffortScore)` only when
    `#available(watchOS 11, *)` and `nil` otherwise. On iOS that check is always true.
  - Every other case is unchanged.
  - `sampleType` stays `objectType as? HKSampleType`.
  - `HealthDisclosure.toRead(on:)` changes from `map(\.objectType)` to
    `compactMap(\.objectType)`. `toShare(on:)` already uses `compactMap(\.sampleType)`.
- [X] T007 [P] Create `Shared/ObservationChanges.swift`: a `@MainActor` function
  `observationChanges<Value: Sendable>(of read: @escaping @MainActor () -> Value) -> AsyncStream<Value>`
  (D-5, data-model.md § Round-alarm situation). Its contract:
  - yield `read()` once immediately;
  - then register `withObservationTracking({ _ = read() }, onChange: …)`, where `onChange`
    hops to the main actor (`Task { @MainActor in … }`), yields a fresh `read()`, and
    registers again;
  - use `.bufferingNewest(1)`;
  - stop registering once the stream terminates (`continuation.onTermination`).

  It needs no availability annotation, since `Observation` exists from watchOS 10 and iOS 17.
- [X] T008 In `Shared/RoundAlarmFollower.swift`, `follow(_:)` (~line 28), keep the
  `Observations { … }` loop under `if #available(iOS 26, watchOS 26, *)`.
  - In the `else` branch, iterate `observationChanges(of:)` (from T007) with the same
    `Situation(session: store.log.sessionID, state: store.state)` closure, and call the same
    `heard(_:session:)`.
  - In `#if DEBUG` only, the launch argument `-rekkert-observation-fallback` makes it take the
    `else` branch, so the watchOS 26 and iOS 26 simulators can exercise the path an SE (1st
    generation) runs.
  - Depends on T007.
- [X] T009 Build at the new floor. Run `mise exec -- tuist generate --no-open`, then:
  - `xcodebuild -workspace Rekkert.xcworkspace -scheme RekkertWatch -destination 'generic/platform=watchOS Simulator' build`
  - `xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert -destination 'generic/platform=iOS Simulator' build`

  Expected: no errors in either. In the iOS build's
  `Rekkert.app/Watch/RekkertWatch.app/Info.plist`, `MinimumOSVersion` is `10.0`. Then run
  `scripts/verify.sh` and expect `==> All checks passed`. Depends on T002–T008.

**Checkpoint**: The iPhone app embeds a watch app that installs on watchOS 10, with no
behaviour change on watchOS 26 and later.

---

## Phase 3: User Story 1 - Score a match from an SE (1st generation) (Priority: P1) 🎯 MVP

**Goal**: Rekkert installs on an SE (1st generation) and every mode can be scored from the
wrist, in step with the phone and other devices.

**Independent Test**: [quickstart.md](quickstart.md) § 3, rows 1–8, on a real SE (1st
generation) on watchOS 10.

The code for this story is in Phase 2. If a row fails, add a fix task to this phase naming the
row, what was seen and the suspected file, and finish it before the checkpoint.

- [X] T010 [US1] Create `specs/003-apple-watch-se-support/validation.md`.
  - A header records: the watch model and size, its watchOS version, the iPhone model and iOS
    version, the build (Xcode run or TestFlight number), and the date.
  - A table has one row for each of quickstart § 3 rows 1–18, with columns *Check*,
    *Result* (pass/fail), *Notes*.
  - Further sections hold quickstart § 1 (the SC-008 trial), § 2 (watchOS 26 regression) and
    § 4 (documents).
- [ ] T011 [US1] [Manual] Install on the SE (1st generation) with the `Rekkert` scheme (README,
  "Running on a real iPhone and Watch"). If Xcode 27 cannot install on or debug a watchOS 10
  watch, use an internal TestFlight build from the `testflight` workflow instead, and note
  which in `validation.md` (research R-10). Record row 1.
- [ ] T012 [US1] [Manual] Run quickstart § 3 rows 2–6 (layout at the watch's size, a
  best-of-three match on the wrist, taps on the phone, every mode, wrist responsiveness) and
  record them in `specs/003-apple-watch-se-support/validation.md`. Depends on T011.
- [ ] T013 [US1] [Manual] Run quickstart § 3 rows 7–8 (iPhone out of reach over Bluetooth, and
  convergence across the SE, a current watch and two phones) and record them in
  `specs/003-apple-watch-se-support/validation.md`. Depends on T011.

**Checkpoint**: Rows 1–8 pass. This is the MVP: an SE (1st generation) owner can score from
the wrist.

---

## Phase 4: User Story 2 - Record the session as an Apple Health workout (Priority: P1)

**Goal**: Workouts start from every entry point on an SE (1st generation), collect with the
wrist lowered, save to Apple Health as tennis, and show on the phone.

**Independent Test**: [quickstart.md](quickstart.md) § 3, rows 9–12.

The code for this story is in Phase 2 (T004 keeps the HealthKit race helper working, and
T005 and T006 keep the effort type out of every request). If a row fails, add a fix task to
this phase.

- [ ] T014 [US2] [Manual] Run quickstart § 3 rows 9–12 on the SE (1st generation) and record
  them in `specs/003-apple-watch-se-support/validation.md`. The rows are: a first workout on
  a fresh install, a workout started from the phone, an hour with the wrist lowered, and
  three workouts of 30+ minutes, one started on the phone. In row 9 also note that the
  Apple Health request lists no effort item. Depends on T011.

**Checkpoint**: Workouts recorded on the SE (1st generation) reach Apple Health and the phone's
Workouts list (SC-004).

---

## Phase 5: User Story 3 - Feel the end of a timed round on the wrist (Priority: P2)

**Goal**: The time-up buzz and notification reach an SE (1st generation) at the same moment
as a current watch.

**Independent Test**: The fallback path on the simulator first (T015), then
[quickstart.md](quickstart.md) § 3, rows 15–17, on the watch.

- [ ] T015 [US3] On the watchOS 26 simulator paired with an iOS 26 simulator, launch
  `RekkertWatch` with `-rekkert-observation-fallback` (from T008). Start a timed Winner court
  round of 1 minute. Check that when it runs out the watch buzzes and shows time is up. Check
  that adding time and letting it run out again rings again. Repeat without the argument to
  confirm the `Observations` path is unchanged. Record both in
  `specs/003-apple-watch-se-support/validation.md`. Depends on T009.
- [ ] T016 [US3] [Manual] Run quickstart § 3 rows 15–17 on the SE (1st generation) beside a
  current watch on the same session, with the app in front, with the wrist lowered, and with
  time added after it ran out. Record them in
  `specs/003-apple-watch-se-support/validation.md`. Depends on T011.

**Checkpoint**: The SE (1st generation) buzzes within 2 s of a current watch (SC-005).

---

## Phase 6: User Story 4 - Rate how hard it was (Priority: P2)

**Goal**: A rating for a workout recorded on watchOS 10 lands in Rekkert's history only. What
Rekkert says and asks about Apple Health matches that, from one tested rule in
`RekkertCore` (D-3, D-4).

**Independent Test**: `swift test` (T017–T018), then [quickstart.md](quickstart.md) § 3,
rows 13–14, plus row 9's effort note from T014.

### Tests for User Story 4 (write first; they must fail before T018)

- [X] T017 [US4] Extend `Packages/RekkertKit/Tests/RekkertCoreTests/HealthDisclosureTests.swift`
  (Swift Testing).
  - Add `theWatchOnWatchOS10LeavesEffortOut`. It expects:
    - `HealthDisclosure.saved(on: .watch, effortInAppleHealth: false) == [.workout, .activeEnergy, .restingEnergy]`;
    - `HealthDisclosure.read(on: .watch, effortInAppleHealth: false) == [.heartRate, .activeEnergy, .restingEnergy, .restingHeartRate, .dateOfBirth, .workout]`.
  - Add `thePhoneIsTheSameEitherWay`. For both `true` and `false`, it expects `saved(on: .phone, …) == [.workout]` and
    `read(on: .phone, …) == []`.
  - In `everyKindSaysWhatItIsAndWhy`, change the expected `.effort` reason to exactly
    `"How hard you rated it, on the 1–10 scale. From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health."`.
  - Leave `theWatchSavesAndReadsWhatItAlwaysDid` and `thePageListsEverythingAndNothingElse`
    unchanged. They pin the default.
  - Run `swift test --package-path Packages/RekkertKit` and confirm the new and changed tests
    fail.

### Implementation for User Story 4

- [X] T018 [US4] In `Packages/RekkertKit/Sources/RekkertCore/Health/HealthDisclosure.swift`:
  - Add `effortInAppleHealth: Bool = true` to `saved(on:)` and `read(on:)`. When it is
    `false`, leave `.effort` out of the result and keep every other kind in its current
    order (data-model.md § Apple Health disclosure rule).
  - Change `HealthData.effort.reason` to the string quoted in T017.
  - Run `swift test --package-path Packages/RekkertKit`. Everything passes, including
    `HealthWordingTests`. Depends on T017.
- [X] T019 [US4] In `Shared/HealthTypes.swift`, have `HealthDisclosure.toShare(on:)` and
  `toRead(on:)` pass `effortInAppleHealth: HealthData.effort.objectType != nil` to the core.
  That is `false` only on a watch below watchOS 11, given T006. This way `askStatus(on:)`
  and the watch's `WorkoutController.shared`/`.read` all follow the core rule. Depends on T006
  and T018.
- [X] T020 [P] [US4] In `docs/privacy/index.html`, in the "Your workouts, to Apple Health and
  to your own iPhone" paragraph (~line 124), replace "and, if you give one, how hard you rated
  it," with the wording in `specs/003-apple-watch-se-support/contracts/apple-health-access.md`
  § Privacy page, including its added sentence. Update the dateline's "Last updated" (~line
  94) to today's date.
- [X] T021 [P] [US4] In `fastlane/metadata/review_information/notes.txt` (line 10), apply the
  Before → After change in `specs/003-apple-watch-se-support/contracts/apple-health-access.md`
  § App Review notes. Then confirm that
  `wc -m fastlane/metadata/review_information/notes.txt` is under 4000.
- [X] T022 [US4] Rebuild (`mise exec -- tuist generate --no-open` and `scripts/verify.sh`).
  On the iOS 26 simulator, open Settings › Apple Health and confirm the Effort row shows the
  new sentence under both "Saved to Apple Health" and "Read from Apple Health". Record it in
  `specs/003-apple-watch-se-support/validation.md`. Depends on T018 and T019.
- [ ] T023 [US4] [Manual] Run quickstart § 3 rows 13–14 on the SE (1st generation). Rate one
  workout on the watch and one on the phone. Check that both show in the phone's Workouts
  list and that neither has an effort rating from Rekkert in Fitness or Apple Health. Check
  that the phone's Apple Health page shows the watchOS 10 sentence. Record the results in
  `specs/003-apple-watch-se-support/validation.md`. Depends on T011 and T022.

**Checkpoint**: Ratings from watchOS 10 stay in Rekkert, and every word about Apple Health
says so (SC-009, FR-009).

---

## Phase 7: User Story 5 - Keep the SE (1st generation) working after this release (Priority: P3)

**Goal**: The gate fails on any change that would drop watchOS 10 (FR-012, D-7).

**Independent Test**: [quickstart.md](quickstart.md) § 1, the SC-008 trial.

- [X] T024 [US5] In `scripts/verify.sh`, add a step after the "Assert the watch may record a
  workout" block (after `check 'NSHealthUpdateUsageDescription'`, ~line 46) and before
  "Assert the iPhone app may look at the local network".
  - It prints `==> Assert the watch app still installs on watchOS 10`.
  - It reads `MinimumOSVersion` from `$plist` with `plutil -extract MinimumOSVersion raw -o -`.
  - On a match it prints `  ok: "MinimumOSVersion" => "10.0"`. Otherwise it prints
    `FAIL: the watch app's minimum is <found>, not watchOS 10.0 — it would no longer install on Apple Watch SE (1st generation), Series 4 or Series 5`
    and exits 1.
  - Add a two-line comment above the step saying why: losing the floor fails silently, so
    the app just stops being offered to those watches.
  - Run `scripts/verify.sh` and confirm it passes.
- [X] T025 [US5] Run the SC-008 trial exactly as in [quickstart.md](quickstart.md) § 1:
  - `jj new -m "trial: raise the watch floor"`;
  - change `.watchOS("10.0")` to `.watchOS("11.0")` in `Project.swift`;
  - run `scripts/verify.sh` and confirm it fails at the new step with the message from T024;
  - `jj abandon @`.

  Record the result in `specs/003-apple-watch-se-support/validation.md`. Depends on T024.

**Checkpoint**: Dropping the floor turns the gate red, and the failure names the SE (1st
generation) (SC-008).

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T026 [P] In `README.md`, after the opening paragraph (which ends "…if you ask it to."),
  add a sentence. It says the iPhone app needs iOS 26 and the watch app runs on watchOS 10 or
  later, so it reaches the Apple Watch SE (1st generation), Series 4 and Series 5, which
  cannot update past watchOS 10 (FR-013).
- [ ] T027 Run [quickstart.md](quickstart.md) § 2 on the watchOS 26 simulator: scoring, a
  workout with a rating that reaches Apple Health, and a timed round. This confirms nothing
  changed on current watches (FR-010, SC-007). Record it in
  `specs/003-apple-watch-se-support/validation.md`. Depends on T009 and T019.
- [ ] T028 [Manual] Run [quickstart.md](quickstart.md) § 3 row 18: start the SE (1st
  generation) on a full charge and play a 2-hour session scored on the wrist with a workout
  running throughout. At least 40% battery should be left (SC-006). Record the start and end
  battery in `specs/003-apple-watch-se-support/validation.md`. Depends on T011.
- [X] T029 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh` one last
  time. Check [quickstart.md](quickstart.md) § 4 (README, privacy page, review notes under
  4000 characters) and fill in the § 4 section of
  `specs/003-apple-watch-se-support/validation.md`.
- [ ] T030 [Manual] After the next App Store Connect upload, confirm that the App Store
  page's compatibility line for Apple Watch reads watchOS 10.0 or later (FR-013). Record it in
  `specs/003-apple-watch-se-support/validation.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: none. It goes first so that no commit lowers the floor against the
  constitution.
- **Foundational (T002–T009)**: after T001. It blocks every story, because nothing installs
  on watchOS 10 before T009.
- **US1 (T010–T013)**: after T009. T011 (installing on the watch) unblocks every [Manual]
  row in every later story.
- **US2 (T014)**: after T011.
- **US3 (T015–T016)**: T015 after T009; T016 after T011.
- **US4 (T017–T023)**: T017 and T018 need only T001 and can run alongside Phase 2.
  T019 needs T006 and T018. T020 and T021 can be done at any time. T022 needs T019. T023
  needs T011 and T022.
- **US5 (T024–T025)**: after T009. It does not depend on any other story.
- **Polish (T026–T030)**: T026 at any time. T027 after T019. T028 after T011. T029 last.
  T030 after a release upload.

### User Story Dependencies

- **US1, US2, US3**: their code is all in Phase 2. They are independent of each other, and
  each is verified on its own rows.
- **US4**: independent of US1–US3. Its core change (T017–T018) is the only part with a test
  suite.
- **US5**: independent. It is only a gate.

### Within Each Phase

- T004 → T005 (same file).
- T007 → T008.
- T017 fails before T018 passes, then T019.

### Parallel Opportunities

- Phase 2: T002, T003, T004, T006 and T007 touch different files. T005 follows T004, and T008
  follows T007.
- T017 and T018 (the `RekkertCore` tests and the change) can run while Phase 2 is under way,
  since `swift test` runs on macOS whatever the watch floor is.
- T020, T021 and T026 are document edits that can run at any time.
- All [Manual] rows (T011–T014, T016, T023, T028) can be done in one sitting at a court once
  T011 is installed.

---

## Parallel Example: Phase 2

```text
Task: "T002 Lower RekkertKit's watchOS platform to .v10 in Packages/RekkertKit/Package.swift"
Task: "T003 Lower RekkertWatch to .watchOS(\"10.0\") in Project.swift"
Task: "T004 Replace Mutex with OSAllocatedUnfairLock in WatchApp/Sources/WorkoutController.swift"
Task: "T006 Make HealthData.objectType optional in Shared/HealthTypes.swift"
Task: "T007 Create Shared/ObservationChanges.swift"
```

## Parallel Example: User Story 4

```text
Task: "T017 Write the watchOS 10 disclosure tests in Packages/RekkertKit/Tests/RekkertCoreTests/HealthDisclosureTests.swift"
Task: "T020 Qualify the effort sentence in docs/privacy/index.html"
Task: "T021 Qualify the effort sentence in fastlane/metadata/review_information/notes.txt"
```

---

## Implementation Strategy

### MVP first (User Story 1)

1. T001: amend the constitution.
2. T002–T009: the watch app builds at watchOS 10 and `verify.sh` passes.
3. T010–T013: install on the SE (1st generation) and score every mode.
4. **Stop and validate**: rows 1–8 pass, and an SE (1st generation) owner can score from the
   wrist.

### Incremental delivery

1. MVP as above.
2. US2 (T014): workouts are verified. No code is needed beyond Phase 2.
3. US5 (T024–T025): guard the floor before anything else lands on top of it. It is cheap,
   so do it early despite P3.
4. US4 (T017–T023): the rule, wording and docs for effort ratings.
5. US3 (T015–T016): the alarm fallback is verified, first on the simulator, then on the
   wrist.
6. Polish (T026–T030): the README, the regression on current watches, battery, the final
   gate, and the App Store check.

The first TestFlight build that reaches watchOS 10 watches should include US4 (T018–T021).
Before that, the phone's Apple Health page and the privacy page still say every watch saves
the rating to Apple Health, which would be untrue for these watches.

---

## Notes

- Commit with jj in the conventional style the history uses (`feat:`, `fix:`, `docs:`, `test:`,
  `chore:`), one logical group at a time. For example, T001 alone, Phase 2 as one or two
  commits, and T017–T019 together.
- No AI attribution trailers in commit messages.
- Mark each task `[X]` here when done. [Manual] tasks are marked by whoever ran them, with the
  result in `validation.md`.
- A failing on-wrist row becomes a new task in its story's phase. Do not paper over it in
  `validation.md`.
