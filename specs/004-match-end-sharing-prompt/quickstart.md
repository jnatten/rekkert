# Quickstart: Proving the Between-Matches Flow Works

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Decisions**: [research.md](research.md)

There are four levels, fastest first. The first two run on every push. Suites and tests
marked *(new)* are added by this feature's tasks.

## Prerequisites

- Xcode 27 and the toolchain from `mise.toml` (`mise install`).
- For level 4: four iPhones, each with an Apple Watch, on the same TestFlight or debug build.
  Wi-Fi may be on or off; run it once with it off.

## 1. Device-free tests (seconds; every push)

```bash
swift test --package-path Packages/RekkertKit --filter BetweenMatches
```

```bash
swift test --package-path Packages/RekkertKit --filter "EndOfMatch|NextMatch|StopBetweenMatches|JoinBetweenMatches|HostWithNoMatch|IdleStop"
```

Expected: every test passes. The ones marked "fails today" are written first, and fail on
the tree at `9d930e27` for the reason given (Principle III).

| Test *(new)* | Proves | Fails today |
|---|---|---|
| `BetweenMatchesTests` (RekkertCoreTests) | Who is asked on each side; one question per session; Leave wins over Stay; the idle clock starts at the end of a match, pauses during one, and expires at 30 min | n/a: new type |
| `StopBetweenMatchesTests.stopWithNoMatchOnReachesEveryGuest` | R-3: a host that stops between matches is heard by every waiting guest, which forgets the code and shows the stop notice | **Yes**: guests ignore it |
| `JoinBetweenMatchesTests.aJoinWithNoMatchOnWaitsAsAGuest` | R-5: a guest joining a host with nothing on becomes a guest at once, with the host's name, and gets the first match | **Yes**: it stays joining |
| `JoinBetweenMatchesTests.aJoinMidMatchIsStillAJoin` | R-14: a link that is up before the host's match arrives does not make a waiting guest, and no popup shows | n/a |
| `NextMatchNoticeTests.theNextMatchArrivesWithANotice` | The host's next match opens a notice on the guest's phone and watch, and scoring waits for OK | **Yes**: it arrives silently |
| `NextMatchNoticeTests.aBluetoothGuestGetsTheNextMatchWithinThirtySeconds` | FR-014: the next match reaches a Bluetooth-only guest within spec 001's 30 s | n/a |
| `NextMatchNoticeTests.okOnTheWatchClosesThePhone` | One answer for the pair, within 10 s of being in touch (FR-013) | n/a |
| `EndOfMatchQuestionTests.hostIsAskedWithTheGuestCount` | The host is asked keep or stop, with the count | **Yes**: nobody is asked |
| `EndOfMatchQuestionTests.guestsAreAskedWithinThirtySeconds` | Each guest is asked stay or leave within 30 s, and within 5 s for at least 95% (SC-006) | **Yes**: nobody is asked |
| `EndOfMatchQuestionTests.leaveTakesThePhoneAndTheWatchOff` | FR-009: both devices leave, the code is kept for Join again, and the host's list drops the guest within 15 s | **Yes**: the host shows it out of reach (R-13) |
| `EndOfMatchQuestionTests.aLeaverNeverGetsTheNextMatch` | FR-015 and SC-001: a guest who left stays off, even in range | n/a |
| `EndOfMatchQuestionTests.unansweredIsStay` | FR-012: no answer, then the next match arrives with the notice, and the record says unanswered | n/a |
| `EndOfMatchQuestionTests.keepIsToldToGuests` | D-5: a guest's open question learns "keeping it shared" | n/a |
| `HostWithNoMatchTests.shareFromThePhoneWithNoMatchOn`, `shareFromTheWristWithNoMatchOn` | FR-016: sharing starts with no match on, from the phone and from the watch. Replaces `sharingStartsFromTheWristOnlyWithAMatchOn`. | **Yes**: refused |
| `IdleStopTests.thirtyMinutesWithNoMatchStopsSharing` | FR-026, SC-008: with `TestClock`, stopped by 31 min, guests told with `idle`, host flagged | **Yes**: never stops |
| `IdleStopTests.aRelaunchAfterThirtyMinutesDoesNotShare` | The morning edge case: `endApp`, 31 min, `relaunch`, and nothing goes up | **Yes**: it resumes |
| `IdleStopTests.aGuestRelaunchedAfterThirtyMinutesDoesNotRejoin` | The same for a waiting guest's app | **Yes**: it redials |
| `IdleStopTests.matchesPauseTheClock` | A 45-minute match, then a 25-minute break, still shares | n/a |
| `OlderBuildBetweenMatchesTests` | D-13: an older guest, or an older host, sees today's behaviour, and nothing stalls | n/a |

```bash
swift test --package-path Packages/RekkertKit
```

Expected: the whole package passes, with every existing sharing suite unchanged except the
rewritten `HostWatchSharingTests` rule. Principle II holds.

## 2. The gate (minutes; every push)

```bash
scripts/verify.sh
```

Expected: package tests, project generation, both app builds and every plist assertion
pass. No new Info.plist key or entitlement is expected, since notifications are already in
use. If one turns out to be needed, `verify.sh` gains its assertion in the same change.

## 3. Simulators: the screens

```bash
scripts/share.sh --keep
```

This leaves two iPhone simulators and a watch booted, sharing over the local network, with
the host on a pinned code. Then, by hand, against [contracts/screens.md](contracts/screens.md):

1. On the host, finish the match.
   - The host gets "Keep sharing for the next match?" over the result, with "1 person is
     on".
   - The guest gets "Stay for the host's next match?" within a few seconds, and within 30 s
     at most.
2. On the guest, choose **Stay**. Its Home shows "On … sharing · waiting".
3. On the host, choose **Keep sharing**, then start a new match.
   - The guest gets "… started a new match".
   - Scoring is off on the guest until **OK** is tapped.
4. Finish again.
   - On the guest, choose **Leave**.
   - Start another match on the host. The guest's Home stays as it is.
5. On the host's Home, use **Stop sharing**.
6. Relaunch the host app with no match on, and use **Share** from Home. Join from the guest.
   - The guest shows "waiting" with the host's name before any match is started.
7. The watch simulator, paired to the host phone, shows the host card, **Code** and **Stop
   sharing** with no match on.

Check each screen at the largest Dynamic Type size and with VoiceOver on (FR-023).

## 4. Real devices: one shared evening (before release)

Four iPhones, each with its watch. One hosts and three join. Phones go in bags between
points.

1. **Three matches in a row.**
   - At the end of the first, guest A chooses **Leave** on the watch, guest B chooses
     **Stay** on the phone, and guest C answers nothing.
   - The host chooses **Keep sharing** on the watch.
   - Then:
     - A never sees match 2 (SC-001).
     - B and C each get the new-match alert. C gets it by notification on the wrist, phone
       in the bag.
     - Nobody's screen changes without the alert (SC-002).
2. **Counted taps.** Stop sharing at the end of match 3 is one tap from the result
   (SC-003). Leave between matches is two taps, on a phone and on a watch (SC-004). Show
   the code with no match on is at most two taps, on both (SC-005).
3. **The idle stop.** Leave the host sharing with no match on for 30 minutes, with one
   guest waiting. By 31 minutes both have said why it stopped (SC-008).
4. **Afterwards**, ask each player whether anything appeared that they did not expect
   (SC-007).
5. **The record.** Export the sharing record from the host and from guest C. The answers,
   the unanswered question, the notification and the idle stop are all in it, in order.

Record the outcome in this feature's `validation.md`, the way
`specs/003-apple-watch-se-support/validation.md` does.
