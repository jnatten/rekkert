# Bug Fix: The watch's board changes without animating

- **Slug**: shared-guest-half-board
- **Fixed**: 2026-11-23
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The watch's board no longer animates a change: the number, the names and the serve mark are swapped in one frame, and the board turns over at once. A lowered wrist that stops the app drawing can then only leave a finished frame on the display. On the phone the roll stays, but only on the number, so a round change no longer fades one round's names through the next's.

The assessment's hypothesis has still not been seen on a watch. This closes the path it describes; it does not prove that path is what he saw.

## Since the Fix (2026-11-24)

The reporter saw it **with the wrist raised**, and leaving the app and opening it again did not help. That rules out the reason this fix was written for: a frame left on a lowered wrist.

The assessment was revised. Its two findings that still stand:

- What he saw looks like the board part way through an animation, and nothing else in the code or the data draws that.
- On simulators, on watchOS 26.0 and 27.2, the board always finishes its animation while the app runs: after play stops, after the app has been in the background, after changes on a page that was off screen, and after taps, holds, colour swaps and page swipes.

So this change is no longer a fix for a known cause. It is kept as the one step that would cure it if his watch stopped running animations that evening, and as the test of that: an evening on a build with this change, with the fault seen again, rules the animation out altogether.

The change was not looked at on watchOS 27.2. The trials there all ran the board as it was before, to try to reproduce the fault.

## The Record Says What Each Device Was Running (2026-11-24)

Asked for after the reassessment, so the next report can say what the watch was doing. The sharing record gets one new line, written by the phone and by the watch alike. On a watch like his it would read:

```
2026-11-23 17:56:52.658  watch  radio       device(1.2 (82) 181886a · watchOS 27.2.1 · Watch7,5 · lowPower off · reduceMotion off)
```

It is the build, the system and the model, and whether Low Power Mode and Reduce Motion are on. A device writes it at launch, once in each day's file, and whenever any of it changes. The export's header gains `Its watch: App … · watchOS … · Watch7,5` from the watch's last one.

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertCore/Sync/LinkRecord.swift` | modified | `DeviceNote`, `LinkEvent.device`, its text and parse, and the header's watch line. |
| `Packages/RekkertKit/Sources/RekkertSync/LinkRecorder.swift` | modified | `offer(device:)`: noted when it differs from the last one noted, or the day does. |
| `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift` | modified | `deviceNote`, offered on the same tick as the battery. |
| `Shared/AppModel.swift` | modified | Reads the note on each platform, and offers it at launch. |
| `Shared/CommitLabel.swift`, `App/Sources/Views/SharingRecordView.swift` | modified | The build string moved to one place, since the header and the note both write it. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/DeviceNoteTests.swift` | added | Six tests, below. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/LinkRecordTests.swift` | modified | One test, below. |
| `specs/005-steady-sharing-nine-guests/contracts/sharing-record.md`, `README.md` | modified | The row, and a sentence on it. |

Tests:

- `DeviceNoteTests`: noted once however often it is offered; again when it changes; once in each day's file; again after a launch; nothing when there is nothing to say; and a line of a kind a build does not know is passed over, which is what a phone on an older build does with its newer watch's day.
- `LinkRecordTests.whatADeviceWasRunningComesBackAsWritten`: the line as exported, the header's watch line, an export read back into the same entries, and a malformed line refused.

Verified:

- The record suites: 45 tests in 6 suites passed.
- `scripts/verify.sh`, run again with everything above: exit 0, "All checks passed". 625, 996 and 21 package tests passed, and both apps built. The long court suites recorded 44 known issues this time against 30 the day before; they are timing expectations those suites already mark as known, and nothing here runs in them.
- On simulators made for it and deleted after: the watch app (Apple Watch Ultra 2, watchOS 27.2) wrote `1.2 (55) f83bae7 · watchOS 27.2 · Watch7,5 · lowPower off · reduceMotion off` at launch, and a second line with `reduceMotion on` within seconds of the setting being switched. The iPhone app (iPhone 17 Pro, iOS 27.0) wrote `1.2 (55) f83bae7 · iOS 27.0 · iPhone18,1 · lowPower off · reduceMotion off`.

Not verified: Low Power Mode, which a simulator cannot switch on, and the header's watch line on a real pair.

A phone on a build before this one drops the watch's new line when it reads the watch's day, and keeps everything else.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Shared/ScoreButton.swift` | modified | The number's `.contentTransition` is `.identity` on the compact board and `.numericText()` elsewhere. `.animation(.snappy, value: value)` moved from the whole half onto the number, and is `nil` on the compact board. |
| `Shared/ScoreboardView.swift` | modified | The turn-over animation is `nil` on the compact board. |
| `Shared/AppModel.swift` | modified | `-rekkert-demo-live <ms>`: the tournament plays itself, a point every so many milliseconds and the next round drawn once one is played out. Debug builds only. |
| `scripts/board-at-rest.sh` | added | Runs the watch app on a simulator with that switch, stops its process at arbitrary moments, and a second later asserts every half has its number. |
| `scripts/board-at-rest.swift` | added | The check on each screenshot: enough solid white in each half of the board. |
| `scripts/verify.sh` | modified | A static guard: every `.animation(`, `.contentTransition(` or `.transition(` in the board's two views must name `compact`. |
| `README.md` | modified | "Verifying" says why the watch's board does not animate and how the two checks cover it. |

## Diff Highlights (optional)

```swift
// Shared/ScoreButton.swift
Text(value)
    …
    .contentTransition(compact ? .identity : .numericText())
    .animation(compact ? nil : .snappy, value: value)
```

```swift
// Shared/ScoreboardView.swift
.animation(compact ? nil : .snappy, value: layout.isMirrored)
```

## Tests Added or Updated

- `scripts/board-at-rest.sh`: an Americano plays itself on the watch simulator, the app is stopped 30 times, and each time both halves must have a solid number. A round change caught mid-fade blurs both numbers too, so it fails the same check.
- `scripts/verify.sh`, "Assert nothing on the watch's board animates": fails if an animation comes back to the board's two views without its `compact`.

No package test was added. Nothing in `RekkertKit` changed, and no unit test sees what SwiftUI draws.

## Local Verification

- `scripts/board-at-rest.sh` against the old board code (a scratch copy with only the new switch and script): **6 of 30 at rest, FAIL**. The other 24 had a half without its number.
- `scripts/board-at-rest.sh` against this change: **30 of 30 at rest**. The frames show the game moving on, from round 3 to round 7, each with crisp numbers and one set of names.
- `scripts/verify.sh`: exit 0, "All checks passed". The package tests passed (619, 995 and 21 tests; the 30 known issues in the long court suites were there before). Both apps built. The new guard said ok.
- The phone, by hand: the fixed iPhone app on a simulator with a court's scoreboard open and the game playing itself, stopped at arbitrary moments. In one frame the big number still showed 2 while the entry row below already said 3, so the roll is still running there. Names were crisp in every frame.
- Both checks ran on simulators made for them and deleted afterwards (Apple Watch Ultra 49 mm on watchOS 26.0, iPhone 17 Pro on iOS 27.0).

Not verified:

- **Any real watch.** The simulator cannot lower a wrist, so nothing here shows the Always On display behaving as the assessment supposes.
- A round change on the phone's board. The court sheet used for the phone check stays on its own round.

## Deviations from Assessment

- **The stop-and-look check is its own script, not a step in `verify.sh`.** `verify.sh` runs on every push and boots no simulator. A step that boots one, stops a process and reads screenshots would add a minute and a new way to flake to every run. `verify.sh` got the static guard instead, which the assessment did not list.
- **Two new files and the README** were not in "Files likely to change": `scripts/board-at-rest.sh`, `scripts/board-at-rest.swift` and `README.md`.
- **The check reads the numbers only.** The assessment also asked for "two sets of names" to fail it. Names are drawn slightly see-through even at rest, so they cannot be told from a fade by colour alone. A round change resets both numbers, so the same frame fails on those.
- **The assessment's open questions are still open.** The fix went ahead on the hypothesis as it stood: whether Always On was on, whether a workout was running, and whether raising the wrist put it right are not known.

## Follow-ups

- Have the reporter play an evening on a build with this change. Seen again, the animation is not the cause and the bug is open with nothing to go on.
- Ask him for a screenshot when it happens (side button and crown together), and the revised assessment's questions.
- The iPhone app waits for the system's speech voices before it draws anything (`ScoreAnnouncer.init` calls `refreshVoices()` from `AppModel.init`). On a simulator that had never been booted, that held the launch screen for about fifty seconds. Not this bug, and not seen on a phone.
- The three things found on the way are untouched: older builds drawing other teams than build 82 when an undo, cancel or redraw crosses a draw; the record's stale first battery reading; and the host's watch losing its phone 430 times.
- `FullscreenScoreView`, `BoardCourtsView` and `BoardMatchView` keep their number roll, as the assessment left them.
