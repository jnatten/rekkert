# Bug Verification: A 32-bit watch crashes the moment it finds a host over Bluetooth

- **Slug**: watch-bluetooth-timer-overflow
- **Tested**: 2026-11-06
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial. Everything that can be checked off the device passes, with no regressions. The assessment's reproduction on a real arm64_32 watch has not been run, because none is at hand.

## Summary

Off the device, the fix holds. Three runs of the watch's real join code (`RadioCore` and `WatchStandIn` over the simulated radio) cover a code typed on the wrist, the watch standing in for its phone (SE validation row 7), and a relaunched watch dialling again by itself. Each gets the watch onto the match. Each arms 4 s, 10 s and 15 s timers that `main`'s conversion overflows at 32 bits, and that the fixed conversion turns into exact deadlines.

In `RekkertSync` compiled for `arm64_32-apple-watchos10.0`, `main`'s `DispatchScheduler.run(after:_:)` contains the multiply by 1,000,000,000 and its overflow trap, and the fixed one has neither. The same is true of `FrameCodec.decode`'s length trap. The full `scripts/verify.sh` passes. What is still unproven is that a 32-bit watch with real CoreBluetooth no longer crashes.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction on an arm64_32 watch (post-fix) | Assessment § Reproduction on an SE (1st generation), Series 4–8, SE (2nd generation) or Ultra (1st generation) | not-run | No arm64_32 watch here. `xcrun devicectl list devices` shows one physical watch, an Apple Watch Ultra 2 (Watch7,5), which runs arm64 on watchOS 26 and could not reproduce the crash before the fix either. Every watch simulator is arm64. |
| Reproduction, simulated: code typed on the wrist | `swift test --filter WatchDelayReplay` in a scratch copy of the package | pass | The phone is in a bag and the code is typed on the watch. The watch gets on the match. Its radio armed 1 s ×11, 4 s ×2, 10 s ×1 and 15 s ×2. The first timer the old conversion traps on is 15 s, the candidate deadline, as the assessment predicted. |
| Reproduction, simulated: stand-in (row 7) | same | pass | The phone joins, then is cut off from the watch and the host, so the watch stands in and catches up. The timers are the same, and so is the first trap. |
| Reproduction, simulated: relaunched watch | same | pass | The watch app is ended and run again with its phone out of reach. It brings its own Bluetooth link up by itself and catches up: 1 s ×1, 4 s ×1, 10 s ×1, 15 s ×2. On `main` this would crash again on every relaunch. |
| Trap removed from the compiled watch code | `xcrun swift build --triple arm64_32-apple-watchos10.0 … -c release`, for the fix commit and for `git archive main`, then `llvm-objdump` on `DispatchScheduler.run(after:_:)` | pass | `main`: `brk` ×6, one `mul`, the constant `0x3b9aca00`, and the overflow check `cmp x8, w8, sxtw` → `b.ne` → `brk #0x1`. Fixed: no `brk`, no `mul`, no constant. It only calls `DispatchTime.now()`, `Duration./`, `DispatchTime + Double` and `asyncAfter`. `lipo` reports `arm64_32` for both. |
| Frame-length trap removed from the compiled code | same, the specialized `FrameCodec.decode(from:)` | pass | `main` tests the length's sign bit and branches to a trap (`tbnz w0, #0x1f`) before `cmp w0, #0x400, lsl #12` (4 MiB). The fixed build compares with 4 MiB first and has no sign-bit trap. That function goes from 17 `brk` to 16. |
| Updated test | `swift test --package-path Packages/RekkertKit`, inside `verify.sh` | pass | `anImpossibleLengthIsRefusedBeforeAnythingIsAllocated(absurd:)` passes for 4194305, 2147483648 and 4294967295 (run under `/speckit-bug-fix`; the package tests in `verify.sh` include it again). |
| Regression suite | `scripts/verify.sh` (the same as CI) | pass | 123 s, exit 0. The new gate prints `ok`. 495 tests in 74 suites and 790 in 69 pass. `tuist generate`, the iOS app and the watch app build for the simulators, and every plist, entitlement and manifest check passes. |
| `verify.sh` gate catches the old code | The gate's grep run against `git archive main` | pass | It lists `BluetoothTransport.swift:93` and fails (checked under `/speckit-bug-fix`). |
| Lint / type-check | none configured | skipped | The project has no SwiftLint or SwiftFormat. Compiling for macOS, the simulators and arm64_32 is the type-check, and all of them succeed. |

## Output Excerpts

```text
REPLAY join from the wrist:   4.0 seconds x2  old(Int32)=OVERFLOW -> trap  fixed=4000000000 ns
REPLAY join from the wrist:   10.0 seconds x1  old(Int32)=OVERFLOW -> trap  fixed=10000000000 ns
REPLAY join from the wrist:   15.0 seconds x2  old(Int32)=OVERFLOW -> trap  fixed=15000000000 ns
REPLAY join from the wrist: first timer the old code would trap on = 15.0 seconds
REPLAY relaunched watch: own Bluetooth link up = true
Test run with 3 tests in 1 suite passed after 2.032 seconds.
```

```text
main, arm64_32, DispatchScheduler.run(after:_:)
    mov   w8, #0xca00
    movk  w8, #0x3b9a, lsl #16      ; 1_000_000_000
    mul   x8, x0, x8
    cmp   x8, w8, sxtw              ; does the product fit 32 bits?
    b.ne  … → brk #0x1              ; no: SIGTRAP
fix, arm64_32: brk=0 mul=0 0x3b9a=0
```

```text
==> Assert no delay on the watch is counted in Int nanoseconds
  ok: no .nanoseconds( in code the watch runs
Test run with 495 tests in 74 suites passed after 57.958 seconds.
Test run with 790 tests in 69 suites passed after 0.291 seconds.
==> All checks passed
exit=0 after 123s
```

How the replay was set up: the package was copied to the scratch directory, identical to the fix commit (`diff -rq` on `Sources`). In the copy, `SimulatedRadio.scheduler` was wrapped to record every delay a `canHost: false` radio (a watch) arms, and a three-test suite was added based on `GuestWristTests`. "old(Int32)" is `main`'s arithmetic redone in `Int32`. "fixed" is the fix's expression, evaluated on the Mac. Nothing in the repository was changed for this.

## Residual Risks

- **No 32-bit watch has run the fix.** The simulated radio is not CoreBluetooth. In particular, the path where `centralManagerDidUpdateState` reports peripherals it is already connected to, and Dispatch's own handling of the deadline on arm64_32, have not run on a device. The disassembly shows the fixed function doing no `Int` arithmetic of its own, so a crash from the same cause is very unlikely, but the device check is what closes it.
- **`main`'s 32-bit arithmetic is reproduced, not run.** The "old" column mirrors `main`'s expression in `Int32`. The compiled `main` binary shows the same trap, but it was not executed, since there is no arm64_32 runtime.
- **The fixed delays were computed on 64-bit macOS.** On the watch, the same `Duration` and Dispatch library calls do the work.
- **Other 32-bit bugs in the same flows.** This verification is only about the timer and frame-length traps. The seeded-shuffle bug (`shared-session-wrong-teams`) is still open and shows up in Americano and Friendly matches on the same watches.
- **Builds already installed.** Anything built from `b117e51` up to this fix keeps crashing on arm64_32 watches until it is updated.

## Recommendation

Hold rather than close. The fix is sound as far as can be checked without the hardware, and it is safe to merge and ship: the bug is gone in simulation and from the compiled watch code, and `verify.sh` is green. To close it, put a build containing `4ec0f309` on an arm64_32 watch. An SE (1st generation) on watchOS 10 is best; a Series 6–8, SE (2nd generation) or Ultra (1st generation) on watchOS 26 also works. Then:

1. Join a hosted match by typing its code on the wrist.
2. Run `specs/003-apple-watch-se-support/quickstart.md` § 3 row 7.
3. End the watch app and reopen it with the phone out of reach.

Record the results in `validation.md`. If the watch crashes, take the crash log and re-run `/speckit-bug-assess` with it.
