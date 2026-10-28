# Contract: What App Review Gets

The submission after build 70 carries three things:

- the review notes below, replacing the "WORKOUTS (HEALTHKIT)" part of
  `fastlane/metadata/review_information/notes.txt`;
- one image, `fastlane/review_attachment.png`, uploaded as the App Review attachment by
  `scripts/release.sh --metadata`: the Apple Health section in Settings on an iPhone with no
  watch, beside the explanation before the permission request (see "The attached image"
  below);
- a reply to the build 70 rejection with the same notes.

All three are done by hand (research D-10). No screen recording is submitted: the build changes
the app itself, which is the first of the two ways out Apple offered, and the notes are
what lead the reviewer to every place Apple Health is named.

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

The attached image shows the Apple Health section in Settings on an iPhone with no Apple Watch, and the explanation Rekkert shows before Apple Health's permission request.
```

The rest of `notes.txt` (Getting started, Apple Watch, Sharing, TV, Live Activity, Encryption)
is unchanged.

Before submitting, check two things on the real watch during T041:

- The menu page sits next to the score, and the notes don't say which side. If the side is
  worth naming, use the direction the watch actually swipes.
- Someone who has not used Rekkert, with an iPhone and no watch, reaches the Apple Health
  section on the first try from these notes alone (SC-006).

## The attached image

Two iPhone screenshots side by side, each with a caption, from a debug build on a simulator
with no watch paired, light appearance and a 9:41 status bar:

- **Settings › Apple Health** (P-01), taken with `-rekkert-demo-settings-apple-health`. That
  debug-only flag opens Settings scrolled to the section, which sits below the fold on an
  iPhone and which `simctl` cannot scroll to.
- **The explanation before the permission request** (P-10), taken with
  `-rekkert-demo-health-explainer`.

The file is gitignored, as the README says for every App Review attachment, so it is made
again from these two flags whenever the screens change.
