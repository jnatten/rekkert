# Contract: What Each Watch Asks Apple Health For, and What Rekkert Says About It

This covers FR-008 and FR-009, and User Story 4. The model behind it is in
[data-model.md](../data-model.md).

## Permission request on the watch

The watch builds its request from `HealthDisclosure` with
`effortInAppleHealth: #available(watchOS 11, *)`.

| Watch | Asks to save | Asks to read |
|---|---|---|
| watchOS 11 and later (unchanged) | workouts, active energy, resting energy, effort | heart rate, active energy, resting energy, resting heart rate, date of birth, workouts, effort |
| watchOS 10 | workouts, active energy, resting energy | heart rate, active energy, resting energy, resting heart rate, date of birth, workouts |

- On watchOS 10 the effort type is never named in a request, a status query or a sample
  query.
- On watchOS 10 the `.ratings` path (explanation plus request for waiting ratings) is never
  entered, because nothing is ever waiting.
- The explanation shown before the first request (`WatchHealthExplainer`) does not mention
  effort today and stays unchanged.

The phone's request is unchanged: save workouts, read nothing.

## Effort rating behaviour

| Watch | Rated on the watch | Rated on the phone |
|---|---|---|
| watchOS 11 and later | Rekkert's history and Apple Health (unchanged) | Rekkert's history and Apple Health, written by the watch (unchanged) |
| watchOS 10 | Rekkert's history only | Rekkert's history only. The watch receives `.rated` and writes nothing. |

On watchOS 10, asking for a rating at the end of a workout works exactly as on a current
watch, on both devices.

## Wording on the phone's Apple Health page

The page is unchanged in structure. One reason string changes, and it appears under both
"Saved to Apple Health" and "Read from Apple Health":

```text
Effort
How hard you rated it, on the 1–10 scale. From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health.
```

The summary, "When", "Where it goes" and "Change access" are unchanged.

## Privacy page (`docs/privacy/index.html`)

The workouts paragraph currently says the watch saves the workout "with the active and
resting energy it burned and, if you give one, how hard you rated it". It changes to:

```text
… with the active and resting energy it burned and, if you give one on a watch with watchOS 11 or later, how hard you rated it. On a watch with watchOS 10 the rating stays in Rekkert, with the rest of the workout's summary.
```

The dateline's "Last updated" moves to the date of the change.

## App Review notes (`fastlane/metadata/review_information/notes.txt`)

The notes must stay under 4000 characters. They are 3935 today, and the change adds about 26.

```text
Before: The Apple Watch saves each one to Apple Health as indoor tennis, with its energy and an optional effort rating.
After:  The Apple Watch saves each one to Apple Health as indoor tennis, with its energy and, on watchOS 11 or later, an optional effort rating.
```

## Tests that pin this

- `HealthDisclosureTests`:
  - the watch lists with `effortInAppleHealth: false` (as in the data model);
  - the default watch lists, unchanged;
  - the phone lists, unchanged for either value;
  - the new `.effort` reason, word for word.
- `HealthWordingTests`, unchanged: the new string must pass it.
- `verify.sh`, unchanged: the Info.plist usage strings still name Apple Health.
