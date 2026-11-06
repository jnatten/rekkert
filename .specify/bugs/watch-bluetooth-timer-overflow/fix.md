# Bug Fix: A 32-bit watch crashes the moment it finds a host over Bluetooth

- **Slug**: watch-bluetooth-timer-overflow
- **Fixed**: 2026-11-06
- **Assessment**: ./assessment.md
- **Status**: applied. Off the device, it is verified by the package tests and by the code compiled for arm64_32. On a watch it is not yet verified; that is `/speckit-bug-test`.

## Summary

The Bluetooth radio's live scheduler built its Dispatch deadline out of `Int` nanoseconds. On the arm64_32 slice that every watch older than Series 9 and Ultra 2 runs, `Int` is 32 bits, so the 15 s candidate deadline trapped as soon as a watch found a host. The deadline is now `.now() + delay / .seconds(1)`, which involves no `Int` at all.

Alongside it, `FrameCodec.decode` now checks a frame's claimed length while it is still a `UInt32`. On the same watches, a length past `Int32.max` used to trap before the check. Finally, `scripts/verify.sh` now fails on `.nanoseconds(` in any code the watch runs.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertSync/BluetoothTransport.swift` | modified | `DispatchScheduler.run(after:_:)`: the deadline is `Duration / Duration` (a `Double`) added to `DispatchTime`, replacing `Int(seconds) * 1_000_000_000` and `.nanoseconds(Int)`. One short comment says why it doesn't go through `Int`. |
| `Packages/RekkertKit/Sources/RekkertSync/Framing.swift` | modified | `decode(from:)`: compares the `UInt32` length against `maximumPayload` before converting it to `Int`. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/FramingTests.swift` | updated test | `anImpossibleLengthIsRefusedBeforeAnythingIsAllocated` now takes the length as an argument: `maximumPayload + 1`, `0x8000_0000` and `UInt32.max`. |
| `scripts/verify.sh` | added check | The first step: fails, listing each hit, on `.nanoseconds(` in `Packages/RekkertKit/Sources`, `Shared` or `WatchApp`. It needs no build, so it fails in seconds. CI runs `verify.sh` on every push. |

## Diff Highlights (optional)

```swift
// BluetoothTransport.swift, DispatchScheduler.run(after:_:)
- let (seconds, attoseconds) = delay.components
- let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
- queue.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds), execute: item)
+ queue.asyncAfter(deadline: .now() + delay / .seconds(1), execute: item)

// Framing.swift, FrameCodec.decode(from:)
- let length = Int(buffer.readingBigEndian(at: offset))
- guard length <= maximumPayload else { throw Fault.oversized }
+ let claimed = buffer.readingBigEndian(at: offset)
+ guard claimed <= maximumPayload else { throw Fault.oversized }
+ let length = Int(claimed)
```

## Tests Added or Updated

- `Packages/RekkertKit/Tests/RekkertSyncTests/FramingTests.swift::anImpossibleLengthIsRefusedBeforeAnythingIsAllocated(absurd:)`: lengths a 32-bit `Int` cannot hold are refused as `.oversized`, the same as any length over the limit. On the 64-bit test host this passed before the change too, so it pins the contract rather than reproducing the trap. The compiled-code check below is what shows the trap is gone.
- `scripts/verify.sh`, "Assert no delay on the watch is counted in Int nanoseconds": the regression guard for the timer. A unit test can't be one, because the package tests run on 64-bit macOS where the old code didn't overflow, and `DispatchScheduler` isn't built there.

## Local Verification

- `swift test --package-path Packages/RekkertKit` → pass: 495 tests in 74 suites and 790 tests in 69 suites, with no failures. All three cases of the widened framing test pass.
- `xcrun swift build --package-path Packages/RekkertKit --triple arm64_32-apple-watchos10.0 --sdk "$(xcrun --sdk watchos --show-sdk-path)" -c release` → `Build complete!`. `lipo -info` on `BluetoothTransport.o` reports `arm64_32`.
- Disassembly of `DispatchScheduler.run(after:_:)` in that arm64_32 release object:
  - **`main`** (built the same way from `git archive main`): `mov w8, #0x3b9aca00` (1,000,000,000), `mul x8, x0, x8`, `cmp x8, w8, sxtw`, `b.ne` → `brk #0x1`. That is the 32-bit overflow check whose failure is the SIGTRAP.
  - **Fixed**: no `mul` and no `brk`. It calls `DispatchTime.now()`, `Duration./`, `DispatchTime + Double` and `asyncAfter(deadline:execute:)`, and nothing else does arithmetic.
- The `verify.sh` gate run on its own: it prints `ok` on the working copy and fails on `main`'s sources, listing `BluetoothTransport.swift:93`. `bash -n scripts/verify.sh` is clean. The full `verify.sh` (generating the project and building both apps for the simulators) was not run; its other steps are unchanged.
- Not verified: anything on a real arm64_32 watch. See Follow-ups.

## Deviations from Assessment

- **`verify.sh` gate added.** The assessment listed it under tests, with an open question about whether a grep gate is welcome. I added it: it is the only check that would catch this pattern coming back, and it follows the existing style of `verify.sh`, which already guards the watchOS 10 floor the same way. It covers only the code the watch runs, so the iOS-only `App` and `Widgets` are free to use `.nanoseconds(`. If it's too blunt, remove the one block.
- **No helper extracted for a unit test.** The assessment offered this as optional and of limited use. Instead, the arm64_32 compile and disassembly verify the fix itself, which a 64-bit unit test couldn't.
- **The `Framing.swift` fix was optional in the assessment, and it is applied**, as its Risks section recommended.

## Follow-ups

- `/speckit-bug-test slug=watch-bluetooth-timer-overflow` on an arm64_32 watch. Join a hosted match from the wrist, then run `specs/003-apple-watch-se-support/quickstart.md` § 3 row 7 (phone out of reach, keeps scoring over Bluetooth) and record it in `validation.md`. If one is at hand, repeat on a Series 6–8 or SE (2nd generation) on watchOS 26.
- Decide how this ships. If the released 1.0 or a TestFlight build contains `b117e51`, watches older than Series 9 and Ultra 2 already crash on wrist-side Bluetooth joins, and this belongs in the next upload rather than waiting for the SE work.
- The cross-compile above works with plain SwiftPM and took about 40 s from cold. It would serve the sibling assessment's suggestion of a CI build of `RekkertKit` for `arm64_32-apple-watchos10.0`, which catches compile-time arm64_32 errors but not run-time ones like this one.
- The seeded shuffle, the other arm64_32 bug, is `shared-session-wrong-teams` and is not touched here.
