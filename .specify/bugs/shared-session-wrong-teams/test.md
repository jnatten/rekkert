# Bug Verification: A 32-bit watch draws different Americano teams from everyone else

- **Slug**: shared-session-wrong-teams
- **Tested**: 2026-11-06
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

Off the device, the fix holds. With the watch's 32-bit `Int` emulated, the old draw disagreed with the phone 7,920 times in 8,000 and the committed draw disagrees 0 times. Phone draws are unchanged from installed builds. The full verification passes and the Release watch binary carries the arm64_32 slice. The assessment's on-device reproduction on an Apple Watch SE (1st generation) was **not** run, so the result is partial rather than verified.

## Checks Performed

Everything ran against commit `d5eb6dda` (jj change `yksvuvvw`). The working copy on top of it was empty.

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction, emulated (post-fix) | `xcrun swiftc -O …/RekkertCore/Tournament/SeededGenerator.swift main.swift`, run on the Mac | pass | Compiles the committed `SeededGenerator.swift` unchanged. 2,000 random tournament ids × 4, 6, 9 and 12 players. Two comparisons. The stdlib walk at `Int64` against `Int32` reproduces the bug (7,920/8,000 differ; the rest are 4-player draws that land on the same permutation by chance). `shuffled(seededBy:)` against the same function transcribed with every `Int` as `Int32` differs 0/8,000. |
| Phones unchanged | Same harness: `shuffled(seededBy:)` against the stdlib's `shuffled(using:)` | pass | 0/8,000 differ, so a fixed build and an installed 64-bit build draw the same teams. |
| Reproduction on the SE (1st generation) | Quickstart § 3 row 5 on the real watch | not-run | No device here. There is also no arm64_32 simulator: every watch simulator is arm64, where the old code already agreed. |
| New tests | `swift test` (via `scripts/verify.sh`), suite "Seeded draws" | pass | All 7 passed: the four scheduler goldens, the Friendly golden (2 cases), `drawsBelowABoundArePinned` and `theSeededShuffleIsTheStdlibsOnSixtyFourBits`. |
| Regression suite | `scripts/verify.sh` | pass | Package tests: 495 tests in 74 suites and 797 tests in 70 suites. Also `tuist generate`, the iOS and watch builds for the simulator, and every plist assertion including the watchOS 10.0 floor. "All checks passed". |
| 32-bit build | `xcodebuild -scheme RekkertWatch -configuration Release -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build`, then `lipo -info` | pass | `arm64 arm64_32`. The fix compiles for the slice the SE runs. |
| Lint (no stdlib draws left on shared paths) | `grep` for `shuffled(using`, `shuffle(using`, `randomElement(using`, `random(in:…using` in `Packages/RekkertKit/Sources`, `Shared`, `WatchApp` and `App` | pass | What remains is `SessionCode.random` and the `LinkSeal` nonce (both the system generator, where nothing has to agree) and the demo history (`DemoGenerator`, seen by one device only). The compiler now rejects any stdlib draw on `SeededGenerator`. |

## Output Excerpts

```text
before the fix, phone vs 32-bit watch differ: 7920/8000
after the fix,  phone vs 32-bit watch differ: 0/8000
after the fix,  phone vs installed phone builds differ: 0/8000
```

```text
Test run with 495 tests in 74 suites passed after 77.613 seconds.
Suite "Seeded draws" passed after 0.146 seconds.
Test run with 797 tests in 70 suites passed after 0.185 seconds.
==> All checks passed
```

```text
Architectures in the fat file: …/Release-watchos/RekkertWatch.app/RekkertWatch are: arm64 arm64_32
```

## Residual Risks

- **No 32-bit hardware was involved.** The emulation transcribes the committed shuffle with `Int32` indices by hand. The real arm64_32 compile of it has been built but never run. The draw itself (`next(below:)`) is all `UInt64`, and `drawsBelowABoundArePinned` pins it to literal values.
- **Installed builds on an SE, Series 4 or Series 5 stay wrong** until they update, and can spread their draw to everyone with "Back to it" on the result screen.
- **The goldens only prove agreement with the toolchain that built them.** If a future Swift changes the stdlib's `next(upperBound:)`, `theSeededShuffleIsTheStdlibsOnSixtyFourBits` would fail even though Rekkert's draws had not moved. That failure would be harmless, and the scheduler goldens are what to trust.
- **A separate 32-bit crash** (the Bluetooth timer overflow) is open as `watch-bluetooth-timer-overflow`. On a 32-bit watch it can stop a shared session from being tested at all until it is fixed.

## Recommendation

Hold. The fix is sound off the device and everything automated passes, but the bug only exists on 32-bit hardware, and nobody has watched it go away there. To close it, install a build from `d5eb6dda` or later on the iPhone paired with the Apple Watch SE (1st generation) and run quickstart § 3 row 5. Play Americano with 6 players and a Friendly with 4, a few rounds each, solo and then on a shared session with another phone. The phone and the SE should show the same teams and benches every round. After a finished Americano, "Back to it" on the SE should change nobody's teams. If the SE crashes on a shared session over Bluetooth first, fix `watch-bluetooth-timer-overflow` before this check.
