# Bug Verification: Package tests fail intermittently on GitHub CI

- **Slug**: ci-test-flakes
- **Tested**: 2026-10-28
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

Locally the bug no longer reproduces. Under the CPU load that reproduces the CI failures on `main`, the fix passed every full-suite run. `scripts/verify.sh` (what `test.yml` runs) passes, including both app builds, and no regressions were found.

The result is **partial** only because the assessment's first reproduction, a GitHub Actions run on the hosted `xcode-27-arm64` runner, was not exercised: it needs a push, which was not authorized as part of this check.

All checks ran on commit `onuzxlvo` / `7d087c8c` ("fix(sync): steady the tests that kept failing on CI"), with an empty working copy on top.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction on CI (assessment steps 1–2) | push, or dispatch `testflight.yml` | skipped | Pushing triggers outward-facing CI; it needs the user's go-ahead. |
| Reproduction under load, fix (assessment steps 3–4) | `swift test --skip-build --package-path Packages/RekkertKit` with 8 `yes` processes on a 14-core Mac, 3 runs | pass | 3/3 passed (494 tests in 74 suites, 73–84 s). No flaky test failed. |
| Same load, `main` for comparison | the same command on a clean copy of 86ffb74 built in the scratchpad, alternating with the fix runs, 3 runs | reproduces | 1/3 failed `aScorerWarmsUpButDoesNotStartTheGame` (`AccessTests.swift:231`). In the `/speckit-bug-fix` comparison, `main` also failed `aPhoneThatIsBackButNotThroughIsNotHandedTheMatch` (`:495`/`:496`) under the same load. |
| New / updated tests | `swift test --skip-build --package-path Packages/RekkertKit --filter '<the fix's tests and suites>'` ×5 | pass | 5/5 passed: 20 tests in 5 suites, including the deterministic `aThroughSaidBeforeThePhoneWentIsNotTakenForNow` and the four new `AccessTests`. |
| Regression suite and app builds | `scripts/verify.sh` | pass | Package tests 494/494; `tuist generate`; iOS and watchOS simulator builds; every plist, entitlement and privacy check ("All checks passed"). |
| Lint / type-check | — | not-run | The project has no SwiftLint or SwiftFormat config. Compiling with the Swift 6 language mode in both builds is the type check, and it passed. |

## Output Excerpts

```
targeted-1..5: Test run with 20 tests in 5 suites passed after 21.7–26.4 seconds
verify:        Test run with 494 tests in 74 suites passed after 68.341 seconds | ==> All checks passed
fix-load-1:    Test run with 494 tests in 74 suites passed after 75.342 seconds
fix-load-2:    Test run with 494 tests in 74 suites passed after 73.380 seconds
fix-load-3:    Test run with 494 tests in 74 suites passed after 83.836 seconds
main-load-3:   ✘ aScorerWarmsUpButDoesNotStartTheGame (AccessTests.swift:231)
```

The scratchpad copy of `main` also fails three `HelpTests` (`HelpTests.swift:67`, `:74`, `:80`) in every run. They read the repo's README and help pages, which the copy does not include, so this is a side effect of the copy and not a result for either version.

Across this check and the comparison in `/speckit-bug-fix`, under the same load:

- **fix:** 6 of 6 full runs passed.
- **`main`:** 2 of 5 failed on the original flaky tests.

## Residual Risks

- **CI hardware not exercised.** The hosted runner's core count is unknown, and its load is not the same as `yes` processes on a local Mac. The local load reproduces the CI failures on `main`, but only a CI run confirms the fix there.
- **Live-offer path still has a window.** A joining guest that takes the host's match from a live offer, rather than from the answer to its own hello, gets the access list a round trip later, as before (see `fix.md`, Deviations 2). `Court.open` waits for the watch's list, so the test no longer depends on which path wins.
- **The suite still depends on spare CPU.** At full saturation (14 `yes` on 14 cores) many more tests fail on both versions (assessment, Reproduction 3). New timing assumptions can still surface as CI flakes.
- **Not checked on devices.** The new wire fields (`snapshot.access`, `standby.issuedAt`) were checked only by the round-trip tests and in-process links. They were not tried between real phones and watches, or against an older build.

## Recommendation

Hold for one CI run, then close. Push the commit, or let the next push run `test.yml`. If the package-test step passes, preferably on two or three runs given the history of about half failing, mark this bug verified and close it. If any of `aPhoneThatIsBack…`, `aScorerWarmsUp…` or `aWatchStandingIn…` fails on CI again, reopen it and re-run `/speckit-bug-assess` with that run's log. A different test failing would be a new flake for its own assessment.
