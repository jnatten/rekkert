# Data Model: Rekkert on Apple Watch SE (1st generation)

**Feature**: `003-apple-watch-se-support` | **Date**: 2026-11-04

No persisted field, wire field or event changes. What changes is one rule in `RekkertCore`,
where the effort rating goes on watchOS 10, and the watch's software floor.

## Apple Health disclosure rule (`RekkertCore`, `HealthDisclosure`)

What a device saves to and reads from Apple Health. Both apps' permission requests and the
phone's Apple Health page are built from it.

**Inputs**

| Input | Type | Meaning |
|---|---|---|
| `device` | `HealthDevice` (`.phone`, `.watch`) | Unchanged. |
| `effortInAppleHealth` | `Bool`, default `true` | New. Whether this device's Apple Health has a place for an effort rating. The watch passes `#available(watchOS 11, *)`. The phone and the Apple Health page use the default. |

**Outputs**

| Device | `effortInAppleHealth` | `saved(on:)` | `read(on:)` |
|---|---|---|---|
| phone | either | `[.workout]` | `[]` |
| watch | `true` (watchOS 11+) | `[.workout, .activeEnergy, .restingEnergy, .effort]` | `[.heartRate, .activeEnergy, .restingEnergy, .restingHeartRate, .dateOfBirth, .workout, .effort]` |
| watch | `false` (watchOS 10) | `[.workout, .activeEnergy, .restingEnergy]` | `[.heartRate, .activeEnergy, .restingEnergy, .restingHeartRate, .dateOfBirth, .workout]` |

**Rules**

- The parameter only ever removes `.effort`. Order and every other kind are unchanged, so
  the existing tests for the default case keep passing as they are.
- The phone's page uses the defaults and lists every kind. "The page lists everything and
  nothing else" still holds.

## Effort kind wording (`HealthData.effort`)

| Field | Before | After |
|---|---|---|
| `title` | "Effort" | unchanged |
| `reason` | "How hard you rated it, on the 1–10 scale" | "How hard you rated it, on the 1–10 scale. From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health." |

The new reason shows in both the "Saved to Apple Health" and "Read from Apple Health" lists on
the phone. It must pass `HealthWordingTests`: "Apple Health" only, never "Health" on its own.

## Apple Health type mapping (`Shared/HealthTypes.swift`)

| Field | Before | After |
|---|---|---|
| `HealthData.objectType` | `HKObjectType` | `HKObjectType?`: `nil` for `.effort` below watchOS 11, otherwise as before |
| `HealthData.sampleType` | `objectType as? HKSampleType` | `objectType as? HKSampleType` (`objectType` is now optional) |
| `HealthDisclosure.toShare(on:)` / `toRead(on:)` | built from `saved`/`read` | also take `effortInAppleHealth`; `compactMap` over the types |

With the disclosure already leaving `.effort` out on watchOS 10, the `nil` branch is never
reached there. It exists so that the type is never named on a system that lacks it.

## Workout effort rating

| Field | Type | Where | Changes |
|---|---|---|---|
| `WorkoutRecord.effort` | `Int?`, within `WorkoutEffort.range` (1–10) | Rekkert's own store, on the phone and the watch | none |
| `WorkoutSignal.rated(workoutID:effort:)` | wire signal | phone ⇄ watch | none |
| Apple Health effort sample | quantity sample related to the workout | the watch's Apple Health | written on watchOS 11 and later only |

**Lifecycle on a watchOS 10 watch**

```text
workout ends ─► asked (watch or phone)
                 ├─ rated on watch ─► .rated published ─► store sets record.effort ─► phone lists it
                 │                    └─ save(): returns at once (no Apple Health write, nothing queued)
                 ├─ rated on phone ─► record.effort set ─► .rated sent to watch
                 │                    └─ heard(.rated) ─► save(): returns at once
                 └─ skipped ─► .skipped (unchanged)
```

On watchOS 11 and later the same flow continues into `enqueue` → `writeWaiting` → `write`,
exactly as today. `writeWaitingRatings()` returns without asking on watchOS 10, so the
`.ratings` explanation and request never appear there.

## Watch software floor

| Where | Value before | Value after |
|---|---|---|
| `Project.swift`, `RekkertWatch.deploymentTargets` | `.watchOS("26.0")` | `.watchOS("10.0")` |
| `Packages/RekkertKit/Package.swift`, `platforms` | `.watchOS(.v26)` | `.watchOS(.v10)` |
| Built `RekkertWatch.app/Info.plist`, `MinimumOSVersion` | `26.0` | `10.0`, asserted by `verify.sh` |
| Constitution, Platform & Technical Constraints | "iOS, watchOS, and macOS 26" | iOS and macOS 26, watchOS 10 (v1.1.0) |

## Round-alarm situation (`RoundAlarmFollower.Situation`)

This is unchanged: `session: UUID` and `state: SessionState?`, read from the store on the main
actor. The follower must see a new `Situation` after every change to either, with any
watchOS. On 26 and later it comes from `Observations`. Below 26 it comes from the tracking
fallback, which emits the current value once at the start and then once after each change.
