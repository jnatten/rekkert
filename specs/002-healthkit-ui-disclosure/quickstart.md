# Quickstart: Proving Apple Health Is Named Everywhere

How to show this feature works, from the fastest check to the real devices. The words each screen must show are in
[contracts/identification-points.md](contracts/identification-points.md). What App Review is
told is in [contracts/review-notes.md](contracts/review-notes.md).

## Prerequisites

- Xcode 26 and `mise` (it pins Tuist), as in the README's Getting started.
- Before any build that should ship, Apple's Apple Health icon from Apple Design Resources,
  added as `AppleHealth.imageset` to both asset catalogs (research D-3). `verify.sh` fails
  without it.
- For the real-device steps: an iPhone on iOS 26 with a paired Apple Watch on watchOS 26,
  with Rekkert deleted from both first, so every first-time prompt appears.

## 1. Device-free tests

```sh
swift test --package-path Packages/RekkertKit
```

**Expected**: green, including these suites:

- `HealthDisclosureTests`: the saved and read lists per device equal the lists before this
  feature, and every kind has words.
- `HealthReachTests`: every combination of the four inputs. `.canRecord` holds exactly when
  the old `isAvailable` expression was true.
- `HealthAskTests`: explains for `wouldAsk` and `unknown`, never for `alreadyAsked`.
- `HelpTests`: the "Apple Health" help item and README section line up.
- The wording scan: no user-facing "Health" without "Apple", no "HealthKit", no "the Health
  app".

## 2. The gate

```sh
./scripts/verify.sh
```

**Expected**: green. Besides today's checks, the "Assert both apps may talk to Health" step
prints two new results:

- `ok:` for each of the four Health usage strings containing "Apple Health";
- `ok:` for `AppleHealth.imageset` holding an image in each app.

## 3. Simulator: no watch, and iPad (SC-002)

On an unpaired iPhone simulator and an iPad simulator, with a debug build installed:

```sh
xcrun simctl launch <udid> dev.natten.rekkert -rekkert-demo-settings
```

**Expected on iPhone**:

- Settings shows the Apple Health section with the icon and name in its header.
- The summary reads as in P-01, and the reach line says recording needs a paired Apple Watch.
- There is no "Workout on your watch" section.
- Tapping "What Rekkert saves and reads" opens the page (P-02). It lists four saved kinds and
  seven read kinds, with "When", "Where it goes" and "Change access".

**Expected on iPad**: the same, with the iPad reach line.

For a screenshot of the page itself, use the new `-rekkert-demo-apple-health` flag.

Then do it by hand on the unpaired iPhone: from a fresh launch, tap the gear. Note the time
it takes and the taps; both must be within SC-002 (30 seconds, two taps).

## 4. Simulator: with a watch

Pair the simulators as in the README (`xcrun simctl pair`). Install both apps, deleting any
earlier install first.

1. **Home.** The Workout section's header shows the mark, and its footer says Apple Health
   (P-03).
2. **Start a workout.** The explainer sheet appears (P-10). Check it:
   - **Not now**: no Apple Health sheet appears and no workout starts. Pressing again shows
     the explainer again.
   - **Continue**: the Apple Health sheet appears. Its text names Apple Health (P-11).
3. **After the sheet.** Start a workout again: no explainer this time.
4. **Settings.** Set "When a match starts" to Ask me on a fresh install. The explainer
   appears. Not now leaves the picker on Do nothing; Continue sets it.
5. **In a match.** Open "...": Start workout carries "Saves to Apple Health" (P-04).
6. **On the watch.** Run `-rekkert-demo-watch-page menu`: the caption under Start workout
   reads "Saves to Apple Health" (W-01). `-rekkert-demo-workout` shows the workout page
   caption (W-03), and `-rekkert-demo-health-explainer` shows the watch explainer (W-05).
7. **Demo data.** Run `-rekkert-demo-workouts` and `-rekkert-demo-workout`. The Workouts list
   footer (P-07), "Saved in · Apple Health" (P-08) and the timeline's heart-rate caption
   (P-09) all show.

Simulators cannot record a real workout. That is the next section's job.

## 5. Real devices: confirm, then record

**R-1. Fresh install.** Delete Rekkert from the iPhone and the watch. Install a TestFlight or
release-configuration build of this branch.

**R-2. The full flow.** Walk through the steps from section 4 on the real pair. Then:

- Start a workout from the phone and confirm it runs on the watch.
- Stop it, and confirm it appears in Rekkert's Workouts and in the Apple Health app.
- Turn access off in the system's settings and press Start workout on the watch. The failure
  text matches W-04.

**R-3. Confirm the access paths.** On iOS 26, find where Rekkert's Apple Health access is
changed:

- the Settings app route;
- the Apple Health app's own route, which iOS 26.4's redesign may have moved;
- whether the watch app's access is listed there, or on the watch.

Update the *Draft* copy in P-02 and W-04, and `HealthDisclosure.changeAccess`, to the paths
actually found, before the build that is submitted.

**R-4. Tick every point.** Go through every P- and W- point in the contract on the real
pair (SC-003). No screen recording is made for App Review.

**R-5. Submit.** This is done by hand in App Store Connect (research D-10):

- paste the review notes;
- reply to the build 70 rejection with the same text;
- submit the build.

## 6. Done when

- Sections 1 and 2 are green.
- Section 3 passes on iPhone and iPad.
- Section 4 passes.
- R-2 and R-3 are done, with the drafts settled.
- Every identification point was seen on the real pair.
- The next build is not rejected under 2.5.1 (SC-001).
