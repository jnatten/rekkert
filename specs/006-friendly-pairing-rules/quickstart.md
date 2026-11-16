# Quickstart: Proving Pairing Rules Work

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Decisions**: [research.md](research.md)

There are four levels, fastest first. The first two run on every push. Tests marked *(new)*
are added by this feature's tasks. "Fails today" means the test is written first and fails at
`0d4ff41b` for the reason given (Principle III).

## Prerequisites

- Xcode 27 and the toolchain from `mise.toml` (`mise install`).
- For level 4: two iPhones with watches on this build, and one iPhone on the current App Store
  or TestFlight build (1.2).

## 1. Device-free tests (seconds; every push)

**Write this one first, before touching the draw**, and commit it green on today's code:

```bash
swift test --package-path Packages/RekkertKit --filter FriendlyNoRulesFingerprint
```

| Test *(new)* | Proves | Fails today |
|---|---|---|
| `FriendlyNoRulesFingerprintTests` (RekkertCoreTests) | SC-003 and FR-005: every round for 2 to 12 players over 30 rounds, by name and sides and bench, as drawn at `0d4ff41b`. Must stay green through the whole feature. | No: it pins today |

Then the rest:

```bash
swift test --package-path Packages/RekkertKit --filter "PairingRules|FriendlyPairingDraw|PairingForecast|FriendlyPlacement|Preset|WireCompatibility"
```

| Test *(new)* | Proves | Fails today |
|---|---|---|
| `PairingRulesTests.wellFormed` | A keep-apart needs two or more, a keep-together exactly two, and duplicates are refused | n/a: new type |
| `PairingRulesTests.conflicts` | FR-009: each of the three clashes is found and names both rules; a clean set has none | n/a |
| `PairingRulesTests.pruning` | FR-011: a removed player leaves every rule; a rule left under its minimum is dropped; a renamed player stays | n/a |
| `PairingRulesTests.encodesOnlyWhenSet` | A friendly with no rules encodes byte-for-byte as before; one with rules round-trips | n/a |
| `FriendlyPairingDrawTests.fourWithTwoApartAlternate` | US-1, SC-001: 20 rounds, never partners, the two line-ups alternate, same sides each time | **Yes**: partners one round in three |
| `FriendlyPairingDrawTests.fourWithTwoTogetherRepeat` | US-3 #3: every round is the same line-up, same sides | **Yes** |
| `FriendlyPairingDrawTests.eightWithFourApart` | SC-005: 30 rounds, no two of the four partners; no repeat partner while an allowed fresh one is on court | **Yes** |
| `FriendlyPairingDrawTests.sixWithTwoTogether` | US-3: together whenever both play; when one sits out, the other is drawn as usual | **Yes** |
| `FriendlyPairingDrawTests.benchStaysFair` | FR-006: sit-out counts never differ by more than one, with or without rules, for 5–12 players | n/a |
| `FriendlyPairingDrawTests.tieBreakLeansTowardsTheRules` | FR-006: five players with three apart break in exactly two rounds of every five, and those rounds carry `unkept` naming the pair | **Yes** |
| `FriendlyPairingDrawTests.fourAfterAMidSessionChange` | The clarified FR-008: three rules-free rounds, then a keep-apart; round 4 is the allowed line-up that came first, and they alternate | **Yes** |
| `FriendlyPairingDrawTests.singlesIgnoreRules` | Two or three players draw as without rules | n/a |
| `FriendlyPairingDrawTests.clashingRulesDrawAsNone` | D-8: a clashing set arriving anyway draws as no rules | n/a |
| `FriendlyPairingDrawTests.sixteenPlayersDrawPromptly` | SC-007: 30 rounds for 16 players, with a keep-apart group of eight, take under 0.5 s in total on CI | n/a |
| `PairingForecastTests.matchesTheDraw` | SC-008: for 4–12 players and a spread of rule sets, the forecast's count equals what drawing the rotation produces | n/a |
| `PairingForecastTests.rotationLength` | 5 → 5, 6 → 3, 7 → 7, 8 → 2; for four, the count of allowed line-ups; nil for singles | n/a |
| `PairingForecastTests.midSessionPlaysOnFromHere` | The editor's forecast starts from the rounds already drawn | n/a |
| `FriendlyPlacementTests.aRuleChangeRacingADrawKeepsTheRound` | D-5 and Principle II: a `configure` with new rules that sorts before a concurrent `nextRound` leaves the drawn round as placed | **Yes**: it re-partners |
| `FriendlyPlacementTests.aPlacementThatDoesNotFitIsDrawn` | A placement with a missing or doubled player falls back to the draw | n/a |
| `FriendlyPlacementTests.unkeptIsTheDrawTimeRules` | D-4: a rule added after a draw leaves that round's `unkept` as it was | n/a |
| `PresetTests.friendlyKeepsItsRulesThroughFreshIds` | FR-015, D-10: `makeSetup()` remaps the members to the fresh ids and prunes | **Yes**: rules are lost |
| `PresetTests.anOlderFriendlyPresetStillReads` | A preset saved before this feature decodes with no rules | n/a |
| `WireCompatibilityTests.aFriendlyWithRulesReadsAsOneWithoutOnAnOlderBuild` | Documents R-6, the reason for the gate: an older decoder drops the rules unread | n/a |
| `WireCompatibilityTests.aFriendlyDrawCarriesItsPlacement` | `nextRound` for a friendly round-trips `placed`; an older reader ignores it | n/a |

```bash
swift test --package-path Packages/RekkertKit --filter "FriendlyPairingSync|PairingRulesAdmission"
```

| Test *(new)* (RekkertSyncTests, on `CourtHarness`) | Proves | Fails today |
|---|---|---|
| `FriendlyPairingSyncTests.phoneAndWatchDrawTheSameWithRules` | SC-004: 12 rounds with a keep-apart group; the phone and the watch show identical line-ups and `unkept` | **Yes**: no rules to draw with |
| `FriendlyPairingSyncTests.aFullAccessGuestChangesTheRules` | US-4 #4, FR-013: a Full access guest's change reaches the host and the other guest; the round in play is unchanged; the next is drawn with it everywhere | **Yes** |
| `FriendlyPairingSyncTests.onlyScoreIsNotOffered` | `canEditPairingRules` is false for Only score and Read-only, and on a guest of an older host | **Yes** |
| `PairingRulesAdmissionTests.aProtocolTwoGuestIsToldToUpdate` | FR-014: joining a friendly with rules, a 1.2 guest (emulated) gets `needsUpdate` on the phone and the watch | **Yes**: it joins and diverges |
| `PairingRulesAdmissionTests.aOneOneGuestIsTurnedAway` | FR-014: a 1.1 guest (`actsAsOlderBuild`) gets `noRoom` and no link | **Yes** |
| `PairingRulesAdmissionTests.rulesAddedMidMatchTakeOlderGuestsOff` | FR-014: an older guest already on is turned away when the first rule is saved, and the host's count said so beforehand | **Yes** |
| `PairingRulesAdmissionTests.withoutRulesOlderGuestsStay` | Compatibility rule 1: an older guest on a rules-free friendly stays and draws the same rounds | n/a |

`CourtHarness` needs one test switch beside `actsAsOlderBuild`: a store that speaks protocol 2,
to stand in for a 1.2 phone.

Then the whole package:

```bash
swift test --package-path Packages/RekkertKit
```

Expected: everything passes. `FriendlyTests`, `SeededDrawTests`, `NeedsUpdateTests` and every
sharing suite pass unchanged. Principle II holds.

## 2. The gate (minutes; every push)

```bash
scripts/verify.sh
```

Expected: package tests, project generation, both app builds and every plist assertion pass.
No new Info.plist key, entitlement or background mode is involved.

## 3. Simulators: the screens

Launch a debug build on an iPhone simulator with the friendly demo:

```bash
xcrun simctl launch <udid> dev.natten.rekkert -rekkert-demo friendly -rekkert-demo-friendly-players 4
```

Then, by hand, against [contracts/screens.md](contracts/screens.md):

1. Start a new friendly with Ada, Bob, Cy and Dan.
   - The Pairing section offers both rule kinds.
   - With three names, it says rules apply from four.
2. Keep Ada and Bob apart and start.
   - Round 1 has them on opposite sides.
   - Win it: Up next is the other line-up.
   - Win round 2: Up next is round 1's line-up again, same colours.
3. Finish, and set up the same four again with Ada, Bob and Cy kept apart.
   - The footer says the rule can't hold in any round with these players, and Start stays
     enabled.
   - Start: every board shows the "couldn't keep them apart" line under it.
4. Set up five players with Ada, Bob and Cy apart.
   - The footer says "in 2 of every 5 rounds".
   - Play five rounds: exactly two show the notice, on the offer and under the board.
5. In play, open **Match options › Pairing rules…**, add Cy and Dan together, and save.
   - The round in play is unchanged.
   - Up next follows the new rule.
6. Make a clash (Ada and Bob both apart and together).
   - The footer names it, and Save and Start are disabled.
7. Save the friendly as a preset, start it from Home, and check the rules are there.

Check each screen at the largest Dynamic Type size and with VoiceOver on.

For two phones and a watch:

```bash
scripts/share.sh --keep
```

On the host, start a friendly with a keep-apart rule. On the guest, check that the same
line-ups and notices show. On the watch, check the same names, and no notice. Give the guest
Only score, and check **Pairing rules…** is gone from its menu.

## 4. Real devices: one friendly evening (before release)

Two iPhones with watches on this build, and a third iPhone on 1.2.

1. The host sets up five or more players with one keep-apart rule, and shares.
   - The 1.2 phone tries to join and is told Rekkert needs updating.
   - The current phone joins.
2. Play at least six rounds.
   - Both phones and both watches always show the same partnerships (SC-004).
   - Keep-apart players are never partners except in rounds that say so (SC-001, SC-006).
3. Start a fresh friendly without rules, and let the 1.2 phone join.
   - Add a rule from the guest phone with Full access.
   - The host warns first that one phone will be taken off.
   - After saving, the 1.2 phone is told it needs updating.
4. Time it: keeping two of four apart and starting, from the names entered, takes under 15 s
   (SC-002).

Record the outcome in this feature's `validation.md`, as earlier features did.
