# Bug Fix: Opening "Keep players apart…" or "Keep two together…" throws the friendly away

- **Slug**: pairing-rule-sheet-closes
- **Fixed**: 2026-11-20
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The rule editor's sheet is now attached once, to the `Form`, instead of to the Pairing `Section`. The `Section` used to give a copy of it to every row, so one tap opened several sheets and the root threw them all away. Tapping either button now opens the rule sheet and leaves it up, from setup and from the match menu.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `App/Sources/Views/PairingRulesEditor.swift` | modified | `PairingRulesSection` takes `editing: Binding<PairingRuleEdit?>` instead of owning it, and loses its `.sheet` and debug `.task`. New `.pairingRuleSheet(_:rules:players:)` modifier (`PairingRuleSheetPresenter`) holds the one sheet, the save-in-place logic and the `-rekkert-demo-rule-sheet` task, unchanged. `EditedRule` is renamed `PairingRuleEdit` and is no longer private. `PairingRulesSheet` holds the editing state and puts the modifier on its `Form` |
| `App/Sources/Views/NewSessionView.swift` | modified | `@State editingRule`, passed to the section. `.pairingRuleSheet` and the pruning `.onChange` move from the section to the `Form` |
| `specs/006-friendly-pairing-rules/quickstart.md` | modified | Level 3: a flag can't show a sheet that closes when tapped open, so run `repro.sh` as well |
| `.specify/bugs/pairing-rule-sheet-closes/repro.sh` | modified | Waits up to 20 s for the button (first launches on a freshly booted simulator take longer than 8 s) and prints axe's reason when it gives up |

## Diff Highlights

```swift
extension View {
    /// Goes on the Form, never on the Section: a Section hands its modifiers to every row, and
    /// one sheet per row means a tap opens several, which throws away the screen underneath.
    func pairingRuleSheet(
        _ editing: Binding<PairingRuleEdit?>, rules: Binding<[PairingRule]>, players: [Player]
    ) -> some View
```

```swift
            Form { … PairingRulesSection(rules: $pairingRules, editing: $editingRule, …) … }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .pairingRuleSheet($editingRule, rules: $pairingRules, players: namedPlayers)
            .onChange(of: namedPlayers.map(\.id)) { _, ids in
                pairingRules = pairingRules.pruned(to: ids)
            }
```

## Tests Added or Updated

- `.specify/bugs/pairing-rule-sheet-closes/repro.sh` is the regression check: setup apart, setup together, setup with a rule already set, and in play. No package test can see SwiftUI presentation, and the project has no UI-test target. The assessment marks that target optional and larger, so it was not added.
- `specs/006-friendly-pairing-rules/quickstart.md` level 3 now runs the script before the by-hand steps.

## Local Verification

- `scripts/verify.sh` → **All checks passed**. Package tests: 608 tests in 105 suites passed, 942 in 85 passed, and 21 in 10 passed with 35 known issues (issues already marked as known in those sharing tests). Project generation, both app builds and every plist assertion passed.
- `repro.sh` on an iOS 27.0 simulator (iPhone 17 Pro), Debug build of this change:
  ```
  PASS setup-apart: "Keep apart" is still up (0 extra presentations logged)
  PASS setup-together: "Keep together" is still up (0 extra presentations logged)
  PASS setup-with-rule: "Keep apart" is still up (0 extra presentations logged)
  PASS inplay-apart: "Keep apart" is still up (0 extra presentations logged)
  ```
  Against `b03026e` (before the fix), all four failed with 3–4 refused presentations each (assessment).
- Manual checks, driven with `axe` on the same simulator:
  - Setup: **Keep players apart…** → tick Ada, Bob → **Done**. The setup stays up with "Ada and Bob apart" in the section.
  - Setup: **Keep two together…** → **Cancel**. Back on setup, rules unchanged.
  - Setup: tap "Ada and Bob apart" → tick Cy → **Done**. The single row becomes "Ada, Bob and Cy apart", so it was edited in place with Ada and Bob already ticked, and the forecast footer updates.
  - In play (`-rekkert-demo friendly -rekkert-demo-pairing-rules`): **Keep two together…** → Kari, Trond → **Done**. Back on Pairing rules with "Kari and Trond together" and the "Changes apply from the next round" note. **Save** closes it. ••• → **Pairing rules…** shows the saved rule.
  - `-rekkert-demo-rule-sheet apart` puts the Keep apart sheet up over setup again, so the screenshot flag works again (broken before the fix).
- Not run: iOS 26, which `/speckit-bug-test` should cover. Also not checked by hand: the largest Dynamic Type size and VoiceOver.

## Deviations from Assessment

- `repro.sh` changed (not listed under files likely to change). Its 5 s wait was too short on a freshly booted simulator, where it skipped every case without saying why. The cases and the PASS/FAIL check are unchanged. The script's PASS check, which the assessment could only infer, is now confirmed: the rule sheet's inline title reads as a "Keep apart" / "Keep together" Heading.

## Follow-ups

- `007-interface-refresh`: when it is rebased, `RefreshedPairingRulesSheet.swift:16` stops compiling (`PairingRulesSection` now needs `editing:`). Give it a `@State` edit and put `.pairingRuleSheet` on its `Form` the same way.
- `SharingSection.swift:31` and `:38` attach two `.confirmationDialog`s to a `Section`, the same pattern. Still not tested; check Stop sharing / Leave on Home.
- `specs/006-friendly-pairing-rules/tasks.md` T045 (simulator, by hand) and T046 (real devices) are still open. This bug is what they would have caught.
- Retake the rule-sheet screenshot with `scripts/shots.sh` if the current one was captured mid-flash.
