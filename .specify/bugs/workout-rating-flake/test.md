# Bug Verification: The rating test reads a late send as what the reconnect said

- **Slug**: workout-rating-flake
- **Tested**: 2026-11-04
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The failure no longer reproduces. Both reconnect tests passed 50 of 50 runs together under full
CPU load, and all eight loaded runs of the whole `RekkertSyncTests` target passed with no issues;
before the fix, one of eight failed on this test. The forced late `.skipped` fails the old count
and passes the new one. `scripts/verify.sh` passes.

## Checks Performed

All load runs used one `yes > /dev/null` per core (14 on this machine) and `swift test --skip-build
--package-path Packages/RekkertKit` against the final code, with no logging.

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction, before the fix (baseline) | 8 runs of `--filter RekkertSyncTests` under load, original test plus logging | 1 fail of 8 | Run 8: count taken at 4, `last → .rated(…)` at `:300`. The other 7 took the count at 5 and passed because the late signal was an `.idle` |
| Reproduction, after the fix | 8 runs of `--filter RekkertSyncTests` under load | pass, 8 of 8 | No issue in any test of the target, and both reconnect tests passed in every run |
| Updated tests, repeated | 50 runs of `--filter "aRatingIsNotRepeatedOnReconnect\|aReconnectIsToldTheLastThingSaidRatherThanTheFirst"` under load | pass, 50 of 50 | — |
| Forced late `.skipped` | Temporary copy with the live `.skipped` held back, count by the old rule, then by the new one; 8 runs each | fail 8 of 8, then pass 8 of 8 | The old rule fails with `last → .skipped(…)`, the CI failure exactly |
| Regression gate | `scripts/verify.sh` | pass | 495 + 788 package tests, `tuist generate`, both app builds, every plist and entitlement check |
| Lint / type-check | — | skipped | The repo has no separate lint step; the compiler is part of the build above |

## Output Excerpts

```
load=14 runs=50 pass=50 fail=0
```

```
run 1 … run 8 rc=0   (whole RekkertSyncTests target under load, after the fix)
```

```
Before the fix, run 8:
RATING-DEBUG boundary=4 ["rated", "idle", "rated", "skipped"]
RATING-DEBUG after=5    ["rated", "idle", "rated", "skipped", "rated"]
Expectation failed: paired.workouts.last == .idle  (last → .rated(…))
```

```
==> Package tests (macOS, no simulator)
Test run with 495 tests in 74 suites passed after 53.483 seconds.
Test run with 788 tests in 69 suites passed after 0.196 seconds.
…
==> All checks passed
```

## Residual Risks

- The counts of six and three depend on the store's start-up share and on the fan-out queuing an
  unanswered rating. If either changes, `eventually` waits out its 5 s deadline and the tests
  still pass, but slowly. The comments name what the count is made of.
- The sibling `aReconnectIsToldTheLastThingSaidRatherThanTheFirst` was never seen to fail. Its
  fix rests on the same mechanism, demonstrated on the rating test, and on its passing in every
  loaded run.

## Recommendation

Close the bug: verified under load and through `verify.sh`.
