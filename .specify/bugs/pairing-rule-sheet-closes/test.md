# Bug Verification: Opening "Keep players apart…" or "Keep two together…" throws the friendly away

- **Slug**: pairing-rule-sheet-closes
- **Tested**: 2026-11-20
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The bug no longer reproduces. Debug builds of the fix commit (`5598d9e`, now `abf1f81` on `main` with identical content) were tested on fresh iOS 27.0 and iOS 26.0 simulators. Both buttons open the rule sheet and leave it up, from setup and from the match menu, with no refused presentations in UIKit's log. The path in the report, typed by hand with no setup flags, works end to end: the rule made in the sheet holds in the first round. `scripts/verify.sh` passes with no regressions.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix), iOS 27.0 | `repro.sh <udid> Rekkert.app` | pass | 4 of 4 PASS, 0 extra presentations. The first run on the cold simulator skipped 2 cases (axe: "Timed out creating the simulator remote automation session"). The rerun passed all 4 |
| Reproduction (post-fix), iOS 26.0 | `repro.sh <udid> Rekkert.app` | pass | 4 of 4 PASS on the first run, 0 extra presentations |
| The reported path, no setup flags (iOS 27.0) | Home → Friendly → type Ada, Bob, Cy, Dan (keyboard left up) → **Keep players apart…** | pass | "Keep apart" sheet stays up listing the four. 0 "already presenting", 0 "Attempt to dismiss" in the UIKit log |
| The rule reaches the match (iOS 27.0) | tick Ada, Bob → **Done** → **Start** | pass | Setup shows "Ada and Bob apart". Round 1 is "Ada & Dan" v "Cy & Bob" |
| Done / Cancel / edit in place (iOS 26.0) | setup flags, then `axe` taps | pass | Done adds "Ada and Bob apart". Cancel closes and leaves the rules unchanged. Editing that row and ticking Cy gives one row, "Ada, Bob and Cy apart" |
| In play: add, save, reopen (iOS 26.0) | `-rekkert-demo friendly -rekkert-demo-pairing-rules`, then taps | pass | Done goes back to Pairing rules with "Kari and Trond together". Save closes it. ••• → Pairing rules… shows the rule |
| Screenshot flag (iOS 26.0) | `-rekkert-demo-rule-sheet apart` | pass | Keep apart sheet up over setup (it went back to Home before the fix) |
| The same flows on iOS 27.0 | as above | pass | Run during `/speckit-bug-fix` on the same source (fix.md, Local Verification) |
| Regression suite | `scripts/verify.sh` | pass | "All checks passed". Package tests 608/105 suites, 942/85 suites, 21/10 suites with 39 known issues. Project generation, both app builds and plist assertions pass |
| Lint / type-check | (none configured) | not-run | The repo has no SwiftLint or swift-format. The Swift compiler in both app builds is the type check, and it passed |

## Output Excerpts

```
== iOS 27 (second run)
PASS setup-apart: "Keep apart" is still up (0 extra presentations logged)
PASS setup-together: "Keep together" is still up (0 extra presentations logged)
PASS setup-with-rule: "Keep apart" is still up (0 extra presentations logged)
PASS inplay-apart: "Keep apart" is still up (0 extra presentations logged)
== iOS 26
PASS setup-apart / setup-together / setup-with-rule / inplay-apart (0 extra presentations logged)
```

```
Test run with 608 tests in 105 suites passed after 63.221 seconds.
Test run with 942 tests in 85 suites passed after 15.679 seconds.
Test run with 21 tests in 10 suites passed after 736.275 seconds with 39 known issues.
==> All checks passed
```

The 39 known issues are timing expectations already marked as known (`ClubNightTests.swift:127-142`, `BusyHallTests.swift:72`). They were 35 in the same suite during `/speckit-bug-fix`. These are the sharing-latency tests, and the fix doesn't touch sharing. The "SWIFT TASK CONTINUATION MISUSE: sendLive(_:)" lines show in both runs (1,064 then, 986 now), and also come from the sharing tests.

## Residual Risks

- **Not tried on a real phone.** All checks ran on simulators. The bug and the fix behave the same on iOS 26.0 and 27.0, but the next TestFlight build should be tried on the phone that reported it. That is also T046 in `specs/006-friendly-pairing-rules/tasks.md`.
- Not checked at the largest Dynamic Type size or with VoiceOver, which quickstart level 3 asks for. The fix changes where the sheet is attached, not how anything is laid out or labelled.
- `repro.sh` can skip cases on a simulator that has only just booted, while axe's automation session starts. It says why when it does. Run it again before reading a skip as a failure.
- `007-interface-refresh` still has the old `PairingRulesSection` call in `RefreshedPairingRulesSheet.swift:16`. It will not compile until it gets the same change (fix.md, Follow-ups).
- `SharingSection.swift:31,38` uses the same Section-modifier pattern for its confirmation dialogs. It is still untested.

## Recommendation

Close the bug: verified end to end on iOS 26 and 27 simulators, including the path in the report typed by hand. Send the next TestFlight build with this fix, and confirm it on the phone that reported it. Carry the `007-interface-refresh` call site and the `SharingSection` check as follow-ups.
