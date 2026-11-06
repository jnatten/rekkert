# Bug Assessment: A 32-bit watch crashes the moment it finds a host over Bluetooth

- **Slug**: watch-bluetooth-timer-overflow
- **Created**: 2026-11-06
- **Source**: pasted text (handed over from another session while assessing `shared-session-wrong-teams`)
- **Verdict**: valid. The code path, the 32-bit arithmetic and the trap are confirmed off the device: the expression was compiled for `arm64_32-apple-watchos10.0`, and its 32-bit arithmetic was run on the Mac. Nobody has watched it happen on a watch yet.
- **Severity**: high

## Report (verbatim or summarized)

> `Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift:92` computes `Int(seconds) * 1_000_000_000` for `DispatchQueue.asyncAfter`. On arm64_32 watches (Apple Watch SE 1st gen, Series 4/5, supported since commit `21c1252`) `Int` is 32 bits, so any delay of 3 s or more overflows and traps. `RadioCore` arms 4 s reply, 10 s proof, 15 s candidate and 15 s proof-limit timers (`RadioCore.swift:143-148`, `:787-794`, `:866`, `:1004`). The watch builds a `BluetoothTransport` in `Shared/AppModel.swift:75`. Confirm which of these paths actually run on the watch (central vs peripheral, `#if os(iOS)` guards), whether a trap is reachable in normal use (for example a guest's watch on a shared session over Bluetooth), and sweep `RekkertSync`/`RekkertCore` for other spots that assume a 64-bit `Int`.

This was first noted as out of scope in `shared-session-wrong-teams/assessment.md` (in the `americano-watchos-10-names-ed82e5` workspace), under Risks.

## Symptom

On a watch that runs the arm64_32 slice, the watch app terminates with an arithmetic-overflow trap whenever it dials a shared match's host over Bluetooth. The trap fires as soon as the scan finds the host's phone, before any data has moved, so a join from the wrist can never succeed. Expected: the watch connects, proves the code and keeps scoring over Bluetooth (FR-004, SE validation row 7).

**Which watches.** The report says only SE (1st generation), Series 4 and Series 5, from `21c1252`. More watches are affected, and for longer:

- The line arrived in `b117e51` (2026-10-27, "run the Bluetooth core under test, with a simulated radio"). Before that, every radio timer was a `DispatchTimeInterval.seconds(Int)`, which is safe on 32 bits because Dispatch widens it to `Int64` itself.
- The floor was then watchOS 26. According to Apple's WWDC25 note, as reported by [MacRumors](https://www.macrumors.com/2025/06/16/watchos-26-moves-apple-watch-to-new-architecture/) and [heise](https://heise.de/-10451081), only Series 9, Series 10 and Ultra 2 moved to arm64 on watchOS 26. Series 8, SE (2nd generation) and Ultra (1st generation) still run arm64_32. Series 6 and 7 have the same chip family as Series 8, so they almost certainly do too, but the sources don't name them.
- So from `b117e51` on, Series 6–8, SE (2nd generation) and Ultra (1st generation) were exposed on watchOS 26. `21c1252` added SE (1st generation), Series 4 and Series 5 on watchOS 10.
- The local Debug device builds of `RekkertWatch.app` in DerivedData are `arm64` only, meaning the watch used for development is a 64-bit one. That, the arm64-only simulators, and tests that run on 64-bit macOS with a simulated clock are why nothing caught it.

## Reproduction

Not yet run on a device. These steps follow the code. Confirming the crash should be the first step of the fix.

1. Install a Release or TestFlight build on an arm64_32 watch: an SE (1st generation) on watchOS 10, or a Series 6–8, SE (2nd generation) or Ultra (1st generation) on watchOS 26. An Xcode run on that watch also works, because a Debug build targets the connected watch's architecture.
2. On a second iPhone, share a match so it hosts and advertises the Bluetooth service.
3. Either of these triggers it:
   - **Join from the wrist.** Open Join on the watch with Rekkert in front, or with a workout running, and type the host's code. Whether or not the watch's own phone is in reach, `WatchStandIn.join` dials from the wrist straight away (`.both`, or `.own` when the phone is out of reach).
   - **Stand in for the phone.** Join on the phone so the watch follows. Then take the watch's phone out of reach, or let its link drop, for more than the 15 s grace while a workout is running. This is quickstart § 3 row 7 of the SE validation, which has not been run yet.
4. Within one scan of the host's phone, the watch app terminates. The crash log should show `EXC_BREAKPOINT` (SIGTRAP) on the `dev.natten.rekkert.bluetooth` queue in `DispatchScheduler.run(after:_:)`, called from `RadioCore.letGoUnlessGreeted(_:)`, which `RadioCore.discovered(_:session:)` calls. [NEEDS CLARIFICATION: confirm the frame names from a real crash log. Symbolication may fold the private `DispatchScheduler` into its caller.]

Evidence collected off the device (scratch files, not in the repo):

- Line 92 compiled for `arm64_32-apple-watchos10.0` with `-O`: the multiply is `smul_with_overflow_Int32` with a `cond_fail "arithmetic overflow"`. For `arm64-apple-watchos10.0` it is `smul_with_overflow_Int64`.
- The same arithmetic in `Int32`, run on the Mac for every delay the radio uses: 1 s fits, 2 s fits, 2.5 s overflows, 3 s overflows, 4 s overflows, 10 s overflows, 15 s overflows. Actually performing the 15 s multiply ended the process with exit code 133 (SIGTRAP). The limit is `Int32.max` ns, about 2.147 s.

## Suspected Code Paths

- `Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift:89-95` (`DispatchScheduler.run(after:_:)`): `Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)`, then `.nanoseconds(Int)`. On arm64_32 the product overflows `Int32` for any delay of about 2.15 s or more, and Swift traps on overflow in `-O` builds. Even without the multiply, `.nanoseconds(Int)` can only hold about 2.1 s on 32 bits, so that case can't be kept in a fix. This is the only `RadioScheduler` used in the app. The tests use `TestClock` (`Tests/RekkertSyncTests/TestClock.swift:6`), so they never reach this line.
- `BluetoothTransport.swift:4`: the real transport is built for `os(iOS) || os(watchOS)`, so the watch gets it. `Shared/AppModel.swift:75` makes one on both platforms, and `:91` passes it to `SharedSession`.

What a watch actually arms. It is only ever a central:

| Timer | Delay | Where | On the watch? | Overflows on arm64_32? |
|---|---|---|---|---|
| liveness tick | 1 s | `RadioCore.swift:250` (`startTicking`, from `startJoining`) | yes, on every join | no |
| redial after a failed connect | 1 s | `RadioCore.swift:924` | yes | no |
| candidate deadline | 15 s | `RadioCore.swift:866` (`letGoUnlessGreeted`, from `discovered` `:855` and `connected` `:895`) | yes, **first trap**: armed right after `radio.connect` for the first host found | **yes** |
| proof deadline | 10 s | `RadioCore.swift:1004` (`awaitProof`, from `notifying` `:997`) | yes, but never reached while the candidate deadline traps first | **yes** |
| reply timeout | 4 s | `RadioCore.swift:383` (`ask`, every `sendLive`) | yes, once a link is up | **yes** |
| proof limit | 15 s | `RadioCore.swift:787` (`subscribed`, host side) | **no**: `startHosting` returns at once when `radio.canHost` is false (`:166`, `BluetoothTransport.swift:147-153`), `openPeripheral`/`publish` are `#if os(iOS)` (`:164`, `:174`), and the watch hosts by asking its phone (`WatchStandIn.startHosting` → `store.send(.startHosting)`) | yes, but only on iOS, where `Int` is 64 bits |

`LinkReplies.patience` deadlines (`RadioCore.swift:425`) are `Duration` arithmetic on `scheduler.now`, not Dispatch, so they are safe.

How the watch gets to `startJoining`:

- `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift:291-321` (`join`): with the radio allowed (Rekkert in front or a workout running, `Shared/AppModel.swift:173`), it calls `sharing.join(code)` immediately alongside asking the phone. When the phone is out of reach, `lookOnTheWrist` (`:485-489`) does the same.
- `WatchStandIn.swift:81-86` (`StandInPolicy`) → `SharedSession.standIn()` (`SharedSession.swift:527-530`) → `dial`: when the phone hasn't been through for 15 s, with a code kept and the radio allowed.
- `SharedSession.swift:404-430` (`dial`) → `bluetooth?.startJoining(code:)` → `RadioCore.startJoining` (`RadioCore.swift:179-189`) → `openCentral` → `centralState(.on)` → `scan` → `discovered` (`:832-856`) → `letGoUnlessGreeted` → trap.
- `CoreBluetoothRadio.centralManagerDidUpdateState` (`BluetoothTransport.swift:376-391`) also reports `retrieveConnectedPeripherals(withServices:)` as found. A host the watch is already connected to at the system level would therefore trap as soon as the radio is on, without a scan.
- `SharedSession.resume()` (`SharedSession.swift:368-379`, from `AppModel.becameActive`) re-dials a join in progress whenever the app comes to the front. So does `joinAgain`.

## Root Cause Hypothesis

`DispatchScheduler.run(after:_:)` turns a `Duration` into Dispatch nanoseconds through `Int`, which is 32 bits on arm64_32. Every guest-side timeout `RadioCore` arms is 4 s or more, so the first one a watch arms traps. That is the 15 s candidate deadline, armed when the first host is found. `b117e51` introduced it when the timers moved behind `RadioScheduler`. The code before used `DispatchTimeInterval.seconds(Int)`, which Dispatch widens to `Int64`. It was not caught because every build and test that ran was 64-bit. **Confidence: high.** The arithmetic is deterministic, the compiled code checks for overflow in `Int32`, and every watch-side join reaches `letGoUnlessGreeted`.

## Proposed Remediation

**Preferred**: Build the deadline without `Int` at all. `Duration / Duration` gives a `Double`, and `DispatchTime + Double` exists. Dispatch converts that `Double` into clamped `Int64` nanoseconds itself:

```swift
func run(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> any RadioTimer {
    let item = DispatchWorkItem(block: work)
    queue.asyncAfter(deadline: .now() + delay / .seconds(1), execute: item)
    return DispatchTimer(item: item)
}
```

This was checked off the device. Compiled for `arm64_32-apple-watchos10.0` at `-O`, the only `Int32` checks left are the stdlib's bounded word-index loop inside `Duration` division, not value arithmetic. On the Mac it gives exactly 1, 2.5, 4 and 15 s. A `Double` holds whole nanoseconds exactly up to about 104 days, so precision doesn't matter here. It needs no change to `RadioScheduler`, `RadioCore` or any timeout value.

**Alternatives**:
- Do the arithmetic in `Int64`, which `Duration.components` already returns, and build `DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds + UInt64(max(0, nanoseconds)))`. This is exact to the nanosecond, but it's more code and adds a clamp to get right, for no practical gain.
- Use `.milliseconds(Int(...))`: Dispatch widens it to `Int64`. This still does `Int` arithmetic, which is safe here only until delays reach about 24.8 days. It fixes this case but leaves the pattern in place.
- Replace the Dispatch timers with `Task.sleep(for:)`. That changes which queue the work runs on, and `RadioCore` relies on everything arriving on the radio's serial queue (`Radio.swift:26-27`). Not worth the risk for this bug.

**Files likely to change**:
- `Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift` (`DispatchScheduler.run(after:_:)`)
- Optionally `Packages/RekkertKit/Sources/RekkertSync/Framing.swift:67` (see Risks)
- `specs/003-apple-watch-se-support/validation.md` (record row 7 and the device check)

**Tests to add or update**:
- A device check on an arm64_32 watch, which is the only thing that proves the fix: join a hosted match from the wrist, then run quickstart § 3 row 7 (phone out of reach, keeps scoring over Bluetooth). If possible, also on a Series 6–8 or SE (2nd generation) on watchOS 26.
- A unit test is of limited use. `DispatchScheduler` is `private` and only built for `os(iOS) || os(watchOS)`, and the package tests run on 64-bit macOS, where the old code doesn't overflow either. If the conversion is pulled out into an internal helper built on every platform, a test can pin that 1 s, 2.5 s, 4 s, 15 s and 20 min come out exact. It protects the form of the fix, not the 32-bit behaviour.
- A guard in `scripts/verify.sh` that fails on `.nanoseconds(` and on `Int(` applied to `.components` in `Packages/RekkertKit/Sources`. It is cheap and catches the pattern coming back. [NEEDS CLARIFICATION: is a grep gate in `verify.sh` welcome, or too blunt?]
- The sibling assessment suggests a CI build of `RekkertCore` for `arm64_32-apple-watchos10.0`. Extending it to `RekkertSync` costs little, but it would **not** have caught this: the overflow happens at run time, not at compile time.

## Risks & Considerations

- **Impact while unfixed.** On every arm64_32 watch, the watch's own Bluetooth link to a host is unusable, and trying to use it crashes the app. A watch-typed join brings the app down even when the phone could have joined alone, because the wrist dials alongside the phone. Mid-match, a phone that drops off the host for 15 s while a workout runs makes the watch stand in, which crashes it. That interrupts the workout until the app is relaunched; `7998c4b` makes a picked-up workout keep collecting, but it has not been checked after this kind of crash. The stand-in can fire again after relaunch under the same conditions. Taps already in the log are persisted, so no score data should be lost. Workaround: keep the phone in reach and join from the phone. 64-bit watches (Series 9 and later, Ultra 2 and later on watchOS 26) and all iPhones are unaffected.
- **Shipped builds.** `8650864` says the 1.0 train is closed in App Store Connect. The App Review work on 2026-10-27/28 suggests 1.0 was built after `b117e51`. [NEEDS CLARIFICATION: does the released 1.0 or any TestFlight build contain `b117e51`? If so, Series 6–8, SE (2nd generation) and Ultra (1st generation) users on 1.0 already crash on watch-side Bluetooth joins, and the fix should ship as 1.1 or as a 1.0.x update rather than wait for SE support.]
- **The other `arm64_32` finding in `RekkertSync`: `Framing.swift:67`.** `FrameCodec.decode` does `Int(buffer.readingBigEndian(at: offset))`, a `UInt32` to `Int` conversion, *before* the `length <= maximumPayload` check. On arm64_32 a header whose length has the top bit set (≥ 2 GiB) traps with "Not enough bits to represent the passed value" instead of throwing `.oversized` and hanging up. The 64-bit devices reject the same frame cleanly. It is only reachable from a peer that already holds the session key: Bluetooth frames are decoded after `LinkSeal` opens them with ChaChaPoly (`LinkSeal.swift:82`, `:107-115`), and the local network decodes inside a TLS-PSK connection (`LocalNetworkTransport.swift:702`). So it takes a broken or hostile peer on the same match. Severity **low**. Fix it alongside, by comparing as `UInt32` first: `guard length <= UInt32(maximumPayload) else { throw .oversized }`, then convert.
- **Nothing else in the sweep assumes a 64-bit `Int`.** The rest of `RekkertSync`/`RekkertCore` checked out:
  - Wire and log counters have explicit widths: `EventID.seq: UInt32` (`Identifiers.swift:15`), the Lamport clock is `UInt64` (`MatchLog.swift:66`), seal frame numbers are `UInt64` (`LinkSeal.swift:49-50`, `:109`), and correlations are `UInt32` with `&+=`.
  - `LocalNetworkTransport`'s timeouts are `DispatchTimeInterval.seconds(Int)`, which Dispatch widens to `Int64`.
  - `WatchConnectivityTransport.swift:150` uses `.now() + 30`, which is a `Double`.
  - `Task.sleep(for:)` and `LinkLiveness` work in `Duration`.
  - `LinkRecord.stamp` uses `Int64` milliseconds (`LinkRecord.swift:247`).
  - Codable `Int` fields stay small: `ShareAccess.revision` goes up by 1 per change, `Greeting.v` is 3, round and court numbers are tiny.
  - Pairing costs top out around 2×10,000 (`LadderScheduler.swift:105`, `RoundScheduler.swift:75-76`).
  - `SessionCode.random` uses the system generator, so no other device has to agree with it.
  - A quick look at `Shared`/`WatchApp` turned up only `Int(x.rounded())` on heart rate, calories and effort, all small.
  - The one width-dependent result is the seeded shuffle (`RoundScheduler.swift:26`, `LadderScheduler.swift:68`), which `shared-session-wrong-teams` already covers.
- **The fix touches only the live scheduler.** `RadioCore` and `TestClock` are unchanged, so the radio's behaviour and its tests stay the same. The only risk is a typo in the conversion, which the device check and an optional helper test cover.

## Open Questions

- [NEEDS CLARIFICATION: is a build containing `b117e51` in the hands of users or testers on 1.0? That decides whether this ships as an urgent update.]
- [NEEDS CLARIFICATION: Series 6 and 7 on watchOS 26 are taken to run arm64_32 because they share the S8's chip family; Apple's note as reported names only Series 8, SE (2nd generation) and Ultra (1st generation). A crash on one of them would settle it.]
- [NEEDS CLARIFICATION: the crash-log frame names, from the first device reproduction.]
- [NEEDS CLARIFICATION: does the `7998c4b` workout recovery pick up cleanly after this crash? That decides how much a mid-match stand-in crash costs the user.]
