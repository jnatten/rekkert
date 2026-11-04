# Research: Rekkert on Apple Watch SE (1st generation)

**Feature**: `003-apple-watch-se-support` | **Date**: 2026-11-04

All findings were checked against the code at `uwrmmsmp` (`b4f5b86`), the base of this branch.
The tools were Xcode 27.0 (27A266a) with the watchOS 27.0 SDK.

## What the platform and the code say

- **R-1: The SE (1st generation) stops at watchOS 10.6.1.** Apple's compatibility table lists
  it as "watchOS 7 to watchOS 10.6.1". Series 4 and Series 5 end at the same version
  ([Apple](https://support.apple.com/en-us/118490)). watchOS 11 and later need a Series 6, an
  SE (2nd generation) or newer.
- **R-2: Two places pin the watch to watchOS 26.** `Project.swift` gives `RekkertWatch`
  `deploymentTargets: .watchOS("26.0")`. `Packages/RekkertKit/Package.swift` declares
  `.watchOS(.v26)`. The iPhone app and widget extension declare iOS 26, and macOS 26 is only
  there for `swift test`.
- **R-3: A trial build at watchOS 10.0 fails in four places, all in the watch app or
  `Shared/`.** A scratch copy had both pins lowered to 10. `RekkertCore` and `RekkertSync`
  compiled without a change. The failures:

  | Where | What | Needs |
  |---|---|---|
  | `WatchApp/Sources/WorkoutController.swift:296–345` | Writing the effort rating: `HKQuantityType(.workoutEffortScore)`, `predicateForWorkoutEffortSamplesRelated`, `.appleEffortScore()`, `relateWorkoutEffortSample` | watchOS 11 |
  | `Shared/HealthTypes.swift:10` | `HealthData.effort` mapped to `.workoutEffortScore` for the permission request | watchOS 11 |
  | `WatchApp/Sources/WorkoutController.swift:886–888` | `Mutex` (Synchronization) guarding a one-shot continuation in `first(of:orNilAfter:)` | watchOS 11 |
  | `Shared/RoundAlarmFollower.swift:30` | `Observations` following the store for the time-up alarm | watchOS 26 |

  The first pass stopped scheduling compiles after the first failing file. That hid
  `HealthTypes.swift` and left two watch views uncompiled. A second pass, with the other three
  stubbed out, found `HealthTypes.swift`. A third pass, with all four stubbed, built cleanly.
  The iPhone app then built, with the watch app embedded and `MinimumOSVersion` set to `10.0`.
  The four rows above are therefore the complete list of what does not build. They are not
  a list of everything that might behave differently at runtime (R-9).
- **R-4: The rating already reaches Rekkert's history without Apple Health.** On the watch,
  `rate(_:)` publishes `.rated(workoutID:effort:)` and then calls `save`, which queues the
  Apple Health write. The store applies `.rated` to its own `WorkoutRecord.effort`
  (`MatchStore.swift:1721`), and that record is what the phone's Workouts list shows. A rating
  given on the phone is set on the record directly (`AppModel.rateWorkout`, `AppModel.swift:804`)
  and sent to the watch. The watch then only writes it to Apple Health (`heard(.rated)` →
  `save`). The phone never reads a rating back out of Apple Health. On watchOS 10, then, the
  only thing to stop is the watch's write to Apple Health, plus the permission it asks for
  (`writeWaitingRatings()` → `ask(.ratings)`, called from `AppModel.swift:722`).
- **R-5: One disclosure drives both the words and the permission request.**
  `HealthDisclosure` (`RekkertCore/Health/HealthDisclosure.swift`) lists `.effort` as saved and
  read on the watch. The phone's Apple Health page (`App/Sources/Views/AppleHealthView.swift`)
  shows `saved(on: .phone) + saved(on: .watch)` and `read(on: .watch)`, using each kind's
  `reason`. The watch builds its request from the same lists (`Shared/HealthTypes.swift`,
  `WorkoutController.shared`/`.read`). `HealthDisclosureTests` pins the lists and every reason
  string. `HealthWordingTests` keeps every literal to "Apple Health". The phone has no way to
  know which watchOS its watch runs: nothing on the wire carries it.
- **R-6: Heart-rate zone times already depend on watchOS 27.** Zones are the person's own
  bands on watchOS 27 (`preferredZones()`). Below that they are estimated from date of birth
  and resting heart rate (`estimatedZones()`), and both can be read on watchOS 10. The time
  spent in each zone comes only from a watchOS 27 zone group (`zoneTimes(of:)`, the live
  reading at line 854). A watchOS 26 watch records none today. An SE (1st generation) will
  behave exactly like a watchOS 26 watch here, and FR-006 in the spec was corrected to say so.
- **R-7: The round alarm follows the store through `Observations`.**
  `RoundAlarmFollower.follow(_:)` builds `Observations { Situation(session:state:) }` and
  iterates it. Everything else in the follower (local notifications, the
  `WKInterfaceDevice` haptic, `Task.sleep`) is available on watchOS 10. The `Observation`
  module itself (`@Observable`, `withObservationTracking`) is available from watchOS 10.
- **R-8: `Mutex` is a one-shot guard.** `first(of:orNilAfter:)` races a HealthKit call against
  a timeout. Whichever finishes first resumes the continuation, and the lock makes sure the
  other one finds nothing to resume.
- **R-9: What the trial build cannot show.** It cannot show how the screens look and lay out
  on watchOS 10, whose system styling predates watchOS 26, or how fast the S5 chip is. It also
  cannot show whether HealthKit, WatchConnectivity and CoreBluetooth behave on watchOS 10 the
  way they do on 26. All of the APIs compile at 10.0. Only a real watch can show the rest.
- **R-10: Tooling.** Xcode 27 has only the watchOS 26.0 simulator runtime installed, and it
  has no SE (1st generation), Series 4 or Series 5 device type. It accepts 10.0 as a
  deployment target without a warning. Two things are unverified: whether Xcode 27 can still
  download a watchOS 10 simulator runtime, and whether it can install on and debug a
  watchOS 10.6.1 watch.
- **R-11: Pairing.** Apple publishes only a minimum iOS for these watches. Community reports
  say they still pair with iPhones on iOS 26, with occasional trouble
  ([MacRumors](https://forums.macrumors.com/threads/watchos-10-compatible-with-ios-26-2.2475638),
  [Apple Community](https://discussionskorea.apple.com/thread/256258677)).
- **R-12: Where the docs promise an effort rating in Apple Health.**
  `docs/privacy/index.html:124` says the watch saves it, as does
  `fastlane/metadata/review_information/notes.txt:10`. The README states no device
  requirements. The App Store description states no minimum watchOS; the store shows the
  minimum itself, from the build.
- **R-13: The constitution pins the platforms.** Its Platform & Technical Constraints say
  "Targets build for iOS, watchOS, and macOS 26."

## Decisions

### D-1: The watch's floor becomes watchOS 10.0

- **Decision**: Set `RekkertWatch` to `.watchOS("10.0")` and `RekkertKit` to `.watchOS(.v10)`.
  iOS and macOS stay at 26.
- **Rationale**: 10.6.1 is the last version for the SE (1st generation). 10.0 also covers a
  watch that never took a point release, and the trial build found nothing that needs 10.1
  to 10.6.
- **Alternatives considered**: 10.6 would shut out watches that missed an update and gain
  nothing. 11 would not include the SE (1st generation) at all.

### D-2: On watchOS 10 the watch keeps the rating out of Apple Health

- **Decision**: `save(_:to:)` returns before queueing anything unless watchOS 11 is
  available. `enqueue`, `writeWaiting` and `write` become `@available(watchOS 11, *)`, and
  `writeWaitingRatings()` does nothing below watchOS 11, so `ask(.ratings)` never fires there.
  The `.rated` signal is unchanged and still reaches the store, so the rating lands in
  Rekkert's history (R-4).
- **Rationale**: This is the answer recorded in the spec's clarification. It touches only the
  watch shell, and nothing on the wire changes.
- **Alternatives considered**: Having the phone write the rating to Apple Health (option B),
  or not asking for a rating at all (option C). Both were turned down in the clarification.

### D-3: The rule lives in `HealthDisclosure`, and the watch passes in what its Apple Health can hold

- **Decision**: `HealthDisclosure.saved(on:)` and `read(on:)` gain an
  `effortInAppleHealth: Bool = true` parameter, which leaves `.effort` out when it is false.
  The watch passes `true` only when `#available(watchOS 11, *)`. `HealthData.objectType`
  becomes optional and returns `nil` for `.effort` below watchOS 11. `toShare` and `toRead`
  use `compactMap`, so the type is never named where it does not exist.
- **Rationale**: Principle I. What the watch saves is a rule, so it belongs in `RekkertCore`
  and can be tested there (Principle III). The shell only answers whether this watch's Apple
  Health has a place for effort ratings. The words and the request keep coming from one place,
  which is what feature 002 set up.
- **Alternatives considered**: Filtering in `HealthTypes.swift` alone would put the rule
  outside the core, untested, and let the page and the request drift apart. A new
  `HealthDevice` case for a watchOS 10 watch would spread OS knowledge through every switch
  on the enum.

### D-4: The phone's wording is fixed text, true for every pairing

- **Decision**: `HealthData.effort.reason` becomes "How hard you rated it, on the 1–10 scale.
  From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health." The phone's
  Apple Health page keeps listing effort, now with that sentence. `HealthDisclosureTests`
  pins the new text. The wording passes `HealthWordingTests`: it says "Apple Health" and never
  "Health" on its own.
- **Rationale**: The phone cannot tell which watchOS its watch runs (R-5). Teaching it would
  mean a new message between the devices. That is a wire-format change to weigh against
  Principle II, for one sentence. Fixed text is accurate whichever watch is paired, and it
  meets User Story 4, scenario 2.
- **Alternatives considered**: Having the watch report its Apple Health capability to the
  phone was rejected as a wire change for wording. Hiding the effort row whenever it is
  unknown was rejected because it would be false for every current watch.

### D-5: The round alarm keeps `Observations` where it exists and falls back below watchOS 26

- **Decision**: `follow(_:)` uses `Observations` when `#available(iOS 26, watchOS 26, *)`.
  Below that it uses a small `Shared/` helper that yields the same `Situation` values as an
  `AsyncStream`. The helper registers `withObservationTracking`, reads the new value on the
  next main-actor turn after each change, and registers again. The iPhone always takes the
  first branch.
- **Rationale**: Nothing changes on current devices (FR-010), and tracking has existed since
  watchOS 10 (R-7). `RoundAlarm` in the core already decides when to ring, so the fallback
  only has to deliver every change to it, which "read on the next turn and register again"
  does.
- **Alternatives considered**: Using the fallback everywhere would change behaviour on
  current devices and give up `Observations`' transactional coalescing. Polling on a timer
  costs battery and adds latency at exactly the moment SC-005 measures. Adding a change
  callback to `MatchStore` would push a shell concern into `RekkertSync`.

### D-6: `Mutex` becomes `OSAllocatedUnfairLock`

- **Decision**: In `first(of:orNilAfter:)`, use `OSAllocatedUnfairLock(initialState:)` from
  `os` (watchOS 9 and later) on every watchOS version, and drop `import Synchronization`.
- **Rationale**: The semantics for a one-shot guard are the same (R-8), with one code path
  and no visible change.
- **Alternatives considered**: An availability branch keeping `Mutex` on watchOS 11 would add
  two paths for no gain. An actor would add an async hop to a helper whose whole job is a race.

### D-7: The gate asserts the floor, and the compiler polices everything above it

- **Decision**: `scripts/verify.sh` asserts that the built watch app's `Info.plist` has
  `"MinimumOSVersion" => "10.0"`. The failure message names the SE (1st generation). Using
  something newer than watchOS 10 without `#available` or `@available` is already a compile
  error once the target is 10.0, and verify.sh builds the watch app. Raising only the
  package's watchOS floor fails the app build, because a package newer than its target is an
  error.
- **Rationale**: Principle IV. Losing the floor fails silently: the app just stops being
  offered to those watches. So the gate has to catch it. SC-008 checks this with a trial
  change.
- **Alternatives considered**: A source grep for `.watchOS("…")` would break on formatting and
  say nothing about the built product. CI on a watchOS 10 simulator is not available (R-10).

### D-8: Real hardware is the test bed for anything watch-specific

- **Decision**: The engine and disclosure changes are covered by `swift test`, and the build
  and floor by `verify.sh`. Current-watch behaviour is regression-tested on the watchOS 26
  simulator. Everything the spec's success criteria measure on the SE (1st generation) runs on
  a real SE (1st generation) on watchOS 10, following [quickstart.md](quickstart.md). If Xcode 27
  cannot install on a watchOS 10 watch, an internal TestFlight build is the fallback. Trying a
  watchOS 10 simulator runtime is worthwhile, as a quick layout check if Xcode 27 offers one
  for download, but nothing depends on it.
- **Rationale**: R-9 and R-10.

### D-9: Documents follow the change

- **Decision**:
  - The README gains a short requirements note: iPhone on iOS 26, and an Apple Watch on
    watchOS 10 or later (SE 1st generation, Series 4 and later).
  - The privacy page qualifies the effort sentence and gets a new "Last updated" date.
  - The App Review notes qualify the same sentence.
  - The App Store description is unchanged. The store shows the minimum watchOS from the
    build (FR-013).
- **Rationale**: FR-009 and FR-013. The privacy page and review notes are part of what Rekkert
  tells people about Apple Health.

### D-10: The constitution is amended, not ignored

- **Decision**: Amend Platform & Technical Constraints to: "Targets build for iOS and macOS 26,
  and for watchOS 10 so the watch app reaches the watches that cannot update past it (SE 1st
  generation, Series 4 and 5). Watch code that uses anything newer carries a fallback." Bump
  1.0.0 → 1.1.0 (MINOR: a materially changed rule) with a Sync Impact Report entry. This is
  the first implementation task.
- **Rationale**: Governance requires an amendment for a changed constraint. Without one, every
  later review would flag this feature.

### D-11: Series 4 and Series 5 come along, unverified

- **Decision**: No device restriction. Watches that can install a watchOS 10 app get Rekkert.
  Only the SE (1st generation) is a verification target.
- **Rationale**: The floor is set by watchOS version, not model (R-1), and these watches run
  the same watchOS 10 software.

### D-12: Nothing on the wire changes

- **Decision**: No changes to `Wire`, `WorkoutSignal`, the reducer, version vectors, draws or
  schedules.
- **Rationale**: Principle II. The SE (1st generation) runs the same engine, so convergence
  holds as it does for every other device. FR-003 is verified end to end on the device rather
  than by new rules.
