# Contract: What App Review Gets

The submission after build 70 carries three things:

- the review notes below, replacing the "WORKOUTS (HEALTHKIT)" part of
  `fastlane/metadata/review_information/notes.txt`;
- a screen recording, attached in App Store Connect › App Review Information;
- a reply to the build 70 rejection with the same notes.

All three are done by hand (research D-10).

## Review notes: the Apple Health part

The part is written to be read cold. It leads with the path that needs nothing but the
device under review. "HealthKit" appears once, in the heading, so the reviewer can match it
to the guideline.

```text
APPLE HEALTH (HEALTHKIT)
Rekkert uses Apple Health for one thing: workouts. A workout the user starts is recorded on the Apple Watch and saved to Apple Health as indoor tennis, the nearest activity Apple Health has to padel, with its active and resting energy and an effort rating if the user gives one. While it runs, and once when it ends, the watch reads heart rate and energy; to show heart-rate zones it also reads the user's date of birth and latest resting heart rate. Nothing is read unless a workout is started, and nothing read leaves the user's own iPhone and Apple Watch.

WHERE TO SEE IT, WITH NO APPLE WATCH (any iPhone or iPad)
Tap the gear at the top right of the start screen. The Apple Health section, with the Apple Health icon, says what Rekkert does with Apple Health and why this device cannot record a workout. Tap "What Rekkert saves and reads" for the full list and where to change access.

WHERE TO SEE IT, WITH A PAIRED APPLE WATCH
- Start screen: the Workout section, marked with the Apple Health icon. Tap "Start a workout". The first time, Rekkert explains what Apple Health will ask, then Apple Health asks.
- In a match: "..." menu > "Start workout", subtitled "Saves to Apple Health".
- Settings > Workout on your watch: start and stop a workout with each match. The footer says the workouts go to Apple Health.
- On the watch: "Start workout" on the menu page next to the score, and on the idle screen, captioned "Saves to Apple Health".
- Afterwards: start screen > Workouts lists them and says they stay in Apple Health, each workout's page shows "Saved in: Apple Health", and the workout is in the Apple Health app.

A screen recording on a physical iPhone and Apple Watch showing each of these is attached.
```

The rest of `notes.txt` (Getting started, Apple Watch, Sharing, TV, Live Activity, Encryption)
is unchanged.

Before submitting, check two things on the real watch during T041:

- The menu page sits next to the score, and the notes don't say which side. If the side is
  worth naming, use the direction the watch actually swipes.
- Someone who has not used Rekkert, with an iPhone and no watch, reaches the Apple Health
  section on the first try from these notes alone (SC-006).

## Recording: shot list

Record on a physical iPhone with a paired Apple Watch, on a fresh install, with the system
screen recorder. Show the watch with a second phone's camera, or the watch's own screenshots
cut in. Target: under three minutes (SC-007).

1. **No-watch path first.** Open Rekkert, tap the gear, and stop on the Apple Health section
   (P-01) for three seconds. Open "What Rekkert saves and reads" (P-02) and scroll through it
   slowly.
2. **Back to the start screen.** Show the Workout section header with the icon, and its
   footer (P-03).
3. **Tap Start a workout.** The explainer appears (P-10). Tap Continue. The Apple Health
   sheet appears (P-11). Allow.
4. **On the watch.** The workout is running. Show "Saving to Apple Health" on the workout
   page (W-03). Show Start workout's caption on the idle screen of a second, fresh start
   (W-01).
5. **Start a match on the phone.** Open "...", show "Stop workout" and, after stopping,
   "Start workout · Saves to Apple Health" (P-04).
6. **Settings › Workout on your watch.** Set "When a match starts" to Ask me, and show the
   footer (P-06).
7. **The result.** Open Workouts (P-07) and a workout (P-08). Then open the Apple Health app
   and show the same workout under Workouts.
8. **End on Settings › Apple Health again** (P-01).

The watch's own explainer (W-05) is shown in a separate short clip from a fresh watch
install if it does not come up in step 4: a phone-first start asks on the phone.
