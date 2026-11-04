# Bug Assessment: The rating test reads a late send as what the reconnect said

- **Slug**: workout-rating-flake
- **Created**: 2026-11-04
- **Source**: pasted text (loaded test runs while fixing `disconnected-taps-flake`; earlier CI run 38354455135)
- **Verdict**: valid
- **Severity**: low

## Report (verbatim or summarized)

> Flaky test: `WorkoutSyncTests.aRatingIsNotRepeatedOnReconnect`
> (`Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift:298`) fails under CPU load
> with `Expectation failed: paired.workouts.last == .idle`, the last signal being `.rated(…)` or
> `.skipped(…)`. Seen once in 6 loaded `RekkertSyncTests` runs before and once in 6 after the
> disconnected-taps-flake fix. Listed as an older CI flake in `.specify/bugs/ci-test-flakes`
> (run 38354455135).

## Symptom

The test sends `.idle`, a rating and a skip, delivers a hello from the pair, and expects the first
workout signal after the hello to be `.idle`, the standing state said again. Now and then under
load, that first signal is the rating or the skip instead. The reconnect did not say either of
them: they were sent before the hello and arrived late. Expected: the test passes unless the
reconnect really repeats a rating.

## Reproduction

1. `swift build --build-tests --package-path Packages/RekkertKit`
2. Start one `yes > /dev/null` per core (14 on the machine used).
3. Run `swift test --skip-build --package-path Packages/RekkertKit --filter RekkertSyncTests`
   repeatedly. It failed in about one run in six: `last → .rated(…)` in one, `last → .skipped(…)`
   in another.

With logging of what the transport had carried when the test took its count, all 30 runs of the
single test under load saw all six signals. Across the whole suite under load (8 runs):

- In 7 runs the count was taken at five, with the start-up `.idle` still on its way. That straggler
  happened to be an `.idle`, so the test passed by luck.
- In 1 run (run 8) the count was taken at four, with the fan-out's queued `.rated` and the
  start-up `.idle` still on their way. The `.rated` landed first after the hello, and the test
  failed at `:300` with `paired.workouts.last → .rated(…)`.

The failure was forced deterministically with a temporary copy of the test (since removed). The
copy used a recorder that held the live `.skipped` back, took its count by the original `>= 3`
rule, then let `.skipped` land before delivering the hello. It failed 8 of 8 runs with
`paired.workouts.last → .skipped(…)`, the CI failure exactly. With its count taken only once
all six had landed, it passed 8 of 8.

## Suspected Code Paths

- `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift:280-299`: waits for
  `paired.workouts.count >= 3` and takes that count as the line between before and after the
  reconnect. The transport carries six workout signals before the hello, not three.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:2139` (`send(_:)`): each signal goes
  live in its own unstructured `Task`, so they land in no fixed order. `.rated` is also queued
  straight away.
- `Packages/RekkertKit/Sources/RekkertSync/FanOutTransport.swift:217`: a live send to a durable
  child that gets no answer is queued as well when `keepsOverDelay` says so (`:256`, true for
  `.rated`). `RecordingTransport.sendLive` never answers, so the rating is carried a third time,
  last.
- `FanOutTransport.swift:139` and `MatchStore.swift:1227`: `attach` reports the pair reachable
  before the store runs. When the run loop takes that report, `shareWorkoutOnReconnect()`
  (`MatchStore.swift:2216`) says `.idle` once more. The suite is `@MainActor`, so the run loop
  starts only after the three `send` calls, and this sixth signal is always there. It needs a
  main-actor hop, which is the one load delays most.
- `MatchStore.swift:1578`: a hello from the pair says the standing state again. That is one
  `.idle`, and the only workout signal the reconnect sends.

## Root Cause Hypothesis

Confidence **high**: the late signal was seen in the loaded logs and the failure was forced
deterministically.

The test assumes three signals are carried before the hello. The transport carries six: three
live sends, the rating queued by the store, the rating queued again by the fan-out when its live
send goes unanswered, and `.idle` from the store's start-up share. The test takes its count as
soon as it sees three. When the CPU is busy, the rest are still on their way. After the hello,
`eventually { paired.workouts.count > announced }` is then satisfied by the first late one, not
by the reconnect's `.idle`. If that late signal is `.idle`, the test passes by luck. If it is the
rating or the skip, the test fails. Under load the start-up `.idle` is usually the late one,
which is why the failure is rare.

This is not a product bug. Nothing is repeated on reconnect: in every logged run the hello added
exactly one `.idle`.

## Proposed Remediation

**Preferred**: Fix the test only. Wait for all six signals before taking the count. Then nothing
sent before the hello is still in flight, and the first signal after it is the reconnect's. Add
one comment naming the six, because the count is not obvious from the three `send` calls.

**Alternatives**:

- *Wait for the content (three ratings, two `.idle`, one skip) rather than the count.* Same
  meaning, harder to read.
- *Check after a quiet period that the reconnect added only `.idle`.* That makes the "not
  repeated" check stricter, but needs the same complete count before the hello. Without one, a
  late `.rated` still looks repeated. Left out: it goes beyond making the test stable.
- *Make `RecordingTransport.sendLive` answer, so the fan-out does not queue the rating again.*
  That changes a transport other tests in the file rely on (`queuedWorkouts`).

Apply the same fix to `aReconnectIsToldTheLastThingSaidRatherThanTheFirst`, which has the same
race (see Risks): wait for its three signals before taking the count.

**Files likely to change**:

- `Packages/RekkertKit/Tests/RekkertSyncTests/WorkoutSyncTests.swift`
  (`aRatingIsNotRepeatedOnReconnect`, `aReconnectIsToldTheLastThingSaidRatherThanTheFirst`)

**Tests to add or update**:

- `aRatingIsNotRepeatedOnReconnect`: takes its count only once all six signals have landed.
- `aReconnectIsToldTheLastThingSaidRatherThanTheFirst`: takes its count only once all three have
  landed.

## Risks & Considerations

- **Coupling**: the count of six follows from the product's start-up share and the fan-out's
  durable fallback. If either changes, `eventually` waits out its 5 s deadline and the test still
  passes, only slower. The comment names the six so the count can be corrected.
- **Product observation, not changed here**: the store queues a rating itself, and the fan-out
  queues it again when its live send goes unanswered. So the durable channel can carry the same
  rating twice. That is harmless, because the receiver applies the same rating to the same
  workout either way (Principle II holds), but it is redundant.
- **Same pattern, one test down**: `aReconnectIsToldTheLastThingSaidRatherThanTheFirst`
  (`WorkoutSyncTests.swift:333`) takes its count once `held` is seen. Before the hello, three
  signals are carried: `.running` and `held` live, and `held` again from the start-up share. If
  `held`'s live send beats `.running`'s, a late `.running` passes for what the reconnect says and
  `last == held` fails. It has not been seen to fail, but it is the same race, so the same fix
  applies there.

## Open Questions

- None for this fix.
