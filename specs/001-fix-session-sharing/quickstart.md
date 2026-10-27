# Quickstart: Proving Sharing Works

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Decisions**: [research.md](research.md)

Four levels, fastest first. The first two run on every push. The third uses the Simulator,
and the fourth needs real devices before release. Hooks marked *(new)* are added by this
feature's tasks.

## Prerequisites

- Xcode 27 and the toolchain from `mise.toml` (`mise install`).
- For level 4: four iPhones and four Apple Watches on the same TestFlight or debug build,
  with **Wi-Fi switched off** on all four phones.

## 1. Device-free tests (seconds; every push)

```bash
swift test --package-path Packages/RekkertKit --filter IncidentTests
```

Expected: every test passes. Each one replays a root cause from [research.md](research.md)
over `SimulatedRadio`, and fails on the code as it was on 2026-10-26 (SC-005):

| Test | Root cause | Passes when |
|---|---|---|
| `hostAppEndedComesBackOnTheSameCode` | RC-1 | Guests are in step within 30 s of the next point scored after the host's app was ended, with no code typed (SC-010) |
| `silentFollowerIsNeverWrittenOff` | RC-2 | A guest that never scores stays in step for 45 simulated minutes |
| `everyGuestGetsTurns` | RC-3 | With 7 guests and one slot freed per callback, every guest receives every point |
| `deliveryDoesNotSnowball` | RC-4 | With 7 guests over 2 simulated hours, per-guest traffic stays bounded and 95% of points arrive within 5 s |
| `guestAppEndedRejoinsWithoutTyping` | RC-5 | A relaunched guest is back on, using the kept code |
| `eighthGuestIsToldNoRoom` | RC-7 | The eighth guest is refused with `noRoom`, and the seven already on are unaffected |
| `guestWatchTakesItsPhonesMatch` | RW-2 | A watch with a warm-up of its own shows the joined match without waiting for a point |
| `standingInWatchCountsOnce` | RW-4 | The host lists one participant for a phone and its standing-in watch |

The rest of the new suites cover the remaining requirements under "Staying on the match"
(SC-011): `HubSchedulerTests`, `PerParticipantDeliveryTests`, `LivenessTests`,
`CapacityTests`, `RestoreTests`, `HostWatchSharingTests`, `GuestWatchFollowTests` and
`KeptCodeTests`.

```bash
swift test --package-path Packages/RekkertKit
```

Expected: the whole package passes, the existing sync suites included. Principle II, the
convergence rule, holds.

## 2. The gate (minutes; every push)

```bash
scripts/verify.sh
```

Expected: package tests, project generation, both app builds and every Info.plist
assertion pass. No new plist keys are expected. If one was added, `verify.sh` asserts it.

## 3. Simulators: the local-network path and the watch screens

```bash
scripts/share.sh
```

Expected: two phones and the guest's watch converge, a killed guest catches up, and *(new)*
a third phase passes. In that phase the host's app is ended and launched again. The host
comes back on the **same code**, and the guest is back in step without anything typed. The
Simulator has no Bluetooth, so this checks the kept code and `restore()`, not the radio.

Screens to look at on a paired watch simulator:

- **Host's watch** *(new launch argument `-rekkert-demo-watch-page code`)*: six digits and
  the QR image. Scan the QR image with another simulator's Camera, or open its link, and
  the join sheet opens.
- **Guest's watch** *(new launch argument `-rekkert-demo-watch-page follow-phone`)*: the
  "Your iPhone is on Ada's match" banner with **Get on it**.
- Menus: check **Share match**, **Code**, **Who's on**, **Stop sharing**, **Join a match**,
  **Join again** and **Leave**, and their tap counts, against
  [contracts/watch-ui.md](contracts/watch-ui.md).

## 4. Field test on real devices (before release; SC-001, 002, 003, 010, 012)

**Set-up**:

- Four iPhones with their watches, Wi-Fi off, Bluetooth on, batteries noted.
- One phone hosts a padel match, best of three sets.
- Every player has "start a workout with the match" on.

| Step | Do | Expect |
|---|---|---|
| 1 | Host taps **Share match** on the watch (phone already in a bag) | The code and QR image show on the host's watch (SC-007) |
| 2 | Three guests join: one by typing on the phone, one by scanning the host's watch, one by typing on the watch | All three in **Who's on** as **In step** within 15 s. Each guest's watch shows the match, through the notification if it was not on screen (FR-027) |
| 3 | Phones into bags. Play a full set, with points tapped on different watches | At every change of ends, all eight devices show the host's score (SC-001) |
| 4 | One guest walks out of range for 5 minutes, then back | The host shows them **Out of reach**, then **In step** within 30 s of return, with nothing touched. Their points from while away count everywhere (SC-003) |
| 5 | *(new, debug builds)* On the host's phone: Settings → **End app as the system would**, then score the next point on any watch | Within 30 s of that point, with nobody touching the host's phone, every guest is back in step, still on the same code (SC-010) |
| 6 | One guest switches Bluetooth off, then on | That guest's watch says "Bluetooth is off on your iPhone", then reconnects by itself (FR-008) |
| 7 | Host taps **Stop sharing** on the watch | Every guest sees "Ada stopped sharing. Saved in History." (US4 AS6) |

**Evidence to keep**:

- Each phone's exported sharing record (Settings → Sharing record → Share). Check that
  someone reading only the records can tell the step-5 break (host's app ended) from a
  guest's watch losing its phone (SC-006).
- From the debug builds' `pointArrived(latency:)` entries, at least 95% within 5 s and all
  within 30 s (SC-002).
- Battery on each phone and watch before and after, beside one unshared match of the same
  length, reported but not gated (SC-012).

## 5. Club night (after release; SC-009)

At the first evening over two neighbouring courts, with a host and up to seven guests, keep
the host's sharing record and two guests'. Expected: no "out of reach" stretch longer than a
player walking off, and every guest in **Who's on** all evening. Compare the arrival times
against the seven-guest simulated test, to check `SimulatedRadio`'s airtime budget.
