# Bug Fix: Taps made during a cut sometimes reach the watch before the reconnect

- **Slug**: disconnected-taps-flake
- **Fixed**: 2026-11-04
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`tapsMadeWhileDisconnectedArriveOnReconnect` now cuts the durable queue as well as live traffic.
Before, only live traffic was cut, and `MatchStore` hands whatever could not go live to the durable
queue, which `LoopbackTransport` delivers through a dropped link. The test also runs with a 50 ms
retry, so the store offers the taps to that queue during every cut, not just in an unlucky run.
The product code is unchanged.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift` | modified | `Pair.init(retryInterval:)` defaults to the store's 4 s; the other tests in the file still use `Pair()` |
| `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift` | modified test | `tapsMadeWhileDisconnectedArriveOnReconnect`: 50 ms retry, and the queue held on both ends from the cut to the end |

## Diff Highlights (optional)

```swift
@Test func tapsMadeWhileDisconnectedArriveOnReconnect() async throws {
    let pair = Pair(retryInterval: .milliseconds(50))
    …
    pair.phoneLink.setDroppingOutgoing(true)
    pair.watchLink.setDroppingOutgoing(true)
    // What cannot go live goes on the durable queue instead, and a dropped link still lets
    // that through. Held, the reconnect is the only way across.
    pair.phoneLink.setHoldingQueue(true)
    pair.watchLink.setHoldingQueue(true)
    await waitOutAnswers(pair.phoneLink, pair.watchLink)
```

## Tests Added or Updated

- `SyncTests.swift::tapsMadeWhileDisconnectedArriveOnReconnect`: checks that the watch hears none
  of the three taps while every channel is cut, even though the store offers them to the durable
  queue during the cut. It then checks that the reconnect alone brings the watch to 3–0, with the
  queue still held.

## Local Verification

- Red, with the 50 ms retry and no hold: `swift test --filter tapsMadeWhileDisconnectedArriveOnReconnect`
  failed 5 of 5 runs at the "watch is still in the dark" check, with the watch at 3–0. Temporary
  instrumentation showed `queuePending from retryUndelivered() fresh=3` inside the quiet period
  each time.
- Green, with the hold: passed 5 of 5 runs. The retry still queued the three taps each time, the
  watch stayed at 0–0, and the reconnect brought it to 3–0.
- Whole `RekkertSyncTests` target with the final code: `swift test --skip-build --package-path
  Packages/RekkertKit --filter "SyncTests\."` passed 495 tests, run while another loaded run was
  using the CPU.
- The temporary instrumentation in `MatchStore.queuePending()` and in the test was removed;
  `MatchStore.swift` has no diff.
- The repeated runs under load and `scripts/verify.sh` are recorded in `test.md`.

## Deviations from Assessment

None.

## Follow-ups

- `WorkoutSyncTests.aRatingIsNotRepeatedOnReconnect` (`WorkoutSyncTests.swift:298`) failed once in
  the six loaded baseline runs. It counts sends that arrive in no fixed order, which is a different
  flake from this one.
- `aCatchUpOfSeveralPointsIsNotAnnouncedAtAll` cuts in the same way without holding the queue. It
  is safe as written, since a queued batch is a catch-up and is never announced. If it ever checks
  more than `announced.isEmpty` before the reconnect, it will need the same hold.
