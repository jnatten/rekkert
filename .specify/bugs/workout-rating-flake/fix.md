# Bug Fix: The rating test reads a late send as what the reconnect said

- **Slug**: workout-rating-flake
- **Fixed**: 2026-11-04
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Both reconnect tests in `WorkoutSyncTests` now take their "before the reconnect" count only once
everything sent before the hello has landed. Before, a send still on its way could pass for what
the reconnect said. The product code is unchanged.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift` | modified test | `aRatingIsNotRepeatedOnReconnect` waits for all six signals instead of three |
| `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift` | modified test | `aReconnectIsToldTheLastThingSaidRatherThanTheFirst` waits for all three signals instead of only `held` |

## Diff Highlights (optional)

```swift
store.send(.skipped(workoutID: record.id))
// Each goes live on a task of its own, the rating is queued by the store and again by the
// fan-out when nobody answers, and the store says `.idle` once more on coming up to find
// its pair in reach. Any of the six still on its way passes for what the reconnect says.
await eventually { paired.workouts.count >= 6 }
```

```swift
store.send(held)
// Both live, and `held` once more as the store comes up to find its pair in reach.
await eventually { paired.workouts.count >= 3 }
```

## Tests Added or Updated

- `WorkoutSyncTests.swift::aRatingIsNotRepeatedOnReconnect`: the first signal after the hello is
  the reconnect's own, so `last == .idle` checks what the reconnect said, not a late send.
- `WorkoutSyncTests.swift::aReconnectIsToldTheLastThingSaidRatherThanTheFirst`: the same for
  `last == held`; a late `.running` can no longer pass for the reconnect's answer.

## Local Verification

- Forced, with a temporary copy that holds the live `.skipped` back and releases it after the
  count (since removed): with the original `>= 3` it failed 8 of 8 runs with `last →
  .skipped(…)`; with the count taken at all six, it passed 8 of 8.
- Both updated tests pass in about 15 ms, three times in a row, without load. A wrong count would
  sit out the 5 s deadline of `eventually`.
- The temporary logging and the held-skip recorder were removed. The test file's diff is the two
  waits and their comments.
- The repeated runs under load and `scripts/verify.sh` are recorded in `test.md`.

## Deviations from Assessment

None to the remediation. The sibling `aReconnectIsToldTheLastThingSaidRatherThanTheFirst` was
already in the assessment's scope. The assessment's reproduction numbers were written before the
last loaded baseline runs had finished. They were then corrected to the final count (8 runs, one
failure), with no change to the cause or the fix.

## Follow-ups

- The durable channel can carry the same rating twice: the store queues it, and the fan-out
  queues it again when the live send goes unanswered. That is harmless, since applying the rating
  again changes nothing, but it is redundant. It is worth a look if the durable queue's volume
  ever matters.
