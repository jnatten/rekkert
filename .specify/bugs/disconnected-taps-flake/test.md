# Bug Verification: Taps made during a cut sometimes reach the watch before the reconnect

- **Slug**: disconnected-taps-flake
- **Tested**: 2026-11-04
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The race no longer reaches the test. The single test passed 50 of 50 runs under full CPU load.
Across six loaded runs of the whole `RekkertSyncTests` target it passed every time; before the
fix, one of six such runs failed on it. The forced version still queues the taps during every cut
and still keeps them from the watch. `scripts/verify.sh` passes. The only failure seen anywhere
was the unrelated `WorkoutSyncTests` flake, which also failed once in the baseline.

## Checks Performed

All load runs used one `yes > /dev/null` per core (14 on this machine) and `swift test --skip-build
--package-path Packages/RekkertKit` against the final code, with no instrumentation.

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction, before the fix (baseline) | 6 runs of `--filter RekkertSyncTests` under load, original test plus logging | 1 fail of 6 | Run 2: watch at 3–0 at the check; `queuePending from sendPending() fresh=4`, 1.8 ms after the taps. Run 3 failed on `WorkoutSyncTests:298` instead |
| Reproduction, after the fix | 6 runs of `--filter RekkertSyncTests` under load | pass, 6 of 6 for this test | 5 of 6 runs fully green. Run 4 failed on `WorkoutSyncTests.swift:298` only |
| Updated test, repeated | 50 runs of `--filter tapsMadeWhileDisconnectedArriveOnReconnect` under load | pass, 50 of 50 | — |
| Forced race, red then green | 50 ms retry, without and then with the hold, 5 runs each | fail 5 of 5, then pass 5 of 5 | The retry queued the three taps inside the quiet period in every run, both ways |
| Regression gate | `scripts/verify.sh` | pass | 495 + 788 package tests, `tuist generate`, both app builds, every plist and entitlement check |
| Lint / type-check | — | skipped | The repo has no separate lint step; the compiler is part of the build above |

## Output Excerpts

```
load=14 runs=50 pass=50 fail=0
```

```
run-1.log … run-6.log: tapsMadeWhileDisconnectedArriveOnReconnect() passed (6 of 6)
run-4.log: Test aRatingIsNotRepeatedOnReconnect() recorded an issue at WorkoutSyncTests.swift:298:9:
           Expectation failed: paired.workouts.last == .idle  (last → .skipped)
```

```
==> Package tests (macOS, no simulator)
Test run with 495 tests in 74 suites passed after 58.262 seconds.
Test run with 788 tests in 69 suites passed after 0.248 seconds.
…
==> All checks passed
```

## Residual Risks

- The original failure was seen once in five `verify.sh` runs on a developer machine. Six loaded
  runs before the fix and six after cannot show that the failure rate is now zero. The argument
  for that is structural: with live traffic dropped, the queue held and earlier questions waited
  out, nothing is left that can reach the watch before the reconnect. The forced runs show the
  durable queue is the leak, and that the hold closes it.
- With the queue held to the end, the test no longer covers the durable queue on reconnect.
  `DurableQueueTests` and `ResilienceTests` still do.
- `WorkoutSyncTests.aRatingIsNotRepeatedOnReconnect` is still flaky under load: once in six runs
  before the fix and once in six after. It is not touched by this fix.

## Recommendation

Close the bug: verified under load and through `verify.sh`. Handle the `WorkoutSyncTests` flake
separately.
