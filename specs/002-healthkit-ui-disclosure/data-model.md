# Data Model: Name Apple Health Wherever Rekkert Uses It

**Feature**: `002-healthkit-ui-disclosure` | **Date**: 2026-10-27

Nothing here is stored or sent. These are values in `RekkertCore/Health/`, free of HealthKit,
that the phone, the watch, the help and the tests all read. The apps map them to HealthKit
types and render them.

## HealthData

One kind of Apple Health data Rekkert touches.

| Case | Shown as | Why Rekkert uses it |
|---|---|---|
| `workout` | Workouts | The session you played, saved as indoor tennis |
| `activeEnergy` | Active energy | What the session burned, saved with the workout and shown on it |
| `restingEnergy` | Resting energy | Added to active energy for the total, as the Workout app does |
| `effort` | Effort | How hard you rated it, on the 1–10 scale |
| `heartRate` | Heart rate | Shown on your wrist while you play, and on the match afterwards |
| `restingHeartRate` | Resting heart rate | To place your heart rate in zones |
| `dateOfBirth` | Date of birth | Your age, to estimate the top of your zones |

**Rules**:

- Every case has a non-empty title and reason (tested).
- The apps map each case to exactly one HealthKit type in an exhaustive `switch`. There is no
  `default`, so a new case cannot compile without its mapping.

## HealthDisclosure

The single statement of what Rekkert does with Apple Health (spec: Key Entity "Apple Health
disclosure").

| Field | Type | Value |
|---|---|---|
| `saved(on:)` | `(Device) -> [HealthData]` | phone: `[workout]`; watch: `[workout, activeEnergy, restingEnergy, effort]` |
| `read(on:)` | `(Device) -> [HealthData]` | phone: `[]`; watch: `[heartRate, activeEnergy, restingEnergy, restingHeartRate, dateOfBirth, workout, effort]` |
| `summary` | `String` | Two sentences for the Settings section and the explainers |
| `when` | `String` | Only while a workout you started is running, and once when it ends |
| `whereItGoes` | `String` | Stays on your iPhone and Apple Watch; never sent to other phones or anywhere else |
| `changeAccess` | `[String]` | The system paths, in order (D-12) |

`Device` is `.phone` or `.watch`.

**Rules**:

- `saved` and `read` are pinned exactly by `HealthDisclosureTests`. These are the lists at
  `rtxlwlsn`, before this feature (FR-019, SC-005).
- The union of both devices' `saved` and `read` is what the Apple Health page lists, so the
  page names everything either app asks for, and nothing else (FR-003, FR-022).
- No string says "HealthKit", and every mention of the service is "Apple Health" or "the
  Apple Health app" (tested with the wording scan, D-6).

## HealthReach

Whether this device can record a workout, and if not, why (spec FR-004).

**Inputs**: `healthAvailable: Bool`, `canPairWatch: Bool`, `isPaired: Bool`,
`watchAppInstalled: Bool`.

| Result | When | Settings line |
|---|---|---|
| `.unavailable` | `!healthAvailable` | Apple Health isn't available on this device, so Rekkert never uses it here. |
| `.cannotPair` | `healthAvailable && !canPairWatch` | Workouts are recorded by an Apple Watch paired with an iPhone. Rekkert doesn't use Apple Health on iPad. |
| `.noWatch` | `canPairWatch && !isPaired` | Recording a workout needs an Apple Watch paired with this iPhone. |
| `.watchAppMissing` | `isPaired && !watchAppInstalled` | Install Rekkert on your Apple Watch to record workouts. |
| `.canRecord` | all true | *(no line; the workout controls are shown)* |

The rows are evaluated top to bottom, and the first match wins.

**Rules**:

- The phone's existing `isAvailable` equals `reach == .canRecord` (tested against the old
  expression's truth table).
- On the watch, reach is always `.canRecord` when Apple Health is available, else
  `.unavailable`.

## HealthAsk

Whether to explain before asking Apple Health for access (spec FR-015 to FR-017).

**Status** (mapped from Apple Health's request status):

- `wouldAsk`: a request now would show the system sheet.
- `alreadyAsked`: it would not.
- `unknown`: Apple Health could not say.

**Rule**: `explainFirst(status) = status != .alreadyAsked`

**The explainer's flow on a device:**

```text
press (or automatic start, or app open with a start set)
        │
        ▼
 query status for this device's saved + read sets
        │
 explainFirst? ──no──► system request (if any) ──► carry on as today
        │yes
        ▼
   explainer  ──Not now──► nothing changes; a Settings picker goes back to Do nothing
        │Continue
        ▼
 system request ──► carry on as today
```

**Rules**:

- The explainer offers exactly two choices, with no per-item switches (FR-015).
- After the system sheet has been shown once, the status is `alreadyAsked` and the explainer
  does not return on that device (FR-017).

## Identification point

A place in the app where Apple Health is named (spec: Key Entity). The full list, with the
words used and the device each needs, is the contract in
[contracts/identification-points.md](contracts/identification-points.md). The review notes
and the recording are built from it.
