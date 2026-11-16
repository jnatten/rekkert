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
swift test --package-path Packages/RekkertKit --filter "PairingRules|PairingText|FriendlyPairingDraw|PairingForecast|FriendlyPlacement|Preset|WireCompatibility"
```

| Test *(new)* | Task | Proves | Fails today |
|---|---|---|---|
| `PairingRulesTests.wellFormed` | T003 | A keep-apart needs two or more, a keep-together exactly two, and duplicates are refused | n/a: new type |
| `PairingRulesTests.conflicts` | T003 | FR-009: each of the three clashes is found and names both rules; overlapping keep-apart groups are not a clash | n/a |
| `PairingRulesTests.pruning` | T003 | FR-011: a removed player leaves every rule; a rule left under its minimum is dropped; a renamed player stays | n/a |
| `PairingRulesTests.breaks`, `.activeRules` | T003 | What a line-up breaks, both kinds; rules are inactive below four players or when they clash | n/a |
| `PairingRulesTests.rulesKeyIsStated` | T003 | D-1: this build always writes `pairingRules`, `[]` included; JSON without it decodes as "never stated"; `unkept` is written only when not empty | n/a |
| `PairingTextTests` | T011 | Every sentence in contracts/screens.md §1–§4b, singular and plural, both kinds | n/a: new type |
| `FriendlyPairingDrawTests.fourWithTwoApartAlternate` | T013 | US-1, SC-001: 20 rounds, never partners, the two line-ups alternate, same sides each time | **Yes**: partners one round in three |
| `FriendlyPairingDrawTests.aPairApartIsAlwaysKept` | T013 | 5–12 players over 30 rounds: a pair kept apart is never partners, and no round is flagged | **Yes** |
| `FriendlyPairingDrawTests.singlesIgnoreRules` | T013 | Two or three players draw as without rules | n/a |
| `FriendlyPairingDrawTests.clashingRulesDrawAsNone` | T013 | D-8: a clashing set arriving anyway draws as no rules | n/a |
| `FriendlyPairingDrawTests.eightWithFourApart` | T020 | SC-005: 30 rounds, no two of the four partners; no repeat partner while an allowed fresh one is on court | **Yes** |
| `FriendlyPairingDrawTests.benchStaysFair` | T020 | FR-006: sit-out counts never differ by more than one, with rules, for 5–12 players | n/a |
| `FriendlyPairingDrawTests.tieBreakLeansTowardsTheRules` | T020 | FR-006: five players with three apart break in exactly two rounds of every five, and those rounds carry `unkept` naming the pair | **Yes** |
| `FriendlyPairingDrawTests.fourWithThreeApartFlagsEveryRound` | T020 | A rule that can never hold flags every round, and the rounds still cycle as today | **Yes** |
| `FriendlyPairingDrawTests.sixteenPlayersDrawPromptly` | T020 | SC-007: 30 rounds for 16 players, with a keep-apart group of eight, take under 0.5 s in total on CI | n/a |
| `PairingForecastTests.rotationLength` | T021 | 5 → 5, 6 → 3, 7 → 7, 8 → 2, 12 → 3, 16 → 4; for four, the count of allowed line-ups; nil for singles | n/a |
| `PairingForecastTests.matchesTheDraw` | T021 | SC-008: for 4–12 players and a spread of rule sets, the forecast's count and pairs equal what drawing the rotation produces | n/a |
| `PairingForecastTests.midSessionPlaysOnFromHere` | T021 | The editor's forecast starts from the rounds already drawn | n/a |
| `FriendlyPairingDrawTests.fourWithTwoTogetherRepeat` | T027 | US-3 #3: every round is the same line-up, same sides | **Yes** |
| `FriendlyPairingDrawTests.sixWithTwoTogether` | T027 | US-3: together whenever both play; when one sits out, nothing is flagged; the bench stays fair | **Yes** |
| `FriendlyPairingDrawTests.togetherAndApartThatCannotBothHoldAreFlagged` | T027 | Rules that cannot both hold with four flag exactly one break a round | **Yes** |
| `FriendlyPlacementTests.aRuleChangeRacingADrawKeepsTheRound` | T030 | D-5 and Principle II: a `configure` with new rules that sorts before a concurrent `nextRound` leaves the drawn round as placed | **Yes**: it re-partners |
| `FriendlyPlacementTests.aPlacementThatDoesNotFitIsDrawn` | T030 | A placement with a missing or doubled player, three a side, or the wrong bench falls back to the draw | n/a |
| `FriendlyPlacementTests.unkeptIsTheDrawTimeRules` | T030 | D-4: a rule added after a draw leaves that round's `unkept` as it was | n/a |
| `FriendlyPlacementTests.aCorrectionAdoptsTheRules` | T030 | A stating correction replaces the rules, `[]` included; the id and rounds stay | **Yes**: rules dropped |
| `FriendlyPlacementTests.anOlderCorrectionLeavesTheRules` | T030 | D-1, D-6: a correction without the rules key (an older build's "swap sides") leaves the rules as they were | **Yes**: it would wipe them |
| `FriendlyPairingDrawTests.fourAfterAMidSessionChange` | T031 | The clarified FR-008: three rules-free rounds, then a keep-apart; round 4 is the allowed line-up that came first, and they alternate | **Yes** |
| `WireCompatibilityTests.aFriendlyWithRulesReadsAsOneWithoutOnAnOlderBuild` | T006 | Documents R-6, the reason for the gates: an older decoder drops the rules unread | n/a |
| `WireCompatibilityTests.aFriendlyDrawCarriesItsPlacement` | T032 | `nextRound` for a friendly round-trips `placed` | n/a |
| `PresetTests.friendlyKeepsItsRulesThroughFreshIds` | T038 | FR-015, D-10: `makeSetup()` remaps the members to the fresh ids | **Yes**: rules are lost |
| `PresetTests.aPresetMissingAPlayerPrunesTheRule` | T038 | FR-011 through a preset | **Yes** |
| `PresetTests.anOlderFriendlyPresetStillReads` | T038 | A preset saved before this feature decodes with no rules | n/a |
| `PresetTests.summaryCountsTheRules` | T038 | "· 2 rules" on the preset's line, nothing with none | **Yes** |

```bash
swift test --package-path Packages/RekkertKit --filter "FriendlyPairingSync|PairingRulesAdmission"
```

| Test *(new)* (RekkertSyncTests, on `CourtHarness`) | Task | Proves | Fails today |
|---|---|---|---|
| `PairingRulesAdmissionTests.aProtocolTwoGuestIsToldToUpdate` | T008 | FR-014: joining a friendly with rules, a 1.2 guest (emulated) is told to update | **Yes**: it joins and diverges |
| `PairingRulesAdmissionTests.aOneOneGuestIsTurnedAway` | T008 | FR-014: a 1.1 guest (`actsAsOlderBuild`) gets `noRoom` and no link | **Yes** |
| `PairingRulesAdmissionTests.aCurrentGuestJoins` | T008 | A guest on this build joins a friendly with rules and draws what the host draws | n/a |
| `PairingRulesAdmissionTests.rulesArrivingTakeOlderGuestsOff` | T008 | FR-014: the host's next friendly, with rules, turns away an older guest waiting on | **Yes** |
| `PairingRulesAdmissionTests.withoutRulesOlderGuestsStay` | T008 | Compatibility rule 1: an older guest on a rules-free friendly stays and draws the same rounds | n/a |
| `PairingRulesAdmissionTests.anOlderWatchIsHeldBackAndThePhoneSaysSo` | T008 | FR-014, C1: a phone's own 1.2 watch never holds a friendly with rules, and the phone raises `pairNeedsUpdateForRules` | **Yes**: the watch draws without rules |
| `PairingRulesAdmissionTests.anOlderWatchFollowsAFriendlyWithoutRules` | T008 | With no rules, an older watch follows as today | n/a |
| `PairingRulesAdmissionTests.theWatchCatchesUpOnceUpdated` | T008 | Once the watch speaks 3, it receives every round and the rules | **Yes** |
| `FriendlyPairingSyncTests.phoneAndWatchDrawTheSameWithRules` | T014 | SC-004: 12 rounds; the phone and the watch show identical line-ups and `unkept` | **Yes**: no rules to draw with |
| `FriendlyPairingSyncTests.everyDeviceRecordsTheSameBrokenRounds` | T022 | SC-004, SC-006: host phone, watch and a guest hold identical `unkept`, and the guest's next-round offer matches the host's | **Yes** |
| `FriendlyPairingSyncTests.aFullAccessGuestChangesTheRules` | T033 | US-4 #4, FR-013: a Full access guest's change reaches the host and the watch; the round in play is unchanged; the next is drawn with it everywhere | **Yes** |
| `FriendlyPairingSyncTests.aRuleChangeIsNeverUndone` | T033 | FR-013: Undo on the host or the guest never takes a rule change back | **Yes**: no rules to keep |
| `FriendlyPairingSyncTests.onlyScoreIsNotOffered` | T033 | `canEditPairingRules` is false for Only score, Read-only, a guest of an older host, and singles | **Yes** |
| `PairingRulesAdmissionTests.rulesAddedMidMatchTakeOlderGuestsOff` | T033 | FR-014: an older guest already on is turned away when the first rule is saved, and the host's count said so beforehand | **Yes** |

`CourtHarness` needs one test switch beside `actsAsOlderBuild` (T007): a store, phone or watch,
that speaks protocol 2, to stand in for 1.2.

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
