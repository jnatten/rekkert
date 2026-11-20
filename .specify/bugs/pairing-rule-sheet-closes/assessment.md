# Bug Assessment: Opening "Keep players apart…" or "Keep two together…" throws the friendly away

- **Slug**: pairing-rule-sheet-closes
- **Created**: 2026-11-20
- **Source**: pasted text
- **Verdict**: valid. Reproduced on simulators (iOS 27.0 and 26.0) with a Debug build of `main` @ `b03026e`, the commit the latest TestFlight build was made from (testflight.yml run 44485178603, 19 Nov). It fails every time, from setup and from the match menu.
- **Severity**: high

## Report (verbatim or summarized)

> whenever i open the "keep two players apart" or "keep two together" menus in friendly matches it instantly closes (and kicks me back to the main menu, not even in the friendly menu).

The buttons are titled **Keep players apart…** and **Keep two together…** (`PairingRulesEditor.swift:34`, `:37`).

## Symptom

Tapping either button shows the rule sheet ("Keep apart" / "Keep together") for a fraction of a second. Then every sheet closes, down to the screen underneath:

- **From friendly setup** (Home → Friendly → Pairing): the rule sheet and the setup sheet both close. The phone is back on Home, and the names and settings typed in are lost.
- **From a friendly in play** (match options → Pairing rules… → either button): the rule sheet and the Pairing rules sheet both close. The phone is back on the scoreboard. The match is unharmed.

Expected (contracts/screens.md §2): the rule sheet stays up until Cancel or Done, and closing it returns to the screen it was opened from.

No crash. The process keeps its pid, and nothing in the log points to a crash.

## Reproduction

By hand, on any build since pairing rules shipped (890e0c5, TestFlight 17 Nov):

1. Home → **Friendly**.
2. Enter four or more player names, so the Pairing section shows its two buttons.
3. Tap **Keep players apart…** (or **Keep two together…**).
4. The sheet flashes up, then the phone is back on Home.

Or in play: start the friendly, then ••• → **Pairing rules…** → **Keep players apart…**. You are back on the scoreboard.

Scripted (Debug build, `axe`): `.specify/bugs/pairing-rule-sheet-closes/repro.sh <udid> <Rekkert.app>`. It reinstalls the app for each case, taps through the four ways in, and reports PASS when the rule sheet is still up 3 s after the tap. Against `b03026e` on iOS 27.0:

```
FAIL setup-apart: "Keep apart" is gone, screen shows: How Rekkert works|Settings|Rekkert (3 extra presentations logged)
FAIL setup-together: "Keep together" is gone, screen shows: How Rekkert works|Settings|Rekkert (3 extra presentations logged)
FAIL setup-with-rule: "Keep apart" is gone, screen shows: How Rekkert works|Settings|Rekkert (4 extra presentations logged)
FAIL inplay-apart: "Keep apart" is gone, screen shows: Thursday|Full screen|Undo (3 extra presentations logged)
```

The PASS check looks for the sheet's inline title as a Heading. The build under test never keeps the sheet up long enough to see that, so the check is inferred: the setup sheet ("Friendly") and the in-play sheet ("Pairing rules") both show their inline titles as Headings in the same tree.

What UIKit logs at the tap (iOS 27.0; iOS 26.0 logs the same lines):

```
E [UIKit:Presentation] Attempt to present <PresentationHostingController: 0x101e1c700> on <PresentationHostingController: 0x101e1d500> (from <NavigationStackHostingController: 0x10e9d2d00>) which is already presenting <PresentationHostingController: 0x101e1e300>.
E [UIKit:Presentation] Attempt to present <…: 0x101e1ea00> on <…: 0x101e1d500> … which is already presenting <…: 0x101e1e300>.
Df [UIKit:Presentation] Warning: Attempt to dismiss from view controller <UIHostingController<…RootView…>: 0x101dbc500> while a presentation or dismiss is in progress!
E [UIKit:Presentation] Attempt to present <…: 0x101e1f100> on <…: 0x101e1d500> … which is already presenting <…: 0x101e1e300>.
```

`0x101e1d500` is the setup sheet, and `0x101e1e300` is the rule sheet that did open. Three more copies try to present on top of the setup sheet and are refused. Then a dismiss arrives at **RootView's** hosting controller, which takes down everything presented above it.

## Suspected Code Paths

- `App/Sources/Views/PairingRulesEditor.swift:52` — `.sheet(item: $editing)` is attached to the `Section` returned by `PairingRulesSection.body` (`:15`). Inside a `Form`, a modifier on a `Section` is applied to each child of the section, not once. This is the cause.
- `App/Sources/Views/PairingRulesEditor.swift:45` — the debug `.task` that opens a rule sheet from `-rekkert-demo-rule-sheet` is attached the same way, so it also runs once per child. That flag now lands on Home too (checked on iOS 27.0), so the rule-sheet screenshot can't be retaken.
- `App/Sources/Views/NewSessionView.swift:600-609` — the setup call site. The `.onChange(of: namedPlayers.map(\.id))` that prunes the rules is attached to `PairingRulesSection`, so it is copied per child as well. Pruning twice gives the same result, so this does no harm, but it is the same pattern.
- `App/Sources/Views/PairingRulesEditor.swift:198-217` — `PairingRulesSheet`, the in-play call site, presented from `MatchOptionsMenu.swift:117-119`.
- `App/Sources/Views/HomeView.swift:203` — presents the setup sheet that gets thrown away.
- `App/Sources/Views/HistoryDetailView.swift:126-128` — earlier lesson in this repo: "Presented from the list itself: a sheet attached to a row goes with the row when it scrolls out of a lazy List, and then never opens." `PairingRulesSection` is the only `.sheet` in the app that doesn't follow it.
- `007-interface-refresh` (not merged): `App/Sources/Refreshed/Friendly/RefreshedPairingRulesSheet.swift:16` embeds the same `PairingRulesSection`, so the refreshed look has the bug too. It becomes a third call site once that branch is rebased.

## Root Cause Hypothesis

`PairingRulesSection` owns its rule-editor sheet and attaches `.sheet(item: $editing)` to its `Section`. In a `Form`, SwiftUI applies a `Section`'s modifiers to each child: the header, every rule row, both add buttons and the footer. A section with no rules therefore holds four presenters bound to the same `editing`. One tap sets `editing`, and all four try to present. The first succeeds. UIKit refuses the other three ("already presenting"), and SwiftUI's attempt to reconcile those presenters ends with a dismiss sent from the root hosting controller. That dismiss closes the rule sheet and the sheet beneath it. The refused presentations track the number of children exactly: 3 with no rules (4 children), 4 with one rule (5 children). It is the same on iOS 26 and 27, so it has been there since pairing rules shipped. It went unnoticed because the editor was only checked through the launch flag. T045 (simulator, by hand) and T046 (real devices) in `specs/006-friendly-pairing-rules/tasks.md` are still unticked. Confidence: **high** for the cause (reproduced, and the count matches). **Medium** for exactly why SwiftUI routes the dismiss to the root, which only matters for curiosity: removing the duplicate presenters removes the trigger.

## Proposed Remediation

**Preferred**: attach the sheet once, to the `Form`, and keep the editor in one place.

- In `PairingRulesEditor.swift`, `PairingRulesSection` stops owning presentation. It takes a `Binding` to the rule being edited (rename `EditedRule` to something non-private, e.g. `PairingRuleEdit`). Its buttons and rows set that binding. Remove `.task` and `.sheet` from the `Section`.
- Add one view modifier beside it, e.g. `.pairingRuleEditor(_ edit: Binding<PairingRuleEdit?>, rules: Binding<[PairingRule]>, players: [Player])`. It holds the single `.sheet(item:)` with the `PairingRuleSheet` save logic from `:53-62`, and the debug `-rekkert-demo-rule-sheet` `.task`.
- `NewSessionView`: add `@State private var editingRule: PairingRuleEdit?`, pass `$editingRule` to the section, and apply `.pairingRuleEditor($editingRule, rules: $pairingRules, players: namedPlayers)` to the `Form` (`:123`, next to `.stepOffConfirmation` at `:140`). It must go on the `Form` itself: `friendlySections` is a `@ViewBuilder` list of sections, and a modifier there gets copied the same way. In the same change, move the pruning `.onChange` (`:607`) from the section to the `Form`.
- `PairingRulesSheet`: the same on its `Form` (`:200`).

This matches the rule `HistoryDetailView` already follows: present from the list, not from inside it.

**Alternatives**:
- Attach the `.sheet` to a single row (for example only the "Keep players apart…" button). This is a smaller diff, but the sheet still lives inside a lazy `Form` row, which `HistoryDetailView.swift:126` already warns against, and the other button would depend on it. Not recommended.
- Push the rule editor onto the surrounding `NavigationStack` instead of opening a second sheet. Both call sites already have one. This avoids nested sheets entirely, but it changes contracts/screens.md §2 ("One sheet") and the Cancel/Done flow, so it is a design change rather than a fix.

**Files likely to change**:
- `App/Sources/Views/PairingRulesEditor.swift`
- `App/Sources/Views/NewSessionView.swift`
- `specs/006-friendly-pairing-rules/quickstart.md` (level 3: reach the rule sheet by tapping, not only through the flag)
- On `007-interface-refresh` once rebased: `App/Sources/Refreshed/Friendly/RefreshedPairingRulesSheet.swift`

**Tests to add or update**:
- The package tests can't see SwiftUI presentation, and the project has no UI-test target. The regression check is `repro.sh` in this folder: all four cases must PASS (no "already presenting" lines; the sheet still up after 3 s; Cancel returns to the setup or Pairing rules sheet). `/speckit-bug-test` should run it on iOS 26 and iOS 27 simulators.
- By hand: Done adds the rule to the section, and editing an existing rule row opens it pre-ticked and saves in place (`:57-61`).
- `scripts/shots.sh` with `-rekkert-demo-rule-sheet apart` takes the rule-sheet shot again (this flag is broken by the same cause today).
- Optional, larger: a UI-test target in `Project.swift` that taps both buttons from setup and from the match menu. It would have caught this, but it is new infrastructure.

## Risks & Considerations

- Setup loses everything typed in while this bug stands. Pairing rules can't be added or edited from any screen, so the whole of spec 006's UI is unreachable on the shipped build. Friendlies without rules play normally.
- The fix touches only the App layer: no protocol, persistence or draw change, and nothing for older watches or guests.
- `SharingSection.swift:31` and `:38` attach two `.confirmationDialog`s (Stop sharing / Leave) to a `Section` the same way. **Not tested.** Either check it with the same method while fixing this, or record it as a follow-up. `MatchTimelineSection.swift:91` puts an `.onAppear` on a `Section`. It sets the same value each time, so it does no harm.
- The demo flag currently "works" by firing its `.task` once per child. Once the `.task` moves into the modifier it runs once. Check that the screenshot still settles in time.

## Open Questions

- [NEEDS CLARIFICATION: which way in did the report come from, setup ("main menu" = Home) or the match menu ("main menu" = the scoreboard)?] Both fail in the same way, so the answer doesn't change the fix.
- [NEEDS CLARIFICATION: iOS version and device the report came from.] Reproduced on iOS 26.0 and 27.0 simulators, but not yet on a real phone.
