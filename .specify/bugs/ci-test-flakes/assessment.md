# Bug Assessment: Package tests fail intermittently on GitHub CI

- **Slug**: ci-test-flakes
- **Created**: 2026-10-28
- **Source**: https://github.com/jnatten/rekkert/actions/runs/40652726799/attempts/3 (host `github.com`, policy branch: `allowlisted`; read through `gh run view --log-failed` for attempts 1–3 of run 40652726799, plus the other failed runs listed below)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

> flake on github ci runs
>
> https://github.com/jnatten/rekkert/actions/runs/40652726799/attempts/3

Run 40652726799 is the manually dispatched **TestFlight** workflow on `main` @ `86ffb74`. Attempts 1, 2 and 3 all failed in **Test, archive and upload** (`scripts/release.sh` → `swift test --package-path Packages/RekkertKit`), so nothing was uploaded. Each attempt failed on a different set of tests:

| Attempt | Failing expectations |
|---|---|
| 1 | `WatchStandInTests.swift:495` + `:496`, `AccessTests.swift:231`, `CapacityTests.swift:101` (4 issues) |
| 2 | `WatchStandInTests.swift:495` + `:496`, `AccessTests.swift:231` (3 issues) |
| 3 | `WatchStandInTests.swift:495` (1 issue) |

The failures are not limited to this run. Every recent failure of `test.yml` and `testflight.yml` comes from the same few tests:

| Run | Commit | Failing test(s) |
|---|---|---|
| 40648213944 (Test) | 9ff162b | `aScorerWarmsUpButDoesNotStartTheGame` |
| 40646890953 (Test) | 9ff162b | `aPhoneThatIsBackButNotThroughIsNotHandedTheMatch` |
| 40643061056 (Test) | 6b729bc | all three below; the same commit **passed** 5 min earlier in 40642569686 |
| 40520270744 / 40518564992 (Test) | 2d6848e / 1d8f8d2 | `aScorerWarmsUpButDoesNotStartTheGame` |
| 40359975429 attempts 1–2 (TestFlight) | c6234bb | `aScorerWarmsUpButDoesNotStartTheGame` (attempt 3 passed) |
| 38354455135 attempt 1 (Test) | de1d03c | `WorkoutSyncTests.aRatingIsNotRepeatedOnReconnect` (older, not seen since) |
| 37917641297 (Test) | 6dd514e | `RoleTests.aGuestThatMissedACancelledEndingDoesNotKeepIt` (older, not seen since) |

Values recorded at the failing expectations:

- `CapacityTests.swift:101`: `store.participants.all.count → 5` (expected 7).
- `AccessTests.swift:231`: `court.host.state?.warmingUpSince → nil` (the host's warm-up was ended by a scorer).
- `WatchStandInTests.swift:495`: `court.radio.stops → 1`. In attempts 1–2, `:496 court.sharing.reachablePeers > 0` was also false.

The logs also contain many `SWIFT TASK CONTINUATION MISUSE: sendLive(_:) leaked its continuation without resuming it` lines. They appear between passing tests too, and nothing in the failing tests' paths depends on them, so they are noise here, not the cause.

## Symptom

`swift test` for `RekkertKit` fails on the hosted `xcode-27-arm64` runner in roughly half of recent runs, with a different handful of sync tests each time. The same commit passes on a re-run. This blocks TestFlight uploads and makes red builds on `main` meaningless. Expected: the package tests pass every time unless the code is actually broken.

## Reproduction

1. Push to any branch (`test.yml`) or dispatch `testflight.yml`.
2. Watch the package-test step: about half of recent runs fail on one or more of the tests above.
3. Locally: `swift build --build-tests --package-path Packages/RekkertKit`, then run `swift test --skip-build --package-path Packages/RekkertKit --filter RekkertSyncTests` while the CPU is saturated (for example, one `yes > /dev/null` per core). With 14 `yes` on a 14-core Mac, one run produced 41 failing expectations across ~25 tests, including `CapacityTests.swift:101` and the `sevenGetOn…` sibling. That load is heavier than CI, but it shows the suite depends on wall-clock time across the board, not only in the three tests above.
4. With 8 `yes` on the same machine, `aPhoneThatIsBackButNotThroughIsNotHandedTheMatch` failed in 3 of 4 runs, on the same `:495`/`:496` expectations as CI.

[NEEDS CLARIFICATION: the hosted runner's core count. The job log names the image (`xcode-27-arm64`, 20261023.0307.1) but not the hardware.]

## Suspected Code Paths

All 488 tests in 74 suites run in parallel under Swift Testing, and the sync tests are `@MainActor`. One slow main actor therefore delays every test's stores at once. Each flaky test has its own way of turning that delay into a failure:

**1. `CapacityTests.aWatchStandingInForAGuestAlreadyOnIsNotTurnedAway` (test bug)**

- `Packages/RekkertKit/Tests/RekkertSyncTests/CapacityTests.swift:99-101`: sends seven hellos plus a watch's guest card and hello, then waits a fixed `quietPeriod()` (250 ms) and asserts `participants.all.count == 7`. That is a check that something *did* happen, behind a fixed wait. `Eventually.swift:41-51` says this is exactly what `quietPeriod()` must not be used for. On CI only 5 of the 7 hellos had been handled after 250 ms.

**2. `AccessTests.aScorerWarmsUpButDoesNotStartTheGame` (test race, with a small product gap behind it)**

- `Packages/RekkertKit/Tests/RekkertSyncTests/AccessTests.swift:44-51` (`Court.open`): waits for `phone.accessTable != nil` and `!watch.canEndSession`, but **not** for the watch to have the access table.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:415-418` (`access`): `guard let accessTable, !canEndSession else { return .full }`. A guest's watch that already has the host's match (from the phone's snapshot) but not yet the `.access` packet reads as `.full`.
- `MatchStore.swift:238-241` (`endWarmup`): with `.full`, `canRunRounds` is true and the watch records `.endWarmup`. The phone relays the event to the host, which merges it. No check in `MatchStore` measures incoming events against the access table (`accessTable` is only read in `access`, at :416). On CI the snapshot reached the watch before the access table often enough to fail 7 runs.

**3. `WatchStandInTests.aPhoneThatIsBackButNotThroughIsNotHandedTheMatch` (stand-down from a standby that arrives late)**

- `Packages/RekkertKit/Tests/RekkertSyncTests/WatchStandInTests.swift:481-497`.
- `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift:406-466` (`evaluate`): the only way `Radio.stop()` runs in this test is `.standDown`. That needs `isPhoneThrough`: pair reachable, and the phone's last word `isThrough == true` on the same code. `.refused`/`.giveUp` need a pending join, and `leave()`/`stop()` are not called. So after the pair link comes back, the watch heard or kept an `isThrough: true` standby. The test only ever sends `false` once the phone goes away.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1538-1562` (hello from the pair) and `:2178-2186` (`shareStandbyOnReconnect`): every hello from the pair makes the phone send its last standby again, in a `Task` that reads `announcedStandby` when the task runs.
- `MatchStore.swift:1503-1518` (`answer`) → `FanOutTransport.swift:198-253` (`sendLive`, `answer`) → `LoopbackTransport.swift:72-85`: a send hops through about three unstructured tasks between reading the standby and the loopback checking `connected`. Once yielded, a packet is delivered whatever the link's reachability does next. Packet delivery and reachability changes also come in on separate streams (`FanOutTransport.swift:113-127`), so the watch can see them out of order.

**Confirmed locally with a trace.** I ran an instrumented copy of the package from the scratchpad; the project's source files were not touched. The prints were scoped to this test's own phone, watch stand-in and radio, and the sync suite ran under load from 8 `yes` processes. The target test failed in 3 of 4 runs under that load, with the same expectations as on CI. Two later runs with less load passed. Timeline of one failing run (seconds from the test's first standby):

| t (s) | What happened |
|---|---|
| 0.000 | `phoneJoins` sends `standby(isThrough: true)` |
| 0.051, 0.459 | the phone gets hellos from its watch and **replays** `standby(isThrough: true)` |
| 0.491 | the watch hears `isThrough: true` (pair reachable) |
| 0.541 | `phoneGoesAway()`; the test sends `standby(isThrough: false)`, which goes nowhere because the links are cut |
| 0.577 | the watch sees the pair unreachable and clears `isThrough` |
| 0.660 | the watch hears a **stale** `isThrough: true` (pair unreachable, cleared again) and stands in |
| 0.712 | `pairBack`: phone and watch links reachable |
| 0.732 | the watch sees the pair reachable, `phoneStandby.isThrough == false`, standing in |
| 0.750 | the phone replays `isThrough: false` (handled by the watch only at **1.236**) |
| **0.800** | the watch hears **another stale `isThrough: true`**, sent no later than 0.459, with the pair reachable → `.standDown` → `Radio.stop()` |
| 0.800+0.3 | the test's 300 ms sleep ends: `stops == 1`, `reachablePeers == 0`. In CI attempt 3 the late `false` landed in time for a second stand-in, hence `stops == 1` with `reachablePeers > 0`. |

Call stack at the stop: `MatchStore.consumeInbound` → `handle` → `onSharing` → `WatchStandIn.heard(_:)` → `evaluate()` → `SharedSession.standDown()` → `cutLinks()` → `Radio.stop()`.

Under load, a packet from the phone took **340–490 ms** to be handled by the watch. Reachability changes come in on their own stream and were handled within about 20–40 ms. So the watch saw "pair down" and "pair back" *before* it saw a "through" sent while the pair was still up.

## Root Cause Hypothesis

These are not one bug. They are several timing assumptions that only hold on a fast, idle machine. CI's hosted runner is neither, and the suite has grown heavier: `262da9f..6b729bc` added about 7,000 lines to `RekkertKit`, including the club-night and simulated-radio tests (`cb32135`, `b117e51`). That puts more work on one main actor at the same time. Failures cluster from 2026-10-27 onward, after those commits.

- **CapacityTests** (confidence **high**): a positive check behind a fixed 250 ms wait. The recorded count (5 of 7) confirms it.
- **AccessTests** (confidence **high**): the test does not wait for the watch's access table, and until it arrives a guest's watch counts as `.full` (`MatchStore.swift:416`). Nothing downstream re-checks it. In the app the window is short (the snapshot and the access table are sent close together), but it is real: a scorer's watch can end the warm-up or run rounds on the host's match in that moment.
- **WatchStandIn** (confidence **high**, confirmed by the trace above): packets and reachability changes reach `MatchStore` on separate streams with no ordering between them (`FanOutTransport.swift:113-127`, `MatchStore.swift:1100-1101`). Under load, an `isThrough: true` the phone said *before* it went away was handled by the watch *after* the pair came back. `WatchStandIn.evaluate()` clears `isThrough` only while the pair is unreachable (`WatchStandIn.swift:410`), so a "through" heard after reconnect counts as fresh, and the watch stands down from a phone that is not through. The test is right; the behaviour is wrong when deliveries are reordered. In the app the same reordering is possible over WatchConnectivity, whose message and reachability callbacks are also independent, but it should be rare. The cost there is the watch dropping its own link to the host for one `grace` (15 s) plus a redial.

## Proposed Remediation

**Preferred** (one change per test, smallest first):

1. **CapacityTests**: replace the `quietPeriod()` with `await eventually { store.participants.all.count == 7 }` before the count check. Keep a short `quietPeriod()` after it only for the "not refused" check, which is a negative. Also review the sibling `sevenGetOnAndTheEighthIsToldThereIsNoRoom`: its `eventually` waits for the first `.noRoom`, which can come before the seventh hello is handled. Waiting for the count too makes it safe.
2. **AccessTests**: in `Court.open`, also wait for `watch.accessTable != nil` (or `watch.access == <the default>`). Then decide the product question in Open Questions. If a guest's watch should not get full rights while the table is on its way, make `access` return the most restrictive value (`.readOnly`) when `!canEndSession` and `accessTable == nil`. That fixes the gap and the race in one place, and the test then needs no change.
3. **WatchStandIn**: make a standby stale-proof rather than tuning the timing. Give `SharingStandby` an optional `issuedAt: Date`, stamped by the phone each time it is sent, including on the reconnect replay, so the stamp says when the phone last vouched for it. This copies `HostingStatus.issuedAt`, which `WatchStandIn.heard(hosting:)` already uses to drop stale statuses (`WatchStandIn.swift:225-226`). On the watch, note the wall-clock time the pair was last seen to go away. `heard(.standby)` then ignores an `isThrough: true` issued before that time. A standby with no stamp (an older phone) keeps today's behaviour.

   Two simpler-looking fixes do **not** work, as the trace shows:
   - *Only trust a standby heard after the pair came back*: the stale one was heard 88 ms *after* the watch saw the pair come back.
   - *A per-standby sequence number with "newest wins"*: the newer `false` was sent while the links were cut and never arrived, so the stale `true` was the newest the watch had seen.

   Add the trace's ordering as a deterministic test. Hold one `standby(isThrough: true)` back, cut and restore the pair, stand in, then deliver the held packet, and assert no stand-down. `LoopbackTransport` has no "hold live sends" switch today; `setHoldingQueue` covers only the durable queue. The test can push the packet straight into the watch side as `ScriptedGuest` does in `CapacityTests.swift:33-38`, or a small hold switch can be added to `LoopbackTransport`.

**Alternatives**:

- *Run the sync suites `.serialized`, or the package tests with `--no-parallel` on CI.* Less contention and quick to do, but it hides real races like the access gap, and the suite gets much slower (132 s already).
- *Retry failed tests on CI* (a re-run step or a test-repetition flag). Cheap, but it accepts flakiness and would have hidden the access gap.
- *Make the test timings (`quick`, `grace`, `eventually` deadlines) larger.* Fewer CI failures, but it does nothing for the stale-standby ordering, which is a matter of order, not time.

**Files likely to change**:

- `Packages/RekkertKit/Tests/RekkertSyncTests/CapacityTests.swift`
- `Packages/RekkertKit/Tests/RekkertSyncTests/AccessTests.swift`
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift` (`access`, if the product gap is closed; stamping the standby in `send(_:)` and `shareStandbyOnReconnect()`)
- `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift` (`heard(_:)`, `evaluate()`)
- `Packages/RekkertKit/Sources/RekkertCore/Sync/Wire.swift:83` (`SharingStandby` gets an optional `issuedAt`; it travels on the wire)
- `Packages/RekkertKit/Tests/RekkertSyncTests/WatchStandInTests.swift`

**Tests to add or update**:

- CapacityTests: the count check waits with `eventually`. Passes under CPU saturation.
- AccessTests: a guest's watch that has the match but not yet the access table cannot `endWarmup` or score beyond its access. Deterministic: hold the `.access` packet back (for example with a `ScriptedGuest`-style transport, or `LoopbackTransport.setSwallowing`).
- WatchStandIn: a `.standby(isThrough: true)` issued before the phone went away and delivered after it came back does not stand the watch down. A fresh one issued after reconnect still does (the hand-back in `theWatchHandsBackWhenItsPhoneIsThroughAgain` must keep passing).
- A CI check worth keeping: run `RekkertSyncTests` under artificial CPU load a few times in a scheduled job, to catch the next timing assumption before it reaches `main`.

## Risks & Considerations

- **Wire format**: adding `issuedAt` to `SharingStandby` changes what phone and watch exchange. An older counterpart sends none, so the new field must be optional and "no stamp" must keep today's behaviour (as `HostingStatus.issuedAt` does).
- **Behaviour change**: making a guest's watch read-only until its table arrives could briefly disable scoring on the wrist right after a join. That needs a product decision (see Open Questions).
- **Clocks**: `issuedAt` is the phone's wall clock compared against the watch's. A paired watch takes its time from the phone, so the skew is small, but a fix should allow a little slack rather than compare to the millisecond.
- **Masking**: serializing or retrying tests would make CI green but leave the access gap and the stale-standby ordering in the app.
- **Scope**: the local stress run shows many more tests that only pass with spare CPU. Fixing these three stops today's CI failures, but more will appear as the suite grows unless timing-based waits are audited (`quietPeriod()` before positive checks, short `Timing` values).
- **Noise**: the `SWIFT TASK CONTINUATION MISUSE` warnings make CI logs hard to read. They are not part of this failure but are worth silencing separately.

## Open Questions

- [NEEDS CLARIFICATION: should a guest's watch that has the host's match but not yet the access table act as `.readOnly` (safe, briefly unable to score) or as the phone's last-known access (needs the phone to send the table before or with the snapshot)? Today it acts as `.full`.]
- [NEEDS CLARIFICATION: is a scheduled "tests under load" CI job welcome, given the cost of hosted macOS minutes?]
- [NEEDS CLARIFICATION: the hosted runner's core count, to size local load for reproduction.]
