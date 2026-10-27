# Contract: Where Apple Health Is Named

Every place the app names Apple Health, how to reach it, whether it needs an Apple Watch, and
the words. The review notes and the recording are built from this list. A screen that starts
a workout, asks to start one, asks for access, or shows data from Apple Health and is not
listed here is a defect (SC-003).

Two conventions apply throughout:

- **Mark**: `AppleHealthMark`, Apple's icon beside the words "Apple Health". It is never
  inside a button, link or menu item (research D-3).
- **Copy**: the words are final unless marked *draft*. *Draft* copy waits on a device check
  (quickstart R-3).

## iPhone and iPad

| ID | Where | Reach | Watch needed | Element | Words |
|---|---|---|---|---|---|
| P-01 | Settings › Apple Health section | Home › gear | No | Header: mark | — |
| | | | | Body | `HealthDisclosure.summary`: "Rekkert can save the workouts your Apple Watch records to Apple Health, and reads your heart rate and energy while one is running. Nothing it reads leaves your iPhone and Apple Watch." |
| | | | | Reach line | `HealthReach` line for this device (see data-model) |
| | | | | Row | "What Rekkert saves and reads" › P-02 |
| P-02 | Apple Health page | P-01 › row | No | Top: mark, large | Title "Apple Health" |
| | | | | Section "Saved to Apple Health" | One line per `HealthDisclosure.saved` kind (both devices), title and reason |
| | | | | Section "Read from Apple Health" | One line per `HealthDisclosure.read` kind, title and reason |
| | | | | Section "When" | `HealthDisclosure.when` |
| | | | | Section "Where it goes" | `HealthDisclosure.whereItGoes` |
| | | | | Section "Change access" | *Draft*: "Settings › Privacy & Security › Health › Rekkert", then "Or in the Apple Health app: your picture › Apps › Rekkert" |
| P-03 | Home › Workout section | Home | Yes | Header: "Workout", mark trailing | — |
| | | | | Footer | "Records your heart rate and energy on your Apple Watch and saves it to Apple Health as tennis, the nearest thing Apple Health has to padel. It runs on its own: start it when you walk on, stop it when you walk off, and play as many matches in between as you like. Settings can have it start and stop with the match instead." |
| P-04 | A match's menu › Start workout | Match › ⋯ | Yes | Item subtitle | "Saves to Apple Health" |
| P-05 | "Start a workout?" | Match start with Ask me | Yes | Alert message | "It runs on your watch while you play, and is saved to Apple Health." |
| P-06 | Settings › Workout on your watch | Home › gear | Yes | Footer, appended | "The workouts it starts are saved to Apple Health; see Apple Health below." |
| P-07 | Workouts list | Home › Workouts | Yes, and one workout | Footer | "Deleting one here removes Rekkert's copy. The workout itself stays in Apple Health." |
| | | | | Empty state | "Start one from your Apple Watch and it shows up here and in Apple Health." |
| P-08 | A workout's page | P-07 › a workout | Yes | Row after "Saved as" | "Saved in" · "Apple Health" |
| | | | | Effort footnote | "Worked out by Apple Health from the zones you were on. Changing them later leaves this as it was on the day." |
| P-09 | A filed match's timeline | History › a match | Yes | Heart-rate chart caption | "Heart rate from Apple Health" |
| | | | | Footer hint | "Start a workout on your watch before you play, and its heart rate from Apple Health goes here too." |
| P-10 | Explainer sheet | First Start workout, or a Settings start picker | Yes | Top: mark | Title "Rekkert works with Apple Health" |
| | | | | Body | "Your Apple Watch records the workout and saves it to Apple Health as tennis. While it runs, Rekkert reads your heart rate and energy to show them with the score. Nothing it reads leaves your iPhone and Apple Watch." |
| | | | | Note | "Apple Health asks next what Rekkert may save and read. You can change it later in Settings." |
| | | | | Buttons | "Continue" · "Not now" |
| P-11 | System permission sheet | After P-10 | Yes | `NSHealthUpdateUsageDescription` | "Rekkert saves the workout your Apple Watch records to Apple Health, as tennis." |
| | | | | `NSHealthShareUsageDescription` | "Rekkert shows the heart rate and energy your Apple Watch saved to Apple Health while you played." |
| P-12 | Help › Settings | Home › ? › Settings | No | Item "Apple Health" | "What Rekkert saves to and reads from Apple Health, and where to change it." |
| | Help › Home | Home › ? › Home | Yes | Item "Start a workout" | "Starts, holds or stops the workout on your watch. It goes to Apple Health." |
| P-13 | Start failed for access | Start workout with access off | Yes | Home Workout footer, in place of P-03's while it shows | "Turn on Apple Health access for Rekkert in Settings." |

## Apple Watch

| ID | Where | Reach | Element | Words |
|---|---|---|---|---|
| W-01 | Start workout, on the menu page, the idle screen and the result screen | Watch app | Caption under the button, while not running and with no failure text | "Saves to Apple Health" |
| W-02 | "Start a workout?" | Match start with Ask me | Alert message | "It's saved to Apple Health." |
| W-03 | Workout page | A page beside the score, while a workout runs | Caption at the foot | "Saving to Apple Health" |
| W-04 | Start failed for access | Start workout with access off | Failure text | *Draft*: "Turn on Apple Health access for Rekkert in Settings on your iPhone." |
| W-05 | Explainer | First Start workout, automatic start, or app open with a start set | Mark, title | "Rekkert works with Apple Health" |
| | | | Body | "Workouts you start are saved to Apple Health. While one runs, Rekkert reads your heart rate and energy. Nothing leaves your watch and iPhone." |
| | | | Buttons | "Continue" · "Not now" |
| W-06 | System permission sheet | After W-05 | `NSHealthUpdateUsageDescription` | "Rekkert saves what you played to Apple Health as a tennis workout, with its energy and your effort rating." |
| | | | `NSHealthShareUsageDescription` | "Rekkert reads your heart rate and energy from Apple Health while a workout you started is running and once when it ends, and your age and resting heart rate to place that heart rate in zones." |
| W-07 | Help › Workout | Phone help, watch chapter | Items | "Start workout": "Records a tennis workout in Apple Health while you play." · "Stop workout": "Ends the workout and saves it to Apple Health." |

## Words that must not appear

The wording scan rejects these in user-facing string literals in `App/Sources`,
`WatchApp/Sources`, `Shared` and `RekkertCore/Help` (FR-013):

- "Health" not preceded by "Apple ";
- "HealthKit";
- "the Health app".

Identifiers (`HKHealthStore`, `isHealthDataAvailable`) are not string literals and are not
scanned.

One exception: a system menu quoted as a path to follow keeps the system's own names, as
in the "Change access" lines of P-02 ("Settings › Privacy & Security › Health › Rekkert").
Those lines live in `HealthDisclosure.changeAccess`, outside the scanned folders, and
`HealthDisclosureTests` exempts them from its own "Apple" rule.

## Accessibility

- The mark is one element, labelled "Apple Health". Its image is hidden from VoiceOver on its
  own, so the name is not read twice.
- On the phone, every caption above uses a Dynamic Type text style and wraps at the largest
  size.
- On the watch, W-01 and W-03 keep the fixed 10 pt size of the existing failure text, so
  they do not grow with the text size:
  - **W-01** wraps.
  - **W-03** stays on one line and shrinks to fit, because the workout page must not scroll.
    If it no longer fits on the 40 mm case, T030 stops and asks rather than drop the caption
    or let the page scroll.
- P-13 and W-04, the failure messages, point to Settings but never quote the Health menu.
  That keeps them inside the wording rule above (T019).
