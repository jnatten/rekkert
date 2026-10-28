# Bug Fix: Package tests fail intermittently on GitHub CI

- **Slug**: ci-test-flakes
- **Fixed**: 2026-10-28
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

This fixes the three CI flakes from the assessment.

- **`CapacityTests`**: the test now waits for every packet to be answered instead of a fixed 250 ms.
- **`WatchStandInTests`**: the phone now dates each standby it sends, and a watch ignores one dated before it last saw its phone go away. Such a standby can arrive after the phone is back and used to make the watch hang up its own link to the host.
- **`AccessTests`**: the host's access list now travels in the same snapshot as the match. A joining guest, and the guest's watch, hold the list from the moment they hold the match, so a scorer no longer briefly has full rights. Nothing becomes read-only, so guests of older hosts keep working as before.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertCore/Sync/Wire.swift` | modified | `SharingStandby.issuedAt: Date?` (optional, defaults to nil). `Wire.snapshot` gains `access: ShareAccessTable? = nil`. Both are optional, so older builds read them as before. |
| `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift` | modified | **Standby:** `stamped(_:)` dates a standby in `send`, `sendDurably` and the reconnect replay; `now` becomes module-internal for `WatchStandIn`. **Snapshot:** `snapshot(forThePair:withTheList:)` carries the host's list (not in live offers) and a guest's copy to its own watch. **Join:** the join takes the list with the match; `adopt(_:publishing:)` lets the join skip the early snapshot that had no role or list. **Receiving:** a snapshot's list is taken through the new `take(_:from:)` (shared with `.access`), only to fill in or bring up to date. **Guest's `.access`:** sent to its own watch only (`sendLiveBesideLinks`), not back over the radio. |
| `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift` | modified | Notes `pairLostAt` (by the store's clock) when it sees the pair go. `heard(.standby)` drops a standby dated before that time. |
| `Packages/RekkertKit/Sources/RekkertSync/FanOutTransport.swift` | modified | When a snapshot goes to another phone, the role and a guest's list are removed, but the host's list is kept. |
| `Packages/RekkertKit/Sources/RekkertSync/LocalNetworkTransport.swift` | modified | Pattern match updated for the new snapshot field. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/CapacityTests.swift` | modified | `aWatchStandingInForAGuestAlreadyOnIsNotTurnedAway` waits until all 9 packets are answered. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/WatchStandInTests.swift` | added tests | A stale "through" is ignored; an undated one is still taken. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/AccessTests.swift` | modified, added tests | `Court.open` also waits for the watch's list. Four new tests, plus `ScriptedHost` and `Overhearing` helpers. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/SharingSignalTests.swift` | modified | `theStandbyIsSaidAgainOnReconnect` compares standbys without their date, and checks that a replay is dated again. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/WireCompatibilityTests.swift` | modified | Round trips for both new fields. An old snapshot and an old standby read with them as nil. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/{OwnWatchTests,RelayedPointTests}.swift` | modified | Pattern matches updated for the new snapshot field. |
| `specs/001-fix-session-sharing/contracts/wire-protocol.md` | modified | Documents `snapshot.access`, the application context's `access`, and `standby.issuedAt`. |

## Diff Highlights

```swift
// WatchStandIn.heard(_:)
case .standby(let standby):
    if let issued = standby?.issuedAt, let lost = pairLostAt, issued < lost { return }

// WatchStandIn.evaluate()
if wasPairReachable, !isPairReachable { pairLostAt = store.now() }

// MatchStore.snapshot(forThePair:withTheList:)
let access = (role == .host && withTheList) || (forThePair && role == .guest) ? accessTable : nil

// MatchStore, the join
adopt(incoming, publishing: false)
...
accessTable = access          // was: accessTable = nil
```

## Tests Added or Updated

- `WatchStandInTests.swift::aThroughSaidBeforeThePhoneWentIsNotTakenForNow`: plays back the ordering from the assessment's trace deterministically. A "through" dated before the phone went away, delivered after it is back, does not stand the watch down. **It fails with the check disabled** (`stops == 1`, `reachablePeers == 0`) and passes with it.
- `WatchStandInTests.swift::anOlderPhoneThatDatesNothingIsTakenAtItsWord`: compatibility. An undated standby still hands back as before.
- `AccessTests.swift::aHostAnswersAJoinWithItsList`: the host's answer to a hello from a phone on another match carries its list.
- `AccessTests.swift::aJoiningGuestHasTheHostsListTheMomentItHasTheMatch`: the scripted host never sends `.access`. The joining phone is `.score` with the host's name as soon as it is a guest. The first snapshot it hands its watch carries the list, and nothing it publishes to the host link does.
- `AccessTests.swift::aGuestsWatchHasTheListTheMomentItHasTheMatch`: a watch handed its guest phone's match is `.score` in the same step.
- `AccessTests.swift::aKeptSnapshotDoesNotPutBackAnotherSharesList`: a snapshot never replaces the current list with another share's, but does bring the same list up to date.
- `AccessTests.swift::aScorerWarmsUpButDoesNotStartTheGame`: unchanged, but `Court.open` now also waits for the watch's list (see Deviations).
- `CapacityTests.swift::aWatchStandingInForAGuestAlreadyOnIsNotTurnedAway`: waits for all answers instead of 250 ms.
- `SharingSignalTests.swift::theStandbyIsSaidAgainOnReconnect`: now also checks that each replay is dated afresh.
- `WireCompatibilityTests.swift`: round trips, and that old payloads read the new fields as nil.

## Local Verification

- `swift build --build-tests --package-path Packages/RekkertKit` → builds with no new warnings in the changed files.
- `swift test --skip-build --package-path Packages/RekkertKit` (full suite, 494 tests in 74 suites):
  - **fix, no load:** 2/2 passed (69.5 s each).
  - **fix, 8 `yes` processes:** 3/3 passed.
  - **`main` (86ffb74, a clean copy built in the scratchpad), same machine and the same load:** 1 of 2 failed on `aPhoneThatIsBackButNotThroughIsNotHandedTheMatch` (`:495`, `:496`) and `aScorerWarmsUpButDoesNotStartTheGame` (`:231`). That is the CI failure, reproduced.
  - The scratch copy of `main` also fails three `HelpTests` because it lacks the repo's README and docs. That's a side effect of the copy, not of either version.
- The affected suites (`AccessTests`, `WireCompatibility`, `SharingSignalTests`, `WatchStandInTests`, `CapacityTests`, `deliveryDoesNotSnowball`, `GuestWatchFollow`, `OwnWatch`, `GuestWrist`, `HostGone`) passed 3/3 consecutive runs.
- Not verified: the iOS/watchOS app targets were not built (`tuist generate` + `xcodebuild`), and nothing was run on devices. No app code matches on `Wire.snapshot` or constructs `SharingStandby` positionally, so the source change should be compatible, but a CI run is the check.

## Deviations from Assessment

1. **Access: the list travels with the match instead of read-only.** The assessment's preferred fix was "a guest's watch is `.readOnly` while it has no table".
   - **Why not:** hosts on TestFlight build 1125959 (2026-10-12) and older have no list at all, so the rule would leave their guests read-only for the whole match. Most test courts also start hosts without a list. The user chose to send the list with the match instead.
   - **How:** the host includes its list in its answer to a hello and in its published snapshot, and the guest passes it on to its watch with the match.
2. **The host's list is left out of live offers, and a guest's `.access` goes only to its own watch.** The first version put the list in every host snapshot, and guests sent their list back over every link.
   - **What happened:** that made `IncidentTests.deliveryDoesNotSnowball` fail in 4 of 4 full runs, against 0 of 4 on `main`. Only the host's first point after a 7-guest join arrived late (20–45 s), reproducible without load.
   - **Bisection in instrumented scratch copies:** both changes are needed to bring that point back to 5.4–5.6 s (`main`: 4.8 s). The live offer goes to every link once per joining guest. A guest's `.access` over the radio was always ignored by the host; at join it now competed with the guest card.
   - **Consequence:** a joiner that happens to take the host's match from a live offer, rather than from the answer to its own hello, still gets the list a round trip later through `.access`, as before. So the window narrows but does not close on that path. `AccessTests.Court.open` therefore waits for the watch's list, which is the test change the assessment proposed.
3. **`CapacityTests` sibling left alone.** The assessment suggested also hardening `sevenGetOnAndTheEighthIsToldThereIsNoRoom`. On reading it, packets on one link are handled in order, so the eighth hello's refusal can only come after the first seven are counted. That test only fails when `eventually`'s 5 s deadline runs out under extreme load.
4. **Scope expansion:**
   - `FanOutTransport.swift` and `LocalNetworkTransport.swift`, for the new snapshot field.
   - `OwnWatchTests.swift`, `RelayedPointTests.swift`, `SharingSignalTests.swift`, for the new field and the standby's date.
   - The wire contract in `specs/001-fix-session-sharing/contracts/wire-protocol.md`.

## Follow-ups

- **Close the live-offer path too:** answer an empty snapshot on the link it came from, with the list, instead of offering the whole match to every link. That would also cut the 7×7 offers at a club-night join, which this fix shows are close to the radio's limit.
- **Load in CI:** a scheduled job that runs `RekkertSyncTests` under artificial CPU load. Under the 14-core saturation from the assessment many more tests fail, so the suite still depends on spare CPU in places.
- **Clock skew:** `issuedAt` is compared across devices. A watch takes its time from its phone, so skew should be small. If a phone's clock is behind by more than the time the pair was apart, the watch hands back late by that skew, at the next replay. It never misses the match: it keeps its own link meanwhile.
- **Log noise:** silence the `SWIFT TASK CONTINUATION MISUSE: sendLive(_:) leaked its continuation` lines in test output.
