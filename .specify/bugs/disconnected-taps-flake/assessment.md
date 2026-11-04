# Bug Assessment: Taps made during a cut sometimes reach the watch before the reconnect

- **Slug**: disconnected-taps-flake
- **Created**: 2026-11-04
- **Source**: pasted text (a failing `scripts/verify.sh` run on branch `003-apple-watch-se-support`)
- **Verdict**: valid
- **Severity**: low

## Report (verbatim or summarized)

> Flaky test: `tapsMadeWhileDisconnectedArriveOnReconnect` in
> `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift` failed once at `SyncTests.swift:120`
> with `Expectation failed: points(pair.watch) == BySide(a: 0, b: 0)` ("watch is still in the
> dark") during `swift test --package-path Packages/RekkertKit` via `scripts/verify.sh`. The four
> runs before and after passed with the same code. Seen on branch `003-apple-watch-se-support`,
> which does not touch `RekkertSync`. Follow-up to `.specify/bugs/ci-test-flakes`, which noted
> that the whole `RekkertSyncTests` suite still depends on wall-clock time under load.

## Symptom

The test cuts the phone–watch pair, scores three points on the phone, waits a fixed
`quietPeriod()` and expects the watch to have seen none of them. Now and then, when the suite
runs under load, the watch already shows 3–0 at that check. Expected: nothing reaches the watch
until the link is restored.

## Reproduction

1. `swift build --build-tests --package-path Packages/RekkertKit`
2. Start one `yes > /dev/null` per core (14 on the machine used).
3. Run `swift test --skip-build --package-path Packages/RekkertKit --filter RekkertSyncTests`
   repeatedly. With instrumentation in `MatchStore.queuePending()` (removed again afterwards),
   1 of 6 whole-suite runs failed on this test, with the watch at 3–0.

The single test on its own, `--filter tapsMadeWhileDisconnectedArriveOnReconnect`, passed 30 of
30 runs under the same load: the race needs the main actor kept busy by the other suites.

The race can be forced deterministically in two ways. Both were tried and then removed:

- Tap 3.9 s after `pair.run()`. `retryUndelivered()` wakes for the first time at 4 s and queues
  the taps (`queuePending from retryUndelivered() fresh=3`). The check fails every time.
- Build the pair with `retryInterval: .milliseconds(50)`, so the retry loop runs throughout the
  quiet period. The check failed 5 of 5 runs.

## Suspected Code Paths

- `Packages/RekkertKit/Sources/RekkertSync/LoopbackTransport.swift:88-99`: `queue(_:)` stands in
  for `transferUserInfo` and is "delivered even when the peer is 'unreachable'". Only
  `setHoldingQueue` stops it. `setDroppingOutgoing` stops `sendLive` and `publishSnapshot`, but
  not this.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1207-1214` (`queuePending()`): hands
  everything the outbox still holds to `transport.queue`. It reads the outbox when it runs, not
  when the failed send was decided on.
- `MatchStore.swift:1353-1373` (`sendPending()`): checks `transport.isReachable`, starts a live
  send, and calls `queuePending()` if it comes back `nil`.
- `MatchStore.swift:1489-1535` (`sendLive` / `answer`): the transport's `sendLive` runs in an
  unstructured `Task`, off the main actor. A send decided while the link was up can therefore
  reach `LoopbackTransport.sendLive` only after the cut. It is then refused without being
  counted in `unanswered`, so `waitOutAnswers` has nothing to wait for.
- `MatchStore.swift:1187-1206` (`retryUndelivered()`): every `retryInterval` (4 s by default),
  if the outbox is not empty and the link is down, calls `queuePending()`.
- `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift:107-127`: the test cuts the live
  link only and leaves the durable queue open.

## Root Cause Hypothesis

Confidence **high**: the failure was captured under load and reproduced deterministically.

The test assumes that `setDroppingOutgoing(true)` on both ends, followed by `waitOutAnswers`,
keeps everything from the watch. It cuts only the live channel. The durable queue still delivers,
by design, and `MatchStore` falls back to it whenever something cannot go live. Two triggers
were seen:

1. **A flush in flight at the cut.** This is what happened in the loaded run. The phone's
   `configure` event was still unacknowledged when `inStep` became true. A `sendPending()` had
   passed its `isReachable` guard and started a live send, but that send reached the transport
   only after the test had set the drop. The transport refused it as "not asked", so
   `waitOutAnswers` returned at once. The test then tapped three times in the same main-actor
   turn. When `sendPending()` resumed with `nil`, `queuePending()` read the outbox (`configure`
   plus three taps, `fresh=4`, 1.8 ms after the taps) and queued all four. The watch merged them
   before the 250 ms quiet period was up.
2. **A retry tick inside the quiet period.** If the taps land just before a `retryUndelivered()`
   wake-up (4 s, 8 s, … after `run()`), the retry finds the link down and queues the backlog.
   A slow run reaches the taps late enough for this to happen.

Both end in `transport.queue`, which a dropped link does not stop. The fixed `quietPeriod()` is
not the cause. Per `Eventually.swift` it is the right wait before a "nothing happened" check, but
"nothing" only holds while every channel to the watch is closed.

This is not a product bug. Handing whatever could not go live to the durable queue is how a
counterpart whose app is not running catches up (`transferUserInfo`). Merging is idempotent, so
a duplicate that also arrives live does no harm. That is Principle II's convergence working as
intended. Reading the outbox when the fallback runs, rather than when the send was decided,
only ever queues more of what the counterpart lacks.

## Proposed Remediation

**Preferred**: Fix the test, not the product. Cut every channel to the watch: hold the durable
queue on both ends (`setHoldingQueue(true)`) at the same time as dropping live traffic. This
follows `GuestWatchFollowTests.joinBehindTheWatchsBack()`, which also cuts with "nothing live
either way, and nothing either queues let through". Every remaining path is then closed by
construction:

- live sends are dropped;
- the durable queue is held;
- `publishSnapshot` is gated on `isReachable`, which includes the drop;
- replies to questions asked before the cut are waited out by `waitOutAnswers`.

Leave the queue held through the reconnect. Then the reconnect's own resync has to deliver the
taps, which is what the test's name claims. A backlog released at the same moment could
otherwise deliver them in its place.

To make the test fail for the stated reason rather than by chance (Principle III), build its
pair with `retryInterval: .milliseconds(50)`. The retry loop then queues the taps inside the
quiet period on every run. Without the hold the test fails every time; with it, it passes. `Pair`
gets an optional `retryInterval` that defaults to the store's 4 s, so the other tests in the
file are unchanged. `OwnWatchTests`' harness does the same.

**Alternatives**:

- *A longer `quietPeriod()` or a shorter wait before the check.* That only moves the window and
  does nothing for a flush already in flight. The task rules it out.
- *Make `setDroppingOutgoing` also hold the queue.* It would hide the durable channel from the
  tests that rely on it getting through a drop, such as `DurableQueueTests`.
- *Count a send as asked when it is decided on, not when it reaches the transport.* That makes
  `waitOutAnswers` also cover sends in flight. It would close trigger 1 only, and it changes the
  transport's counting for every test.

**Files likely to change**:

- `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift` (`Pair.init`,
  `tapsMadeWhileDisconnectedArriveOnReconnect`)

**Tests to add or update**:

- `tapsMadeWhileDisconnectedArriveOnReconnect`: runs with a 50 ms retry so the durable queue is
  offered the taps during the cut, holds the queue, and still expects the watch to stay at 0–0
  until the reconnect and then reach 3–0 from the reconnect alone.

## Risks & Considerations

- **Coverage**: with the queue held to the end, the test no longer checks the durable path on
  reconnect. `DurableQueueTests` and `ResilienceTests` cover that path.
- **Siblings**: `aCatchUpOfSeveralPointsIsNotAnnouncedAtAll` (`SyncTests.swift:757`) cuts with
  `setReachable(false)`, also without holding the queue. A queued batch of five taps is a
  catch-up, which is not announced, so its `announced.isEmpty` check still holds. It is left
  alone.
- **Other flakes**: one of the six loaded runs failed elsewhere instead,
  `WorkoutSyncTests.aRatingIsNotRepeatedOnReconnect` (`WorkoutSyncTests.swift:298`, last was
  `.rated` rather than `.idle`). That test counts sends that arrive in no fixed order, a
  different mechanism. It is out of scope here.

## Open Questions

- None for this fix.
