# Bug Fix: Starting a workout from the iPhone is slow and sometimes never starts

- **Slug**: phone-workout-start-slow
- **Fixed**: 2026-11-01
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The watch no longer parks a phone-started workout behind its Health explainer. It starts on access already given, or reports `.idle` to the phone. The phone now shows a "Starting…" state, reports a failure if the watch says `.idle` or stays silent for 15 s, and skips a redundant permission request. When the paired phone becomes reachable, the watch repeats its current workout state straight away instead of waiting for the phone's hello.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `WatchApp/Sources/WorkoutController.swift` | modified | `handle(_:)` no longer calls `start()`. If a workout is already running, it says so again. Otherwise it calls `begin()` directly. On failure it reports through `stopped(with:)` (which publishes `.idle`). If access was refused, it also queues `prepare()` for the next time the app is opened. |
| `App/Sources/WorkoutController.swift` | modified | New `isStarting` and a 15 s `patience` task. `start()` ignores presses while starting. `.running` or `.paused` ends the starting state. `.idle` during a start shows "Couldn't start on your Apple Watch. Check Rekkert there." Silence shows "No word from your Apple Watch yet. Check Rekkert there." `requestAuthorization` is skipped when `askStatus` has just said `.alreadyAsked`. |
| `App/Sources/Views/HomeView.swift` | modified | While starting, the button reads "Starting a workout…" / "Waiting for your Apple Watch" and is disabled. |
| `App/Sources/Views/MatchOptionsMenu.swift` | modified | While starting, the menu item reads "Starting workout…" and is disabled. |
| `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift` | modified | `consumeReachability()` calls `shareWorkoutOnReconnect()` when the pair goes from unreachable (or unknown) to reachable. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift` | added test | `aRunningSaidOutOfReachIsSaidAgainOnceThePhoneIsBack` |

## Diff Highlights (optional)

Watch, phone-started workout:

```swift
func handle(_ configuration: HKWorkoutConfiguration) {
    guard isAvailable else { return }
    if isTracking, let startedAt {
        let elapsed = builder?.elapsedTime ?? Date().timeIntervalSince(startedAt)
        publish?(isPaused ? .paused(since: startedAt, elapsed: elapsed) : .running(since: startedAt))
        return
    }
    guard !isStarting else { return }
    failure = nil
    do {
        try begin()
    } catch {
        stopped(with: error)
        if (error as? HKError)?.code == .errorAuthorizationDenied { prepare() }
    }
}
```

Store, on the pair coming back:

```swift
recordedPairReachable = isPairReachable
if isPairReachable { shareWorkoutOnReconnect() }
```

## Tests Added or Updated

- `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift::aRunningSaidOutOfReachIsSaidAgainOnceThePhoneIsBack`: a watch store behind a fan-out whose paired link is down sends `.running`. The phone does not get it. When the link comes up, the phone receives `.running` without having sent a hello. With the new line in `consumeReachability()` removed, this test fails (times out after 5 s with nothing received). With it in place, the test passes.
- The existing `aRatingIsNotRepeatedOnReconnect` and `aReconnectIsToldTheLastThingSaidRatherThanTheFirst` still pass. The re-announce still sends only the latest state, never a request.

## Local Verification

- Commands run:
  - `swift test --package-path Packages/RekkertKit --filter WorkoutSyncTests` → 13/13 passed.
  - Same filter on the new test with the `MatchStore` line removed → failed as expected (1 issue). The line was restored afterwards.
  - `swift test --package-path Packages/RekkertKit` → RekkertSyncTests 495 passed, RekkertCoreTests 788 passed. This includes `HealthWordingTests`: the new phone strings don't mention Health.
  - `mise exec -- tuist generate --no-open` → project generated.
  - `xcodebuild -scheme Rekkert -destination 'generic/platform=iOS Simulator' build` → exit 0. The iOS app, with the watch app embedded, builds with no warnings in the changed files.
  - `xcodebuild -scheme RekkertWatch -destination 'generic/platform=watchOS Simulator' build` → exit 0.
- Manual checks: none. There is no app test target, and starting a workout needs a paired iPhone and Apple Watch. The phone and watch changes in `WorkoutController` and the two views are covered only by compiling, not by tests.

## Deviations from Assessment

- **No `HealthAsk` rule in `RekkertCore`; `HealthAskTests` unchanged.** Once the phone path skips the explainer, the only remaining decision is "is workout sharing authorized?", and `begin()` already makes that check. A core function would just pass a boolean through, with nothing worth testing. The watch wiring sits in an app target with no tests, so it is listed below for a device check.
- **Explainer for a refused start is `.prepare`, not `.start`.** The assessment said to keep `explaining = .start` for the next app open. That would start a workout whenever someone later taps Continue on the watch, possibly hours after the phone press. Parking `.prepare` asks for access without starting anything.
- **Scope addition: the watch repeats its state if a phone start arrives while a workout is already running.** Without this, a phone that missed an earlier `.running` would press Start, hear nothing (the old code returned silently), and show the new 15 s "No word" message over a workout that is running. This is a few lines inside `handle(_:)`, a file the assessment already listed.
- **`.idle` during a start reports a failure straight away.** The assessment said to clear the starting state on `.idle`. It now also sets the phone's `failure`, so a refusal from the watch (Path B) shows immediately instead of after the 15 s timeout. If a stale `.idle` arrives just before `.running`, the message is cleared when `.running` lands (`heard(.running)` sets `failure = nil`).
- **Re-announce trigger.** It hangs off the pair-reachability change `consumeReachability()` already tracks for the sharing record (`recordedPairReachable`), so it fires only when the pair comes up, not on every fan-out reachability event.

## Follow-ups

- Device check (needed for `/speckit-bug-test`):
  - Phone start with the watch app closed and the watch's Health request status not yet answered → workout starts on the wrist and the phone flips to "Stop the workout".
  - Phone start while Apple's Workout app holds the session → phone shows "Couldn't start on your Apple Watch…" within a couple of seconds.
  - Phone start with the watch out of range → phone shows "No word from your Apple Watch yet…" after 15 s.
- Read types the watch has never asked for (heart rate, zones) aren't requested on a phone-started workout, so the heart-rate glyph may stay empty until the watch app is opened. `AppModel.becameActive()` calls `prepare()` only when `workoutOnMatchStart != .off`. Consider calling it whenever the watch status isn't `.alreadyAsked`. This is the product question left open in the assessment.
- A `WorkoutSignal` case that carries the watch's reason (another workout, access off) would let the phone say exactly what happened instead of "Check Rekkert there". It needs a wire change and `WireCompatibilityTests`.
