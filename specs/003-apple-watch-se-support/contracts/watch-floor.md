# Contract: The Watch App's watchOS Floor

This covers FR-001, FR-010, FR-012 and User Story 5. It is the promise that keeps the SE (1st
generation) supported after this release.

## The floor

- The watch app installs on **watchOS 10.0 and later**.
- That brings in the SE (1st generation), Series 4 and Series 5, and every newer watch.
- The iPhone app and widget extension stay at iOS 26.
- macOS 26 remains the package's test platform.

Both declarations must agree:

| Declaration | Value |
|---|---|
| `Project.swift`, `RekkertWatch`, `deploymentTargets` | `.watchOS("10.0")` |
| `Packages/RekkertKit/Package.swift`, `platforms` | `.watchOS(.v10)` |

## The fallback rule

Code compiled into the watch app (`WatchApp/`, `Shared/`, `RekkertCore`, `RekkertSync`) may
use something newer than watchOS 10 only behind `#available` or `@available`. There must be
a fallback that either:

- behaves the same for the player (as for `Observations` → tracking, and `Mutex` →
  `OSAllocatedUnfairLock`); or
- leaves the feature out in a way the spec names, and says so where the player would look
  (as for effort ratings in Apple Health).

Existing `watchOS 27` checks (heart-rate zone bands and zone times) already follow this rule.

## The gate (`scripts/verify.sh`)

A new step after the watch app's embedding checks:

```text
==> Assert the watch app still installs on watchOS 10
  ok: "MinimumOSVersion" => "10.0"
```

If the check fails, the gate stops with a message that names the consequence:

```text
FAIL: the watch app's minimum is <found>, not watchOS 10.0 — it would no longer install on Apple Watch SE (1st generation), Series 4 or Series 5
```

Other parts of the gate already enforce the rest:

| Change | What fails |
|---|---|
| `Project.swift` floor raised | the new `MinimumOSVersion` assertion |
| `Package.swift` floor raised alone | the watch app build: the package's minimum is above the target's |
| A watchOS 11+ or 26+ API used without `#available` | the watch app build: availability errors are errors |
| A new file that uses such an API without a fallback | the watch app build |

SC-008 is checked once by hand: raise `Project.swift` to `.watchOS("11.0")` on a scratch
change, run `scripts/verify.sh`, see the failure above, and discard the change.

## Constitution

The Platform & Technical Constraints entry changes from "Targets build for iOS, watchOS, and
macOS 26." to:

```text
Targets build for iOS and macOS 26, and for watchOS 10 so the watch app reaches the watches
that cannot update past it (SE 1st generation, Series 4 and 5). Watch code that uses anything
newer carries a fallback.
```

The version goes 1.0.0 → 1.1.0, with a dated Sync Impact Report entry.
