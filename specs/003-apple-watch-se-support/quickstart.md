# Quickstart: Validating Rekkert on Apple Watch SE (1st generation)

**Feature**: `003-apple-watch-se-support`

The contracts are [watch-floor.md](contracts/watch-floor.md) and
[apple-health-access.md](contracts/apple-health-access.md), and the model is in
[data-model.md](data-model.md). Steps 1 and 2 need no hardware. Step 3 needs a real watch,
because Xcode 27 has no simulator for the SE (1st generation) or for watchOS 10
([research.md](research.md) R-10).

## Prerequisites

- Xcode 27 and `mise install` (pinned Tuist).
- For hardware: `TUIST_DEVELOPMENT_TEAM` in `mise.local.toml` (README, "Running on a real
  iPhone and Watch").
- An iPhone on iOS 26 or later, paired with an **Apple Watch SE (1st generation) on watchOS
  10.x**. Check it in Settings › General › About on the watch.
- For the convergence and timed-round checks, a second device on the same session. A current
  watch on watchOS 26 or later is best. A second iPhone will do for convergence.
- Date of birth set in Apple Health on the iPhone, so zones can be estimated.

## 1. Automated checks

```bash
swift test --package-path Packages/RekkertKit
```

Expected: everything passes, including `HealthDisclosureTests` for the watchOS 10 lists and the
new effort wording.

```bash
scripts/verify.sh
```

Expected: `==> All checks passed`, including the new step:

```text
==> Assert the watch app still installs on watchOS 10
  ok: "MinimumOSVersion" => "10.0"
```

**SC-008: the gate catches a dropped floor.** Do this on a scratch change and throw it away:

```bash
jj new -m "trial: raise the watch floor"
```

```bash
sed -i '' 's/.watchOS("10.0")/.watchOS("11.0")/' Project.swift
```

```bash
scripts/verify.sh
```

Expected: it fails at the floor step, with the message from
[watch-floor.md](contracts/watch-floor.md) naming the SE (1st generation). Then discard the
trial:

```bash
jj abandon @
```

## 2. No change on current watches (FR-010, SC-007)

Run `RekkertWatch` on a watchOS 26 simulator paired with an iOS 26 simulator and confirm the
following still work as before:

- Scoring a match from the wrist and from the phone.
- Starting and ending a workout. The effort question appears, and a rating given on either
  device appears in Apple Health on the simulator.
- Starting a short timed Winner court round. The watch buzzes and shows time is up when it
  runs out.
- On the phone, Settings › Apple Health lists Effort with the new sentence. Nothing else has
  changed.

## 3. On the SE (1st generation)

Run the `Rekkert` scheme on the iPhone. The watch app installs on the paired watch by itself.
If Xcode 27 refuses to install on or debug a watchOS 10 watch, use an internal TestFlight
build instead (`testflight` workflow) and run the same steps.

| # | Check | Expected | Covers |
|---|---|---|---|
| 1 | Watch app on the watch | Rekkert appears in the iPhone's Watch app under available apps, installs and opens to the start screen. | US1-1, FR-001 |
| 2 | Every screen at the watch's size | Nothing is clipped or overlapping, and every control can be reached. Go through the court page, menu, join, workout page, result, and the effort sheet. | FR-011 |
| 3 | A best-of-three match tapped on the watch | Every point is on the phone within 2 s. None are missing or doubled. The serve dot and badge agree. | US1-2, SC-002 |
| 4 | Taps on the phone, including an undo | The watch follows. | US1-3 |
| 5 | Our court, All courts (timed and match), Friendly, Americano and Mexicano, a few rounds each | The watch shows the same courts, rounds and next-round prompts as the phone. | US1-4, SC-001 |
| 6 | Wrist responsiveness | The score changes within 0.5 s of a tap, both at the start and after 20 tournament rounds. | SC-003 |
| 7 | iPhone out of reach, a second phone sharing the match | The watch keeps scoring over Bluetooth. Every device agrees once back in contact. | US1-5, FR-004 |
| 8 | Points tapped on the SE, a current watch and two phones while one is offline | Every device ends on the same score once all are back in contact. | US1-6, FR-003 |
| 9 | First workout on a fresh install | The explanation, then the Apple Health request, which lists no effort item. The workout starts. | US2-1, US4-3, FR-009 |
| 10 | Workout started from the phone, watch app closed | The workout starts on the watch, and the phone shows it running. | US2-2, FR-005 |
| 11 | Wrist lowered for an hour of play | Heart rate and energy are collected throughout. The live zone shows. | US2-3, FR-006 |
| 12 | End three workouts of 30 minutes or more (one started on the phone) | Each is in Apple Health as tennis with heart rate and energy, and in the phone's Workouts list with its summary. | US2-4, SC-004 |
| 13 | Rate one workout on the watch and one on the phone | Both ratings show in the phone's Workouts list. In the Fitness or Apple Health app, neither workout has an effort rating from Rekkert. | US4-1, SC-009, FR-008 |
| 14 | Settings › Apple Health on the phone | Effort reads "… From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health." | US4-2, FR-009 |
| 15 | Short timed round with the app in front, with a current watch on the same session | Both buzz within 2 s of each other. The SE shows that time is up. | US3-1, SC-005, FR-007 |
| 16 | Same, wrist lowered | The time-up notification arrives on the SE. | US3-2 |
| 17 | Add time after it ran out, let it run out again | The SE buzzes again. | US3-3 |
| 18 | Full charge, then a 2-hour session scored on the wrist with a workout throughout | At least 40% battery is left. | SC-006 |

Record the watchOS version, the watch size and the battery figures with the results.

## 4. Documents

- `README.md` names watchOS 10 as the watch minimum and mentions the SE (1st generation).
- `docs/privacy/index.html` and `fastlane/metadata/review_information/notes.txt` carry the
  qualified effort sentence from [apple-health-access.md](contracts/apple-health-access.md).
  The notes must stay under 4000 characters:

```bash
wc -m fastlane/metadata/review_information/notes.txt
```

- After the next upload, the App Store page's compatibility line for Apple Watch reads
  watchOS 10.0 or later.

## Optional: a watchOS 10 simulator

If Xcode 27 offers a watchOS 10 simulator runtime under Settings › Components, a watchOS 10
simulator can catch layout regressions before the watch is needed. Nothing above depends on
it.
