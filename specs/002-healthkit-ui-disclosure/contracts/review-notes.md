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
Used only for workouts the user starts. The Apple Watch saves each one to Apple Health as indoor tennis, with its energy and an optional effort rating. While it runs and when it ends, the watch reads heart rate and energy, plus date of birth and resting heart rate for heart-rate zones. Nothing read leaves the user's iPhone and Apple Watch.

NO APPLE WATCH NEEDED (any iPhone or iPad)
Tap the gear on the start screen. The Apple Health section, with the Apple Health icon, says what Rekkert saves and reads, and "What Rekkert saves and reads" lists it in full.

WITH A PAIRED APPLE WATCH
- Start screen: the Workout section carries the Apple Health icon. The first "Start a workout" explains what Apple Health will ask, then it asks.
- In a match: "..." > "Start workout", subtitled "Saves to Apple Health".
- On the watch: "Start workout", captioned "Saves to Apple Health".
- Settings > Workout on your watch, start screen > Workouts, and each workout's page all name Apple Health.

The attached image shows the Apple Health section in Settings on an iPhone with no Apple Watch, and the explanation shown before the permission request.
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
