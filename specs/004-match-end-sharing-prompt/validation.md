# Validation: Asking at the End of a Shared Match, and Sharing Between Matches

**Feature**: `004-match-end-sharing-prompt` | Steps from [quickstart.md](quickstart.md)

## Simulators (quickstart § 3), 2026-11-06

Two iPhones on iOS 26.0 (an iPhone 17 Pro paired with an Apple Watch Series 11, and an iPhone
Air), on the debug build. Nothing could be tapped: the run had no access to the simulator panel,
so each step was driven by launch flags and read from screenshots. The new debug-only flags are
`-rekkert-demo-late-finish`, `-rekkert-demo-late-next`, `-rekkert-demo-late-answer` and
`-rekkert-demo-share-empty`.

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Host asked over the result when the match ends | Pass | "Keep sharing for the next match?" with "1 person is on". The result shows behind it. |
| 1 | Host's watch asked in place of Done | Pass | "Keep sharing?", "1 on". It goes back to Done once the phone answers Keep. |
| 1 | Guest asked within 15 s | Pass | Asked over the result, or over Home when the match had nothing played. |
| 2 | Guest told the host is keeping it shared | Pass | "The host is keeping it shared." after the host's Keep |
| 3 | Next match lands on the guest with a popup | Pass | "The host started a new match", over the new match on the phone and full-screen on the watch |
| 3 | Scoring off until OK | Not seen | Needs a tap. Covered by `NextMatchNoticeTests.scoringWaitsForOK`. |
| 4 | Leave at the end of a match | Not seen | Needs a tap. Covered by `EndOfMatchQuestionTests`. |
| 5 | Host's Home with nothing on | Pass | "Sharing on 604 218 · 1 on · until you stop", Stop sharing, and "Shared with 1 on 604 218" under Start |
| 6 | Share with nothing on, guest joins and waits | Pass | The guest's Home shows "On a shared match · Waiting for the host's next match", and Leave |
| 6 | Guest's watch waiting | Pass | "On a shared match · Waiting for the next match", Leave |
| 6 | First match after a wait arrives with the popup | Pass | On the phone and on the watch |
| 7 | Host's watch card with no match on | Not seen | The paired watch was the guest's in that run |
| — | Popups show only their two answers | Fixed | iOS 26 added its own **Cancel** to each alert. On the new-match popup that would have left scoring blocked with nothing left to answer. The answer that putting the popup away should mean is now the cancel button: Keep sharing, Stay, and OK. |

**Largest text size** (accessibility XXXL, phones only; `simctl` cannot set it on the watch):

- **The questions.** Both questions wrap and keep both answers reachable. The host's message scrolls inside the system alert.
- **Home's sharing rows.** These sit below the Start list and could not be scrolled to without a tap. They use the same row layout as the Start rows, which wrap cleanly at that size.

VoiceOver was not checked live.

## Real devices (quickstart § 4)

| | |
|---|---|
| Phones | _four iPhones, models and iOS_ |
| Watches | _four Apple Watches, models and watchOS_ |
| Build | _TestFlight build N_ |
| Date | _date_ |

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Three matches: a leaver never sees the next (SC-001) | | |
| 1 | No screen changes without the popup (SC-002) | | |
| 1 | Unanswered guest gets it by notification on the wrist | | |
| 2 | Stop is one tap from the result (SC-003) | | |
| 2 | Leave between matches in two taps, phone and watch (SC-004) | | |
| 2 | Code shown in two taps with nothing on (SC-005) | | |
| 3 | Idle stop by 31 minutes, everyone told why (SC-008) | | |
| 4 | Players report no surprise match (SC-007) | | |
| 5 | Sharing record holds the answers, notification and idle stop | | |
