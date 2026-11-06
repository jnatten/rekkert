# Bug Fix: A 32-bit watch draws different Americano teams from everyone else

- **Slug**: shared-session-wrong-teams
- **Fixed**: 2026-11-06
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Seeded draws no longer go through the stdlib's `shuffled(using:)`, which draws at the width of `Int`. A new `Array.shuffled(seededBy:)` and `SeededGenerator.next(below:)` do the same Fisher–Yates walk and Lemire draw entirely in `UInt64`. An Apple Watch SE (1st generation), where `Int` is 32 bits, now draws the same teams as the phones. On 64-bit hardware every draw comes out exactly as before, so builds already installed keep agreeing. `SeededGenerator` is no longer a `RandomNumberGenerator`, so the stdlib's `Int`-width draws can't be used on it again.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/SeededGenerator.swift` | modified | Drops the `RandomNumberGenerator` conformance. Adds `next(below:)` (Lemire, `UInt64`) and `Array.shuffled(seededBy:)` (the stdlib's walk, `UInt64` draws). |
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift` | modified | `split` shuffles with `shuffled(seededBy:)`. This covers Americano, Mexicano and Friendly, and the ladder's bench. |
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/LadderScheduler.swift` | modified | The random ladder start shuffles with `shuffled(seededBy:)`. |
| `Shared/AppModel.swift` | modified | The demo history draws its scores through a private `DemoGenerator` that wraps `SeededGenerator`. Same values as before. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/SeededDrawTests.swift` | added test | Golden draws, pinned draw arithmetic, and the stdlib-compatibility check. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/Helpers.swift` | modified | Adds `TestGenerator`, a conforming wrapper for tests that shuffle delivery orders and roll dice. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/MatchLogTests.swift` | modified | Uses `TestGenerator`. Same stream, so the same orders. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/MatchTimelineTests.swift` | modified | Uses `TestGenerator`. Same stream, so the same rolls. |

## Diff Highlights (optional)

```swift
public mutating func next(below bound: UInt64) -> UInt64 {
    precondition(bound > 0, "bound cannot be zero")
    var product = next().multipliedFullWidth(by: bound)
    if product.low < bound {
        let threshold = (0 &- bound) % bound
        while product.low < threshold {
            product = next().multipliedFullWidth(by: bound)
        }
    }
    return product.high
}
```

```swift
let shuffled = players.map(\.id).shuffled(seededBy: &generator)
```

## Tests Added or Updated

All in `Packages/RekkertKit/Tests/RekkertCoreTests/SeededDrawTests.swift`:

- `americanoWithABenchDrawsAsItAlwaysHas`: 6 players on one court, rounds 1-3, teams and bench.
- `americanoOnTwoCourtsDrawsAsItAlwaysHas`: 9 players on two courts, rounds 1-3.
- `mexicanoFirstRoundDrawsAsItAlwaysHas`: 6 players, round 1.
- `randomLadderStartDrawsAsItAlwaysHas`: 10 players, fixed pairs, two courts, random start.
- `friendlyDrawsAsItAlwaysHas(players:teams:bench:)`: 4 and 5 players, rounds 1-3.
- `drawsBelowABoundArePinned`: seed 42, draws below 2, 3, 6, 7, 1000, 2⁴⁰ and `UInt64.max`, pinned to literal values.
- `theSeededShuffleIsTheStdlibsOnSixtyFourBits`: for 1,000 seeds and lengths 0-16, `shuffled(seededBy:)` equals the stdlib's `shuffled(using:)`. It only runs where `Int` is 64 bits.

All the golden values were taken from the unmodified code first. The five scheduler tests passed against it before anything changed, and pass unchanged after the change. The pinned draws came from the stdlib's `next(upperBound:)` on the old conforming generator.

## Local Verification

- Commands run:
  - `swift test --filter SeededDrawTests` on the unmodified code → the 5 scheduler golden tests passed. This confirmed the captured values are what installed builds draw.
  - `swift test` (in `Packages/RekkertKit`) after the change → passed: 495 tests in 74 suites, and 797 tests in 70 suites.
  - `scripts/verify.sh` → "All checks passed". That covers the package tests again, `tuist generate`, the iOS app (with the watch app embedded) and the watch app built for the simulator, and every plist assertion, including the watchOS 10.0 floor.
  - `xcodebuild -scheme RekkertWatch -configuration Release -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build` → succeeded. `lipo -info` lists `arm64 arm64_32`, so the shipped watch binary has the 32-bit slice the SE (1st generation) runs, and the new code compiles for it.
- Manual checks: none on a device. There is no arm64_32 simulator, so the new draw has not run on 32-bit hardware. It uses only `UInt64` arithmetic, and `drawsBelowABoundArePinned` pins its output, but the on-device check is still the SE row in Follow-ups.

## Deviations from Assessment

- The "optional CI step" (build `RekkertCore` for `arm64_32-apple-watchos10.0`) was run once locally as a Release device build of the watch app instead. It was not added to CI.

## Follow-ups

- Run quickstart § 3 row 5 on the SE (1st generation). Americano and Friendly, a few rounds each, solo and on a shared session: the phone and the SE show the same teams and benches. After a finished Americano, "Back to it" on the SE changes nobody's teams.
- Testers on an SE, Series 4 or Series 5 should update. A build from before this fix still draws its own teams on those watches, and can spread them with "Back to it".
- The Bluetooth timer overflow on 32-bit watches (`BluetoothTransport.swift:92`) is still open. It has its own proposed assessment.
