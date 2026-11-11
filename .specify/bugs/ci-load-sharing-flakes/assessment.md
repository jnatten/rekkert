# Bug Assessment: Test and TestFlight runs fail since the steady-sharing branch loaded the runner with long court simulations

- **Slug**: ci-load-sharing-flakes
- **Created**: 2026-11-11
- **Source**: pasted text, plus the GitHub Actions runs it points at (read with `gh run view --attempt N --log-failed`; host `github.com`, policy branch: `allowlisted`)
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

> Look at the previous commits. They introduced some sort of flake i think. It is very flakey to run tests on github actions now. And testflight.
>
> Look at the runs.

The suspect commits are the five on `005-steady-sharing-nine-guests` after `8f325c5`:

- `96734b1` test(sharing): a second link per guest, a busy hall and a clock per device in the court harness
- `82c1b9a` fix(sharing): a guest's second link dropping no longer slows the whole court
- `caddb4f` feat(sharing): the sharing record says how late points were and which link dropped
- `cec93ae` feat(sharing): a full match says how many it takes, and the record notes battery
- `ba58710` fix(sharing): close the gaps convergence found in the record, refusals and calibration

Both runs are on `ba58710`, and every attempt failed in `swift test --package-path Packages/RekkertKit`. In **Test** run [43027752716](https://github.com/jnatten/rekkert/actions/runs/43027752716), both attempts failed in `scripts/verify.sh`. In **TestFlight** run [43027852466](https://github.com/jnatten/rekkert/actions/runs/43027852466), all four attempts failed in *Test, archive and upload* (`scripts/release.sh:247`), so nothing was uploaded. The last green runs were on `main` (`e6b1159`, `42770464561`) and TestFlight on `main` (`42490282611`).

| Failing expectation | Test run a1 | Test run a2 | TF a1 | TF a2 | TF a3 | TF a4 | Fails |
|---|---|---|---|---|---|---|---|
| `GuestWristTests.swift:102–103` joiningAgainAfterTheHostStoppedSaysSoAndForgets | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ | **6/6** |
| `GuestWristTests.swift:40` joiningOnTheWristWithThePhoneInABag | ✘ | ✘ | | ✘ | ✘ | ✘ | 5/6 |
| `CalibrationFitTests.swift:68` aRecordFromAKnownRadioIsFittedBackWithinAQuarter *(new)* | ✘ | | ✘ | ✘ | ✘ | | 4/6 |
| `RelayedPointTests.swift:163/164` anAnswerIsHandedOnWithoutWaitingForAChildThatNeverAnswers | | ✘ | | | ✘ | | 2/6 |
| `WatchStandInTests.swift:314` aPhoneThroughOnAnotherCodeIsNotTheJoinLanding | | | | ✘ | | | 1/6 |
| `BusyHallTests.swift:64` everyDeviceGetsItsPointsInTime, FR-011's 30 s *(new)* | | | | | ✘ | | 1/6 |

Run length and size, package tests only:

| | Tests / suites | Swift Testing run time |
|---|---|---|
| `main` @ `e6b1159` (green) | 553 / 81 | 271 s |
| branch @ `ba58710` (six attempts) | 602 / 100 | 888–1064 s |

The long suites on the branch, from the attempt logs:

| Suite | `main` | branch |
|---|---|---|
| Points within a second in a busy hall (`BusyHallTests`, new) | — | 888–1064 s |
| A club night (`ClubNightTests`, reworked to the full limit on two radios) | 157 s | 853–1030 s |
| Fitting the simulated radio to a record (`CalibrationFitTests`, new) | — | 353–478 s |
| Delays timed from the tap, whatever the clocks say (`ClockOffsetTests`, new) | — | 355–472 s |
| A forgotten share stops by itself | 271 s | 315–434 s |
| A host on 1.1 (`OlderHostTests`, new) | — | 155–224 s |
| A watch standing in gets its points in time (`StandInDelayTests`, new) | — | 108–149 s |
| The incident | 122 s | 164–240 s |

Every failure in the short tests lands 7–35 s after the run starts, which is when all 100 suites start at once.

## Symptom

On the hosted `xcode-27-arm64` runner, the package tests on the branch fail every time: six attempts out of six, with a different mix each time. `GuestWristTests.swift:102–103` fails in all of them. The same tests pass on a developer machine. The suite was green on `main` before these commits, and both `verify.sh` and `release.sh` should pass.

## Reproduction

Fails in CI on every attempt. Locally it reproduces with synthetic CPU load:

1. `swift build --package-path Packages/RekkertKit --build-tests`
2. With an idle machine: `swift test --package-path Packages/RekkertKit --skip-build --filter 'GuestWristTests|WatchStandInTests|RelayedPointTests'`. This passed 3/3 here (M4 Pro, 14 cores), in about 3 s each.
3. Saturate the CPU: `for i in $(seq 1 26); do (while :; do :; done) & done`. Run the same filter again: it failed 3/3. `GuestWristTests.swift:40` failed in every run. Several `WatchStandInTests` failed too (`:179`, `:184`, `:187`, `:221`, `:242`, `:314`, `:381`, `:399`, `:549`, `:566`, `:573`, `:574`). Kill the loops afterwards.
4. Run the same loaded command against the pre-branch tree (`git archive 8f325c5 Packages/RekkertKit | tar -x -C <tmp>`, build, run). It failed 3/3 with the same tests, and one run also failed `GuestWristTests.swift:102–103` and `RelayedPointTests.swift:163`.

[NEEDS CLARIFICATION: synthetic load does not reproduce `GuestWristTests.swift:102–103` reliably here (1 run in 6 across both trees). The 6/6 rate is specific to the hosted runner with the branch's long suites beside it. The mechanism is below.]

## Suspected Code Paths

- `Packages/RekkertKit/Package.swift` — `RekkertSync` and `RekkertSyncTests` use `.defaultIsolation(MainActor.self)`. Every court-harness test runs on the one main actor. Swift Testing runs suites in parallel, and `.serialized` only orders tests within its own suite.
- `Packages/RekkertKit/Tests/RekkertSyncTests/BusyHallTests.swift`, `ClubNightTests.swift:29 predict(…)`, `ClockOffsetTests.swift`, `CalibrationFitTests.swift`, `Calibration.swift:127 fit(…)`, `OlderHostTests.swift`, `StandInDelayTests.swift`, `LongEveningRecordTests.swift` — new or much heavier court simulations, added in `96734b1`…`ba58710`. Each runs for minutes, with 16–20 devices and two radios each. Together they keep the main actor busy for the whole 15–18 minute run instead of about 2.5 minutes.
- `Packages/RekkertKit/Tests/RekkertSyncTests/CourtHarness.swift:343–383` (`run(for:)`, `until(within:)`, `step(atMost:)`) — radio time moves 50 ms per step. Between steps, the stores get only `4 × Task.yield()` plus a 1 ms sleep to catch up. How much radio time passes per wall-clock second therefore depends on how busy the machine and the main actor are.
- `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift:491,496` — the stand-in's policy runs on `ContinuousClock` and `Task.sleep(for: tick)`, which is wall-clock time. It is the one part of the court that the harness cannot put on the radio clock. `MatchStore` and `FanOutTransport` moved onto the radio clock in `96734b1` (`CourtHarness.swift`, `clockSleep`).
- `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift:546–551` (`.giveUp`) — the stand-in's own "not found" sets `joining = .failed(.notFound)` but leaves the kept code. Only `SharedSession.giveUp(.notFound)` (`SharedSession.swift:851`, `remember(.sharingStopped)`) forgets it, and that fires from the search deadline at `SharedSession.swift:817–829`. The deadline is `searchLimit` = 14 s on the injected `sleep`, which is the radio clock in the harness.
- `Packages/RekkertKit/Sources/RekkertSync/SharedSession.swift:716,806` — `graceBeforeNotice` and `radioGrace` call `Task.sleep` directly instead of the injected `sleep`, so they are wall-clock time in the harness too.
- `Packages/RekkertKit/Tests/RekkertSyncTests/GuestWristTests.swift:8–14` — the test's stand-in timing (`phoneWait` 1 s, `ownWait` 3 s, `grace` 0.5 s) is wall-clock time. The `until(within:)` limits beside it are radio time.
- `Packages/RekkertKit/Tests/RekkertSyncTests/RelayedPointTests.swift:150–165` (`QuietChildTests`) — asserts `heardAfter < 2 s` and `doneAfter < 6 s` measured with `ContinuousClock`, on the main actor.
- `Packages/RekkertKit/Tests/RekkertSyncTests/WatchStandInTests.swift:300–315` — a fixed `Task.sleep(200 ms)` and then a check of state.
- `scripts/verify.sh:22` and `scripts/release.sh:247` — both run the full `swift test`, so a failure here also blocks TestFlight.

## Root Cause Hypothesis

**The new commits did not break the code these tests check. They made the CI run heavy enough that existing wall-clock assumptions now fail on almost every attempt.** Confidence: **high** for the mechanism, **medium** for how much each factor contributes.

1. **Load.** The branch adds about six long court simulations, and `ClubNightTests` now runs at the full guest limit on two radios. The package run goes from 271 s to about 900–1060 s on a 3-vCPU runner. All court tests are `@MainActor`, so they share one serial executor no matter how many cores there are. At startup all 100 suites begin together, and the short court tests that start then have to share the main actor with the long simulations. Every short-test failure happens within the first 35 s of the run.
2. **Two clocks in one test.** The harness steps the radio clock. `WatchStandIn` and a few `SharedSession` waits run on the wall clock. On an idle machine, 50 ms of radio time takes roughly 1–2 ms of wall time, so radio time runs ~30× faster than the wall clock and the wall-clock waits look long. Under load the ratio falls and the order of events changes. `GuestWristTests.swift:102` is the clearest case:
   - **Idle machine:** after the host stops, `joinAgain()` starts two timers. `SharedSession`'s 14 s search deadline (radio time) passes in well under a second of wall time. It wins, calls `giveUp(.notFound)`, and the code is forgotten. The test passes.
   - **Loaded runner:** each step is slow, so the stand-in's 3 s `ownWait` (wall time) runs out first. `WatchStandIn` takes its own `.giveUp` path and sets `.failed(.notFound)` with the code still kept. Line 101 passes, and lines 102–103 fail.
   - This matches the CI logs exactly: line 101 never fails, and 102–103 always do. In the app, both timers are wall-clock time (`ownWait` 20 s against `searchLimit` 14 s), so the session's path wins there.
   - `GuestWristTests.swift:40` has the same shape: a 1 s/3 s stand-in sequence on the wall clock must finish within 10 s of radio time.
3. **Wall-clock budgets on a busy main actor.** `QuietChildTests` (2 s / 6 s) and `WatchStandInTests` (`Task.sleep(200 ms)`) measure real time. They fail when the main actor is busy elsewhere.
4. **Fragility that predates the branch.** The pre-branch tree fails the same tests under the same synthetic load. Spec 001's `ci-test-flakes` (2026-10-28) found the same class of problem: "timing assumptions that only hold on a fast, idle machine". The fix then steadied the individual tests but left the two clocks in place.
5. **New tests that are flaky themselves.** `CalibrationFitTests.swift:68` bisects on replayed p95 values (`Calibration.fit`). Each replay goes through the harness, so the measured p95 picks up harness timing noise, and a noisy comparison can steer the bisection the wrong way. Its 25 % check then fails. It also runs for 350–480 s on CI, which adds to the load.
   - Run alone on an idle machine here, it passed 2/2 in 61–63 s, but the fit swung widely. The radio was known to be 25 ms and 3,000 B/s. Run 1 fitted 78 ms and 3,308 B/s; run 2 fitted 61 ms and 587 B/s. The p95 was within 5 % in run 1 and 14 % in run 2.
   - So even on an idle machine, a 3,000 B/s radio can fit back as 587 B/s. Under CI load the noise grows past the 25 % margin. `BusyHallTests.swift:64` asserts that FR-011's 30 s holds for every late point. It sits outside the `withKnownIssue` block that covers its 1 s/2 s/5 s neighbours, so one starved arrival fails the run.

## Proposed Remediation

**Preferred**: two parts. Ship the first one first; it alone should get CI and TestFlight green again.

1. **Take the long court simulations out of the default `swift test` run.**
   - Gate them behind an opt-in trait, for example `.enabled(if: ProcessInfo.processInfo.environment["REKKERT_LONG_SIMULATIONS"] != nil)` on the suite. Apply it to `BusyHallTests`, `ClubNightTests.twoCourtsFullHalfAnHour*`, `ClockOffsetTests`, `CalibrationFitTests.aRecordFromAKnownRadioIsFittedBackWithinAQuarter`, `OlderHostTests` and `StandInDelayTests`. Also review `LongEveningRecordTests` and "A forgotten share stops by itself".
   - Run them in their own step or job with the variable set and nothing else beside them, either on push or on a schedule (see the open questions).
   - Leave the variable unset in `release.sh`, so TestFlight doesn't wait on calibration predictions.
   - Most of these already keep their spec numbers under `withKnownIssue(… isIntermittent: true)`. They are predictions until T059's field run, not gates, so moving them costs little coverage.
   - This should bring the default run back toward its ~270 s length and free the main actor for the short tests.
2. **Put `WatchStandIn` on the clock it is given.**
   - Inject `now` and `sleep` into `WatchStandIn`, as `MatchStore`, `FanOutTransport` and `SharedSession` already take `sleep`. The defaults stay `ContinuousClock` and `Task.sleep`.
   - Have `CourtHarness` pass the radio clock, so the stand-in's `phoneWait`/`ownWait`/`grace` and the store's timers measure the same time.
   - Route `SharedSession`'s `graceBeforeNotice` and `radioGrace` through the injected `sleep` too.
   - With that, `GuestWristTests.swift:40` and `:102–103` give the same answer however busy the machine is.
   - `GuestWristTests`' stand-in timing then needs to respect the real order: the test's `ownWait` must be longer than `SharedSession.searchLimit` (14 s), or the test must assert the stand-in's own path, depending on the open question about FR-024 below.

**Alternatives**:
- *Run the whole package without parallelism* (`swift test --no-parallel`). This removes the contention, but the run time becomes the sum of every suite, and the long simulations alone are near the 60-minute job timeout today. Not recommended unless part 1 is done anyway.
- *A larger runner.* This helps the CPU part but not the single main actor, and it costs money every run. It does not fix the two clocks.
- *Retry failed tests.* This hides real failures: `GuestWristTests.swift:102` fails every time on CI, so retries would not get TestFlight through anyway.
- *Only widen the wall-clock budgets* (2 s → 10 s and so on). This is cheap for `QuietChildTests` and `WatchStandInTests.swift:314`, but it leaves the clock-order problem in `GuestWristTests` and returns once the suite grows again.

**Files likely to change**:
- `Packages/RekkertKit/Tests/RekkertSyncTests/BusyHallTests.swift`, `ClubNightTests.swift`, `ClockOffsetTests.swift`, `CalibrationFitTests.swift`, `OlderHostTests.swift`, `StandInDelayTests.swift` (and possibly `LongEveningRecordTests.swift`), to add the opt-in trait
- a shared trait or helper in `Packages/RekkertKit/Tests/RekkertSyncTests/` (e.g. next to `CourtHarness.swift`)
- `.github/workflows/test.yml`, for a separate long-simulation step or job
- `scripts/verify.sh` (only if the long step is run from it)
- `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift`, to inject `now`/`sleep`
- `Packages/RekkertKit/Sources/RekkertSync/SharedSession.swift:716,806`, to use the injected `sleep`
- `Packages/RekkertKit/Tests/RekkertSyncTests/CourtHarness.swift:257`, to pass the radio clock to `WatchStandIn`
- `Packages/RekkertKit/Tests/RekkertSyncTests/GuestWristTests.swift`, `RelayedPointTests.swift` (`QuietChildTests`), `WatchStandInTests.swift`, for timings consistent with the radio clock or wider wall-clock budgets
- `Packages/RekkertKit/Tests/RekkertSyncTests/BusyHallTests.swift:64`, to decide whether FR-011's 30 s belongs inside the known issue until T059

**Tests to add or update**:
- The default `swift test` passes under the synthetic-load recipe in *Reproduction* (26 busy loops) for at least 3 runs in a row. Record this in `test.md`.
- On CI, two or more green attempts of the Test workflow and one green TestFlight dispatch on the fixed branch.
- A `CourtHarnessTests` case showing that a `WatchStandIn` wait is measured in radio time: with the machine idle, a 3 s `ownWait` does not run out before 3 s of radio time.
- `GuestWristTests.joiningAgainAfterTheHostStoppedSaysSoAndForgets`, rewritten so the order between the stand-in's `ownWait` and the session's `searchLimit` is explicit, plus a case for the other order once FR-024's intent is settled.
- The long simulations still run (and pass, apart from their known issues) in their own step.

## Risks & Considerations

- **Coverage moves later.** With the long simulations off the default run, a regression in FR-008/FR-010/FR-011 behaviour would show up in the separate step or nightly run, not on every push or before TestFlight. The hard expectations in them (in step at every check, `BusyHallTests.swift:64`, the calibration fit) would no longer block a release.
- **Production code changes for the clock injection.** `WatchStandIn` is shipped watch code. The defaults must stay exactly `ContinuousClock`/`Task.sleep`. `verify.sh` forbids `.nanoseconds(` in code the watch runs (32-bit watches), so any `Duration` arithmetic added for the clock must follow the existing style.
- **The stand-in's own "not found" keeps the code.** In the app this path loses to the 14 s search deadline (20 s > 14 s), so FR-024 holds there. The order depends on the two default timings staying where they are, and nothing checks that.
- **Other changes on the branch.** No uncommitted changes were found (`jj status`: the working copy is empty).
- **More suites on the main actor.** Once the long simulations are gated, the default suite is back near its old size. The two-clock problem in step 2 is still worth fixing, so the next long suite doesn't bring this back.

## Open Questions

- [NEEDS CLARIFICATION: should the long simulations run on every push (separate job), on a schedule, or only on demand before a field run?]
- [NEEDS CLARIFICATION: FR-024, "joining again says nothing is there, and lets the code go". Should `WatchStandIn`'s own `.giveUp` also forget the kept code, so the outcome doesn't depend on which timer fires first?]
- [NEEDS CLARIFICATION: should `BusyHallTests.swift:64` (FR-011's 30 s) and `CalibrationFitTests.swift:68` stay hard expectations, or sit under the same T059 known issue as their neighbours until the field run's record replaces the guessed radio speed?]
