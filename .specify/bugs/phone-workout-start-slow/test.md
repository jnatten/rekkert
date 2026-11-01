# Bug Verification: Starting a workout from the iPhone is slow and sometimes never starts

- **Slug**: phone-workout-start-slow
- **Tested**: 2026-11-01
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The main symptom (Path A, the regression from `b08f8c2`) reproduces with the pre-fix watch app and is gone with the fix. On the same paired simulators, minutes apart, the pre-fix watch app stalled on its Apple Health explainer and never started a session. The fixed one started a session 0.6 s after the phone's request, and the phone showed it running 2.6 s after the tap. All automated checks pass, and the reporter has since tried the fix on a real iPhone and Apple Watch and says it worked. Path B (the watch refuses the start) was not tested separately; it was not part of the original report.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction, pre-fix (Path A) | Pre-fix watch app (`28c4538`) on the paired watch simulator, fixed phone app, Start workout from the phone's match menu | fail (as expected) | Watch received the workout 0.6 s after the request, then started no session. It sat on the "Rekkert works with Apple Health" explainer. |
| Reproduction, post-fix (Path A) | Same simulators and Apple Health state, fixed watch app (`082bb53`), same steps | pass | Session started 0.6 s after the request. The phone switched to Pause / Stop workout with the heart in the badge, 2.6 s after the tap. |
| Phone "starting" state | Opened the match menu during a start | pass | "Starting workout…", greyed out, in both runs. |
| Phone 15 s timeout | Pre-fix run above: the watch never answered | pass (partly seen) | The menu went back to an enabled "Start workout" within about 20 s. The failure text ("No word from your Apple Watch yet…") shows only on the Home screen, which wasn't on screen. |
| Watch says "running" again when the phone becomes reachable | First fixed run (21:23), watch and phone logs | pass | Watch published "running" while WatchConnectivity reported `reachable: NO`; reachability flipped 11 ms later; the phone's first message from the watch came 2.3 s after that. The logs can't show whether the new resend or the existing resend on the phone's hello delivered it first. |
| Stop from the phone | Stop workout from the match menu, both fixed runs | pass | Watch ended and finished the session. The phone asked "How hard was that?" (skipped). |
| Real devices | Reporter started workouts from a physical iPhone with a physical Apple Watch | pass | Reported as: "seemed to work nicely when trying on physical devices". No timings or details of which starts were tried. |
| Path B (watch refuses: another workout running, or access off) | — | not-run | Needs another app holding the watch's workout session, or Rekkert's access revoked on the simulators. Neither was set up. |
| New test | `swift test --package-path Packages/RekkertKit --filter WorkoutSyncTests` | pass | 13/13, including `aRunningSaidOutOfReachIsSaidAgainOnceThePhoneIsBack`. During the fix this test failed with the new `MatchStore` line removed. |
| Regression suite | `swift test --package-path Packages/RekkertKit` | pass | RekkertSyncTests 495, RekkertCoreTests 788, including `HealthWordingTests` |
| Type-check (app targets) | `xcodebuild` for `Rekkert` (iOS Simulator) and `RekkertWatch` (watchOS Simulator) | pass | Both exit 0. The fixed simulator runs used these builds. The pre-fix build (`28c4538`, throwaway jj workspace, since removed) also exit 0. |
| Lint | — | not-run | No linter or formatter is configured in the repo. |

## Output Excerpts

Pre-fix watch app (stall):

```
21:29:11.794 Rekkert       [HealthKit:workouts] Requesting watch workout app launch with configuration
21:29:12.428 RekkertWatch  [watchkit] Got workout url watchkit:///workout
21:29:12.428 RekkertWatch  [watchkit] Calling handleWorkoutConfiguration: on <SwiftUI.ExtensionDelegate>
(no "Initializing workout session" from RekkertWatch afterwards; watch screen: "Rekkert works with Apple Health")
```

Fixed watch app, same simulators:

```
21:30:09.156 Rekkert       [HealthKit:workouts] Requesting watch workout app launch with configuration
21:30:09.676 RekkertWatch  [WC] WCSessionState reachable: NO
21:30:09.718 RekkertWatch  [watchkit] Calling handleWorkoutConfiguration
21:30:09.731 RekkertWatch  [HealthKit:workouts] <HKWorkoutSession ...> Initializing / Started
21:30:09.756 RekkertWatch  [WC] WCSessionState reachable: YES
21:30:11.733 Rekkert       [WC] handleDictionaryMessageRequest (first message from the watch)
```

Package tests:

```
Test run with 13 tests in 1 suite passed after 0.115 seconds.     (WorkoutSyncTests)
Test run with 495 tests in 74 suites passed after 53.645 seconds.  (RekkertSyncTests)
Test run with 788 tests in 69 suites passed after 0.270 seconds.   (RekkertCoreTests)
```

## Residual Risks

- **Real hardware checked only informally.** The reporter's device check has no timings, and the simulator's 2.6 s says nothing about a cold launch over Bluetooth. The phone now shows that it's waiting, but the system's own launch time is unchanged.
- **Path B not exercised.** The fixed phone's reaction to `.idle` during a start ("Couldn't start on your Apple Watch…") is untested apart from compiling.
- **Simulator explainer was visible.** On the simulator, the stalled explainer was on the watch screen because nothing else was in front. On a real watch with the wrist down it wouldn't be, which is how the original report reads ("sometimes it doesn't start"). The stall itself is the same either way.
- **Apple Health state on the simulators.** Sharing permission came from the phone's grant, and the watch simulator was never asked for its own read types. This was the Path A condition in both runs. Heart rate and zones on a phone-started workout, for a watch that has never been asked, remain the open follow-up from `fix.md`.
- **Test data left on the simulators.** Two short tennis workouts (21:23 and 21:30) were saved to the simulators' Apple Health and Rekkert history. The pre-fix run saved nothing because it never started. The paired iPhone 17 Pro simulator was booted for this and left running.

## Recommendation

Close the bug. The regression is fixed, the before/after on simulators shows it directly, and the reporter confirmed it on real devices. If a start from the phone ever silently fails again, try it while Apple's Workout app holds the session (Path B), which is the one path not tested.
