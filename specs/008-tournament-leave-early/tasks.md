---

description: "Task list for Leaving an Americano or Mexicano Early"
---

# Tasks: Leaving an Americano or Mexicano Early

**Input**: Design documents from `specs/008-tournament-leave-early/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required. Principle III asks for engine tests first. In every phase the test tasks
come first, and **must fail for the stated reason before that phase's implementation**. The one
exception is T003, the no-absence fingerprint. It is written green on today's code and must stay
green through every later task (D-13).

**Organization**: Tasks are grouped by user story in the spec's priority order: US1 and US2 are
P1, US3 and US4 are P2, US5 is P3. Phase 2 holds what every departure needs to be safe, so the
MVP can ship on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: The user story the task belongs to (US1–US5, as in spec.md)
- Paths are from the repository root. Some are shortened:

  | Short | Full path |
  |---|---|
  | `RekkertCore/` | `Packages/RekkertKit/Sources/RekkertCore/` |
  | `RekkertSync/` | `Packages/RekkertKit/Sources/RekkertSync/` |
  | `CoreTests/` | `Packages/RekkertKit/Tests/RekkertCoreTests/` |
  | `SyncTests/` | `Packages/RekkertKit/Tests/RekkertSyncTests/` |

- `R-n` and `D-n` are the findings and decisions in research.md. Find code by the function
  named, not by line number.
- SwiftPM picks up new files in existing targets, and Tuist globs `App/Sources/**`, so new files
  need no package or project changes.
- **All UI text comes from `AwayText`**, which builds every sentence in
  [contracts/screens.md](contracts/screens.md). Views never compose away wording themselves.
- **Fingerprint check.** Run `swift test --package-path Packages/RekkertKit --filter
  TournamentNoAbsenceFingerprint` after every task that touches `RekkertCore/Tournament/`. If it
  goes red, that task changed a tournament nobody left: fix the task, never the fingerprint.
- **Sheets go on the List, never a Section.** A `.sheet` or `.confirmationDialog` attached to a
  `Section` is copied onto every row, so one tap opens several and throws the screen away (bug
  `pairing-rule-sheet-closes`). Every presentation added here attaches to the `List`, the `Form`
  or the view around them.

### Glossary

| Spec (user-facing) | Code and research |
|---|---|
| has left, gone, away | an open `TournamentAbsence` (`until == nil`) |
| came back, brought back | the absence closed (`until` set) |
| the players still there | `presentPlayers` / `present(inRound:)` |
| organiser | any phone with `canMarkAway`: the host, or a Full-access guest of a host at protocol 4 |
| the round in play | the tournament's last round, `L` in D-3 |

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A known-good baseline, and the pin that keeps it.

- [X] T001 Run `scripts/verify.sh` at `f9297b3` and note the package test counts (608 / 942 / 21 at planning time). This is the baseline the gate is compared against.
- [X] T002 [P] Create `CoreTests/TournamentTestSupport.swift` with internal helpers shared by every new core suite:
  - `makeTournament(format: TournamentFormat, players: Int, courts: Int, seed: Int = 1) -> Tournament`: players named "P0"… with ids from `uuid(n)`, and the tournament id from the seed (as `PartnerTurnTests` builds them);
  - `drawing(_:rounds:score:)`: appends rounds with `TournamentEngine.appendingRound`, scoring every court with a deterministic `score(round, court) -> BySide<Int>` so Mexicano's table is stable. The default is `a = target`, `b = (round * 3 + court) % target`;
  - `rendered(_ round: Round) -> String`: "P0+P1 v P2+P3 | … (P8 out)", courts in order, names sorted within a side;
  - `fingerprint(_ lines: [String]) -> UInt64`: FNV-1a 64 over the lines joined by "\n".
  Make the private helpers in `TournamentTests.swift` and `PartnerTurnTests.swift` use these only where that is a straight swap. Leave their assertions alone.
- [X] T003 Write `CoreTests/TournamentNoAbsenceFingerprintTests.swift` (`@Suite("A tournament nobody leaves draws as it always has")`), **green on today's code** (D-13):
  - `@Test(arguments:)` over `[.americano, .mexicano]` × players 5…16 × courts 1…4.
  - Draw 20 rounds. After round 3, redraw round 3 with the first player of its playing set picked to sit out, using `TournamentEngine.sitOuts(for:picked:redrawing: true)`, as `MatchStore.redrawRound` does.
  - Pin `fingerprint(rounds.map(rendered))` per combination in a `static let pinned: [String: UInt64]` keyed "americano-9-2". Generate the table once on today's code, and head the file with "Pinned before players could leave (spec 008, D-13). Fix the draw, never these values."
  - Commit this task on its own, before T010.

**Checkpoint**: The baseline is green, and the fingerprint is committed.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Absences exist on the wire and in state. No draw can be re-partnered by one. Older
devices are kept off once one exists. Every story needs all of this before it can ship.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests for the foundation ⚠️ (write first; they must fail)

- [X] T004 [P] Add `startTournament(format:players:courts:absences:)` and `playTournamentRound(on:)` to `SyncTests/CourtHarness.swift`, beside `startFriendly`:
  - **Start.** `host.phone.store.configure(.tournament(Tournament(format:, players:, config: TournamentConfig(courtCount:), absences:)))`, then `nextRound()`.
  - **One round.** Score each court of the last round to the target on `.a` with `setScore`, then `nextRound()` on the given device.
  - `tournament(on:)` returns the device's `Tournament`.

  Until T008 adds `absences`, keep that parameter out of the call.
- [X] T005 [P] Extend `CoreTests/WireCompatibilityTests.swift`. Each fails today:
  - `aTournamentNobodyLeftHasNoAbsencesKey`: encoding `makeTournament` gives JSON with no `"absences"` key.
  - `absencesRoundTrip`: a tournament with one closed and one open absence survives encode and decode.
  - `setAwayRoundTrips`: `MatchEvent` with `.setAway(player:isAway:after:placed:)` survives encode and decode, with and without `placed`.
  - `anOlderDecoderReadsSetAwayAsUnrecognised`: the event's JSON with its kind renamed to one this build doesn't know decodes as `.unrecognised` and re-encodes unchanged. Use the pattern the suite already uses for unknown kinds.
  - `americanoDrawsCarryPlacement`: `TournamentEngine.placement(of:)` is non-nil for an Americano, and its round equals `appendingRound`'s.
- [X] T006 [P] Write `CoreTests/AbsencePlacementTests.swift` (`@Suite("A carried draw stands")`) for D-5. Each fails today:
  - `americanoAdoptsAFittingPlacement`: an Americano `nextRound` folded with a `placed` differing from the recomputed round (two players swapped across a court) takes `placed`.
  - `aPlacementMayIncludeSomeoneAway`: a tournament whose `absences` marks P3 away from the next round adopts a placement that has P3 on court 1, and the round has P3 on court 1.
  - `awayPlayersOnAPlacedBenchGetNoCredit`: the same with P3 on the placement's bench. The round's `sitOuts` has no P3, and `Leaderboard` gives P3 no compensation for it.
  - `aPlacementMissingSomeonePresentIsRefused`: a placement that leaves out a present player is not adopted, and the round is drawn here.
- [X] T007 [P] Write `SyncTests/AbsenceAdmissionTests.swift` (`@Suite("Older builds and a tournament someone left", .serialized) @MainActor`), on T004's helpers and the protocol switch `PairingRulesAdmissionTests` uses to make a device speak an older protocol. Each fails today:
  - `aGuestOnProtocol3IsTurnedAwayWhenTheFirstAbsenceFolds`: the guest gets `needsUpdate` and its link is refused. The host records `.refused(.needsUpdate)`.
  - `aGuestOnProtocol3IsTurnedAwayAtHelloAfterward`.
  - `aWatchOnProtocol3IsHeldBack`: the host's watch receives nothing of the session, and `pairNeedsUpdate` is true.
  - `aFriendlyWithRulesStillAdmitsProtocol3`: 006's gate is unchanged.
  - `aGuestOffersTheActionOnlyToAHostAt4`: `canMarkAway` is false on a Full-access guest whose host speaks 3.
  - `theNeedOutlivesTheReturn`: with every absence closed, a guest at 3 is still turned away.

### Implementation for the foundation

- [X] T008 Create `RekkertCore/Tournament/TournamentAbsence.swift` with `TournamentAbsence`, `AwayStretch` and `AwayPreview`, as in data-model.md:
  - `TournamentAbsence { player: PlayerID; from: Int; until: Int? }`, Codable, Sendable, Hashable. "When set, `until > from`."
  - `AwayStretch { firstMissed: Int; backFor: Int? }`, 1-based.
  - `AwayPreview` with every field in the data model.
- [X] T009 Add absences and presence to `RekkertCore/Tournament/Tournament.swift` (D-1):
  - **The field.** `public var absences: [TournamentAbsence]`, defaulting to `[]` in `init`. In `CodingKeys` and `init(from:)`: "Decoded with `decodeIfPresent` (default `[]`), encoded only when not empty". Write a hand-written `encode(to:)` that skips the key when empty, like `Round.encode`.
  - **Presence.** `isPresent(_:inRound:)`, `present(inRound:)` (roster order), `presentPlayers` (`present(inRound: rounds.count)`), `isAway(_:)`, `hasAbsences`, `isShortOfPlayers`, and `awayPlayersOnCourt(inRound:)`, all as in data-model.md.
  - **Counts.** `playableCourts` and `benchSize` come from `presentPlayers.count`.
  - Keep the invariants in mind for T018. "A player has at most one open absence (`until == nil`)." "Their absences don't overlap, and are kept in the order they were folded."
  - T005's two absence tests pass, and the fingerprint stays green.
- [X] T010 Add `case setAway(player: PlayerID, isAway: Bool, after: Int, placed: RoundPlacement? = nil)` to `EventKind` in `RekkertCore/Sync/MatchEvent.swift` (D-2):
  - add it to `isUndoable`'s `false` list, and to `payloadDate`'s nil list;
  - in `SessionReducer.swift`, add a `case .setAway: break` placeholder. US1 fills it in.
  - T005's event tests pass.
- [X] T011 Make carried draws stand (D-5):
  - **Americano placement.** In `RekkertCore/Tournament/RoundScheduler.swift`, `TournamentEngine.placement` returns a placement for `.americano` too, drawn the same way as for Mexicano.
  - **Adoption.** `appendingRound` adopts `placed?.round(for:)` for Americano before falling back to `AmericanoScheduler`.
  - **The fit.** In `RekkertCore/Tournament/RoundPlacement.swift`, relax `round(for:)` to the rule in contracts/engine-api.md, and drop away players from the returned round's `sitOuts`.
  - **Done when** T006 and T005's placement test pass, and the fingerprint, `SeededDrawTests`, `PartnerTurnTests` and `MixedBenchTests` stay green.
- [X] T012 Raise the protocol and say what a state needs (D-9):
  - in `RekkertCore/Sync/Wire.swift`, `sharingProtocol = 4`, with the doc comment "4 from spec 008 (leaving early)";
  - in `RekkertCore/Sync/SessionModel.swift`, `SessionState.sharingProtocolNeeded`: 3 for `.friendly` with non-empty `activeRules`, 4 for `.tournament` with `hasAbsences`, 1 otherwise.
- [X] T013 Generalise the older-build gate in `RekkertSync/MatchStore.swift` (D-9, D-10):
  - **The question.** Replace `hasActiveRules(_:)` and `pairingRulesProtocol` comparisons with `state?.sharingProtocolNeeded`. Turning away at hello, turning away when the need rises (not only when rules appear), the refusal kinds and `updatePairHold` all compare a peer's protocol against it.
  - **Renames.** `pairNeedsUpdateForRules` → `pairNeedsUpdate`, and `olderGuestsTurnedAwayByRules` → `olderPeersTurnedAway(ifNeeding:)`. Keep `refusedForRules` working; rename it `refusedForNeed`.
  - **The action.** Add `canMarkAway` (contracts/engine-api.md). Add `setAway(_ player: PlayerID, isAway: Bool)`, guarded by it, recording `.setAway(player:isAway:after: rounds.count - 1, placed: nil)` for now. US2 adds the placement.
  - **Done when** T007 passes and `PairingRulesAdmissionTests` stays green.
- [X] T014 [P] Follow the renames in `App/Sources/Views/FriendlyMatchView.swift` (`pairNeedsUpdate`), `App/Sources/Views/PairingRulesEditor.swift` (`olderPeersTurnedAway(ifNeeding: 3)`) and `SyncTests/PairingRulesAdmissionTests.swift`. Change no behaviour.

**Checkpoint**: `swift test` is green, and so is the fingerprint. A tournament can hold absences,
nobody older can follow one, and no carried draw can be re-partnered. Nothing yet creates an
absence.

---

## Phase 3: User Story 1 - Someone leaves between rounds (Priority: P1) 🎯 MVP

**Goal**: Between rounds, the organiser marks a player as gone. Every later round leaves them out,
with courts and bench sized for who is left, and the table credits them nothing more.

**Independent Test**: Start a nine-player Americano on two courts and play two rounds. Mark one
player as left, then draw five more rounds. That player is in none of them. Nobody sits out,
since eight fill two courts. Their points are exactly what they had after round 2.

### Tests for User Story 1 ⚠️ (write first; they must fail)

- [ ] T015 [P] [US1] Write `CoreTests/TournamentAbsenceTests.swift` (`@Suite("Marking a player as gone")`), for D-3 case 1, calling `TournamentEngine.settingAway(_:isAway:after:placed:in:)`:
  - `beforeTheFirstRound`: `from == 0`.
  - `afterAFinishedRound`: `from == L.index + 1`, and `L` is unchanged.
  - `afterACancelledRound`: the same.
  - `markingTwiceKeepsTheFirstStart`.
  - `aLadderAFinishedTournamentAndAStrangerAreUntouched`: the result equals the input.
- [ ] T016 [P] [US1] Write `CoreTests/AbsenceDrawTests.swift` (`@Suite("The draw leaves out whoever has left")`):
  - `nobodyAwayIsDrawn` (SC-002, `@Test(arguments:)` over both formats × players 5…16 × courts 1…4): play 3 rounds, mark P1 away, and draw 10 more. P1 is in no court and no `sitOuts` of any of them. Each round has `min(courts, present / 4)` courts and the rest benched.
  - `mexicanoRanksOnlyThosePresent`: after marking the table leader away, court 1 of the next round is the top four of those present.
  - `americanoRepeatsNoMoreThanAFreshStart` (SC-005, players 6…13, 2 courts): P0 leaves after round 2. Over the rounds to the end of the rotation of the rest, the most any pair partners is no more than an Americano started with the remaining count reaches over as many rounds.
  - `pickingTheBenchIgnoresWhoIsAway`: `TournamentEngine.sitOuts(for:picked: [awayPlayer], redrawing:)` is refused (`chosen` throws).
- [ ] T017 [P] [US1] Extend `CoreTests/TournamentTests.swift`:
  - `nothingIsEarnedWhileAway`: P2 leaves after round 2 of 6. P2's `pointsFor`, `compensation`, `roundsPlayed` and `sitOuts` equal their values after round 2 (SC-003).
  - `theOrderIsUnchanged`: standings sort exactly as `Leaderboard.isRankedAbove` says, the player who left included.
  - `standingsCarryTheAwayStretch`: P2's `away == [AwayStretch(firstMissed: 3, backFor: nil)]`, and everyone else's is empty.
- [ ] T018 [P] [US1] Write `SyncTests/TournamentAbsenceSyncTests.swift` (`@Suite("Leaving early across devices", .serialized) @MainActor`) with `betweenRoundsEveryDeviceAgrees` (SC-004). Use `CourtHarness` with the host's watch and one Full-access guest, and `startTournament(.americano, players: 9, courts: 2)`. Play two rounds, call `setAway(P4, isAway: true)` on the guest, and play four more rounds, alternating the drawing device. Within 5 s of each draw, all three hold equal `rounds`, `absences` and `Leaderboard.standings`.

### Implementation for User Story 1

- [ ] T019 [US1] Make the schedulers read presence in `RekkertCore/Tournament/RoundScheduler.swift` (D-1):
  - `AmericanoScheduler.nextRound` and `MexicanoScheduler.nextRound` pass `tournament.presentPlayers` to `split`, and their "not enough players" error counts it.
  - `TournamentEngine.bench` passes `base.presentPlayers` to `plannedTurn` and `mixedBench`.
  - `RoundScheduler.chosen` validates against `presentPlayers`.
  - Leave `LadderScheduler` alone. Ladders are out of scope, and can't hold absences (T020).
  - **Done when** T016's draw tests pass and the fingerprint stays green.
- [ ] T020 [US1] Create `RekkertCore/Tournament/TournamentEngine+Away.swift`:
  - **`settingAway`, case 1 only** (D-3): no round, or `L` cancelled or done. The rest is a no-op, which US2 fills in.
  - **The guards.** Ladder, finished tournament or a player not on the roster: return the input.
  - **Marking someone already away** keeps their `from`.
  - **`awayPreview`**: for now it fills `player`, `isAway`, `fromRound`, the courts and bench before and after, and `isShortOfPlayers`.
  - **Done when** T015 passes.
- [ ] T021 [US1] Fold `setAway` in `RekkertCore/Sync/SessionReducer.swift`: `.tournament` → `TournamentEngine.settingAway(player, isAway:, after:, placed:, in:)`. Anything else is a no-op. The `configure` correction branch keeps the absences it already holds; it adopts only `name`, `players` and `config`, as today.
- [ ] T022 [US1] Fill `Standing.away` in `RekkertCore/Tournament/Leaderboard.swift` from `absences` (1-based, in order). Change neither the sort nor any total. **Done when** T017 passes.
- [ ] T023 [P] [US1] Create `RekkertCore/Presentation/AwayText.swift` with the US1 sentences from contracts/screens.md §1–§2:
  - the footer "Eve has left. The draw leaves her out." Write it with the name, not a pronoun: "The draw leaves Eve out." For several players: "Ada and Eve have left. The draw leaves them out.";
  - the confirmation title "Has Eve left?" and button "Eve has left";
  - the row subtitle "Left after round 4";
  - the older-phones line "1 phone on an older Rekkert will be taken off this tournament. It can join again once updated." and its plural.

  Write `CoreTests/AwayTextTests.swift` alongside it for these, singular and plural.
- [ ] T024 [US1] Create `App/Sources/Views/WhosHereView.swift` (screens §2):
  - **The sheet.** Titled "Who's here?", with Done. One row per roster player, from `TournamentView.tournament(model)`, with the subtitle from `AwayText`.
  - **In US1**: a present player's row is tappable only when `tournament.currentRound` is nil, done or cancelled. Otherwise the footer says "Players can leave once this round is over." Away rows aren't tappable until US5.
  - **The confirmation.** Tapping opens a `confirmationDialog` **attached to the `List`**, with the title, the destructive button and, on the host, the older-phones line when `olderPeersTurnedAway(ifNeeding: 4) > 0`. Confirming calls `model.store.setAway(id, isAway: true)`.
- [ ] T025 [US1] Wire `App/Sources/Views/TournamentView.swift` (screens §1):
  - **The button.** In `managementSection`, for `model.store.canMarkAway && !tournament.isLadder`, add **Who's here…** (`person.crop.circle.badge.xmark`), presenting `WhosHereView` from the `List` (not a `Section`).
  - **The footer.** Add the "has left" footer when anyone is away.
  - **The finish offer.** Add the sheet's presented flag to `showingFinishOffer`'s hold-back condition.
  - **The watch.** Show the watch-needs-updating notice when `model.store.pairNeedsUpdate`, with the same wording as `FriendlyMatchView`, minus "pairing rules".
- [ ] T026 [US1] Run `SyncTests/TournamentAbsenceSyncTests.swift` (T018) and the whole `swift test --package-path Packages/RekkertKit`. Fix the fold or the gate, never the test.

**Checkpoint**: US1 works end to end. Marking someone between rounds takes them out of every later
draw on every device, and older devices are kept off.

---

## Phase 4: User Story 2 - Someone leaves while their court is playing (Priority: P1)

**Goal**: A player can be marked as gone at any time. An unstarted round is drawn again without
them. A court with points stops and counts as it stands, and the round closes when the others
finish. No race re-partners a round.

**Independent Test**: In a two-court Americano, score court 1 to 9–7, mark one of its players as
left, and finish court 2. The round closes, court 1 counts 9–7 for all four, and the next round
leaves the player out.

### Tests for User Story 2 ⚠️ (write first; they must fail)

- [ ] T027 [P] [US2] Extend `CoreTests/TournamentAbsenceTests.swift` for D-3 cases 2 and 3:
  - `anUnstartedRoundIsDrawnAgainWithoutThem`: `from == L.index`, `L` no longer has the player, and the result equals `redrawingLastRound` with `L.sitOuts` less the player as picks, cut to the new bench size.
  - `theCarriedRedrawIsTakenWhenItIsForThisRound`: `after == L.index` with a fitting `placed` adopts it.
  - `aStaleCarriedRedrawIsIgnored`: `after == L.index - 1` redraws here.
  - `aCourtWithPointsStopsWhereItStands`: with `from == L.index + 1`, the player's court has `isConfirmed`, and a `.point` folded after it changes nothing.
  - `theRoundClosesWhenTheOthersFinish`: `isDone(L)` once the other court reaches the target, and `canDrawNextRound` is true.
  - `aZeroZeroCourtStopsToo`: another court has points and the player's has none. The player's court is confirmed at 0–0.
  - `leavingFromTheBenchKeepsItsCredit`: the player was in `L.sitOuts`, `L` is unchanged, and their compensation for `L` stands.
  - `markingAgainSettlesARacedRound`: P3 is away from `L.index` but on a court of `L` (built through T011's relaxed placement). Marking P3 again redraws `L` if nothing is played, and otherwise confirms P3's court.
- [ ] T028 [P] [US2] Extend `SyncTests/TournamentAbsenceSyncTests.swift`:
  - `midRoundEveryDeviceAgrees` (SC-004, SC-006): score court 0 to 9–7, mark a player on it away on the guest, and finish court 1 on the watch. All three agree, court 0 reads 9–7 and confirmed everywhere, and no other court's score changes.
  - `aDepartureThatRacedADrawRepartnersNothing` (SC-006, D-5): partition the guest from the host. The host draws the next round and scores a point on it, while the guest marks a player in that round as left. Rejoin. Every device holds the host's line-up for that round, the point stands, and `awayPlayersOnCourt(inRound:)` names the player.

### Implementation for User Story 2

- [ ] T029 [US2] Complete `settingAway` in `RekkertCore/Tournament/TournamentEngine+Away.swift` with D-3 cases 2 and 3, the carried-placement rule, and "marking a player who is already away re-applies cases 2 and 3 to `L` and leaves `from` alone". Fill `awayPreview`'s `redrawsRoundInPlay` and `stoppingCourt`. **Done when** T027 passes.
- [ ] T030 [US2] In `RekkertSync/MatchStore.swift`, `setAway` computes the redraw it will record when `tournament.canRedrawCurrentRound` and the player is in the round in play. It applies `settingAway` to its own state, then records `placed: RoundPlacement(result.rounds.last!)` with `after: rounds.count - 1`.
- [ ] T031 [P] [US2] Add the US2 sentences to `RekkertCore/Presentation/AwayText.swift`, with tests in `CoreTests/AwayTextTests.swift`:
  - "Round 6 hasn't started, so it's drawn again without Eve."
  - "Court 2 stops at 9–7 and counts as it stands." (including 0–0)
  - the race subtitle "Still drawn on court 2 in round 6."
  - the race choices "Take Eve off round 6" and "Eve is back".
- [ ] T032 [US2] Update `App/Sources/Views/WhosHereView.swift`:
  - **Any time.** Every present row is tappable while the tournament isn't finished, and US1's "once this round is over" footer goes.
  - **The confirmation.** Show `redrawsRoundInPlay` and `stoppingCourt`.
  - **The race row.** For players in `awayPlayersOnCourt(inRound: latestRoundIndex)`, show the warning glyph and subtitle, and a dialog with **Take … off round N**, which calls `setAway(id, isAway: true)` again. **… is back** arrives with US5.
- [ ] T033 [US2] Run `SyncTests/TournamentAbsenceSyncTests.swift` (T028) and the whole `swift test --package-path Packages/RekkertKit`.

**Checkpoint**: US1 and US2 together cover every moment someone can leave, with Principle II
intact.

---

## Phase 5: User Story 3 - Fewer players change the shape of the evening (Priority: P2)

**Goal**: The confirmation says what the evening becomes in numbers. A full rotation counts only
those left. Below four, the courts screen says so and offers Finish.

**Independent Test**: In an eight-player, two-court tournament, mark one player as left. Before
confirming, the phone says the next rounds are played on one court with three sitting out. After
confirming, the next round is drawn that way.

### Tests for User Story 3 ⚠️ (write first; they must fail)

- [ ] T034 [P] [US3] Extend `CoreTests/TournamentLengthTests.swift`:
  - `aFullRotationCountsOnlyThosePresent`: nine players, full rotation, and P0 leaves after round 2. `plan.partnershipsLeft` equals the pairs among the other eight not yet partnered, and `isReached` comes when they are all done.
  - `setRoundsAreUnchanged`: a `.rounds(7)` plan's `finalRound` is the same with and without a departure.
  - `belowFourNoRoundIsDrawn`: five players, two leave. `isShortOfPlayers` is true, `appendingRound` throws `notEnoughPlayers`, and a folded `nextRound` changes nothing.
- [ ] T035 [P] [US3] Extend `CoreTests/AwayTextTests.swift` with the shape lines:
  - "From round 7: 1 court, 3 sit out each round." and its singular forms, written only when the courts or the bench change;
  - "Nobody sits out from round 7.";
  - "Fewer than four are left, so no more rounds can be drawn.";
  - the courts-screen line "Fewer than four players are here, so no more rounds can be drawn."

### Implementation for User Story 3

- [ ] T036 [US3] In `RekkertCore/Tournament/Tournament+Length.swift`, build the full rotation's unpaired set from `presentPlayers`. Pairs partnered while someone was present still count as partnered. **Done when** T034 passes, and the existing `TournamentLengthTests` and the fingerprint stay green.
- [ ] T037 [US3] Add the shape lines to `RekkertCore/Presentation/AwayText.swift` from `AwayPreview`'s before and after counts. **Done when** T035 passes.
- [ ] T038 [US3] Show the shape:
  - in `App/Sources/Views/WhosHereView.swift`, add the shape line and the "fewer than four" line to the confirmation;
  - in `App/Sources/Views/TournamentView.swift`, when `tournament.isShortOfPlayers`, replace the Draw button with the courts-screen line and **Finish tournament**, which uses the existing finish path.

**Checkpoint**: The organiser sees what leaving costs before confirming, and is never left facing a
Draw button that can't draw.

---

## Phase 6: User Story 4 - The table and History say who left (Priority: P2)

**Goal**: The standings, the finish screen, History and the TV board show who left and when. The
ranking itself is unchanged, and the Players page counts only rounds played.

**Independent Test**: Finish a tournament in which one player left after round 4. The final table
and the History entry both show that player, "Left after round 4", and their points. Their
per-round average on the Players page counts only the rounds they played.

### Tests for User Story 4 ⚠️ (write first; they must fail)

- [ ] T039 [P] [US4] Extend `CoreTests/SessionResultTests.swift` with `placingsSayWhoLeft`: an Americano where P2 left after round 4 has `Placing.detail == "Left after round 4"` for P2, and nil for everyone else. The order is that of `Leaderboard`.
- [ ] T040 [P] [US4] Extend `CoreTests/TVBoardTests.swift` with `liveStandingsMarkWhoIsAway`: P2's live name reads "P2 · left", and `detail` is still the difference.
- [ ] T041 [P] [US4] Add `aPlayerWhoLeftAveragesOnlyRoundsPlayed` to `CoreTests/PlayerStatsTests.swift`, using `PlayerStatsFixtures.swift` (FR-015). With P2 away for rounds 5–8 of 8, P2's `rounds` is 4 and the average is over those 4. This passes today (R-2): it pins the behaviour, and needs no implementation.

### Implementation for User Story 4

- [ ] T042 [US4] In `RekkertCore/Presentation/SessionResult.swift`, set `Placing.detail` for Americano and Mexicano from `AwayText` for anyone with `away`. In `RekkertCore/Presentation/TVBoard.swift`, append " · left" to the live name of anyone `isAway`. **Done when** T039 and T040 pass.
- [ ] T043 [P] [US4] In `App/Sources/Views/StandingsView.swift`, add the away line under `StandingRow`'s subtitle (screens §3), from `AwayText`.
- [ ] T044 [P] [US4] In `App/Sources/Views/HistoryDetailView.swift`, add "Away: Eve" under the "Sitting out: …" caption for any round someone missed (screens §4), using `present(inRound:)` on the archived tournament.

**Checkpoint**: Everywhere a table is shown on the phone, it says who left, and nobody's place
changes for it.

---

## Phase 7: User Story 5 - Coming back (Priority: P3)

**Goal**: The organiser brings a player back at any time. They are drawn from the next round, are
owed neither a rest nor a game, and a mark undone before another round leaves no trace.

**Independent Test**: In a nine-player Americano, mark a player as left after round 2. Play rounds
3 and 4 without them, bring them back, and draw round 5. They are in round 5, they earned nothing
for rounds 3 and 4, and no round already played changes.

### Tests for User Story 5 ⚠️ (write first; they must fail)

- [ ] T045 [P] [US5] Extend `CoreTests/TournamentAbsenceTests.swift` for D-4:
  - `backBetweenRounds`: `until == L.index + 1`.
  - `backBeforeTheRoundStarts`: `until == L.index`, and `L` is redrawn with them.
  - `aMistakeLeavesNoTrace`: mark and bring back with no round in between. `absences` is empty, and the rounds equal those of a tournament never marked: "An absence closed with `until == from` is removed rather than stored (D-4)".
  - `bringingBackSomeoneHereChangesNothing`.
- [ ] T046 [P] [US5] Write `CoreTests/ReturnBenchTests.swift` (`@Suite("A returner is owed neither a rest nor a game")`) for D-6, over both formats with 9, 10 and 13 players on 2 courts:
  - `theyPlayTheirFirstRoundBack`: P1 is away for rounds 3–5 and back for 6. P1 isn't in round 6's `sitOuts`.
  - `theyRejoinTheRotation`: over the next `ceil(present / bench)` rounds, P1's sit-outs from round 6 on end within one of the fewest among the rest.
  - `nobodyLeftMeansTodaysHistory`: `PairingHistory` of a tournament without absences equals today's (field by field).
- [ ] T047 [P] [US5] Extend `CoreTests/AwayTextTests.swift`:
  - "Away rounds 3–4" and "Away rounds 3–4 · left after round 7";
  - "Is Eve back?" / "Eve is back";
  - "Round 6 hasn't started, so it's drawn again with Eve." / "Eve plays again from round 7."

### Implementation for User Story 5

- [ ] T048 [US5] Add the return to `settingAway` in `RekkertCore/Tournament/TournamentEngine+Away.swift` (D-4): close the open absence at `L.index` with a redraw, or at `L.index + 1`, and remove it when `until == from`. Extend `awayPreview` for `isAway: false`, and `MatchStore.setAway`'s redraw placement in `RekkertSync/MatchStore.swift` to the return redraw. **Done when** T045 passes.
- [ ] T049 [US5] Apply the returner's bench bookkeeping in `RekkertCore/Tournament/PairingHistory.swift` (D-6): before recording round `r`, for each absence with `until == r`, set the returner's `sitOuts` to `max(own, min over the others present for r)` and their `lastSatOut` to `recorded - 1`. **Done when** T046 passes, and the fingerprint, `PartnerTurnTests` and `MixedBenchTests` stay green.
- [ ] T050 [US5] Add the US5 sentences to `RekkertCore/Presentation/AwayText.swift` (T047). In `App/Sources/Views/WhosHereView.swift`, make away rows tappable with the "Is … back?" dialog, and add **… is back** to the race dialog.

**Checkpoint**: All five stories work on their own and together.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Help, docs, the gate, cross-build, and the screens tapped by hand.

- [ ] T051 [P] Add the help item to `RekkertCore/Help/HelpCatalog.swift`, page `phone.rounds`: **Who's here…** with symbol `person.crop.circle.badge.xmark` and the text in screens §6. Add the line to Americano and Mexicano in `RekkertCore/Help/ModeHelp.swift`. Run `HelpTests`.
- [ ] T052 [P] Update `README.md`:
  - **Americano / Mexicano**: a paragraph on leaving between rounds and mid-round, the table's label, coming back, and older builds being kept off;
  - **Who may do what**: "who has left" among the round-running actions Only score phones don't get.

  Run `HelpTests`, which checks README sections have help pages.
- [ ] T053 Run `scripts/verify.sh`, then `scripts/cross-build.sh ca67ad0 b03026e` and `scripts/cross-build.sh --players 13 ca67ad0` (quickstart level 2). If cross-build differs, T011 changed something an older build sees: fix T011.
- [ ] T054 Run quickstart.md level 3 on an iPhone simulator, **tapping** each step rather than using launch flags. Check that **Who's here…**, its rows and every confirmation open and stay open until dismissed, and do it at the largest Dynamic Type size and with VoiceOver on. Fix what is found.
- [ ] T055 Run quickstart.md level 4 on real devices before release, and record the outcome in `specs/008-tournament-leave-early/validation.md`, as `specs/005-steady-sharing-nine-guests/validation.md` does.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T003 depends on T002, and is committed before any Phase 2 change to
  `RekkertCore/Tournament/`.
- **Foundational (Phase 2)**: depends on Setup. It blocks every story.
- **US1 (Phase 3)**: depends on Foundational. This is the MVP.
- **US2 (Phase 4)**: depends on US1 (it completes `settingAway` and the sheet).
- **US3 (Phase 5)** and **US4 (Phase 6)**: depend on US1 only. They can run alongside US2 and
  each other.
- **US5 (Phase 7)**: depends on US1. The race dialog's "is back" (T050) also needs US2's T032.
- **Polish (Phase 8)**: after the stories being shipped.

### Within Each Story

Tests first, failing for the stated reason. Then the engine (`RekkertCore`), then `MatchStore`,
then `AwayText`, then views. Run the fingerprint after every `RekkertCore/Tournament/` change.

### Parallel Opportunities

- **Phase 1**: T002 is alone; T003 follows it.
- **Phase 2**:
  - the tests T004–T007 are independent;
  - T008 → T009 → T010 → T011 run in sequence (one type chain);
  - T012 can run alongside T008–T011;
  - T013 follows T012, and T014 follows T013.
- **US1**: tests T015–T018 in parallel; T023 (`AwayText`) alongside T019–T022.
- **US2**: T027, T028 and T031 in parallel.
- **US3, US4 and US5**: after US1, three people can take one each. Within US4, T043 and T044 are
  parallel.

### Parallel Example: User Story 1

```bash
# Tests together (different files):
T015 CoreTests/TournamentAbsenceTests.swift
T016 CoreTests/AbsenceDrawTests.swift
T017 CoreTests/TournamentTests.swift (additions)
T018 SyncTests/TournamentAbsenceSyncTests.swift

# Then the engine in order, with AwayText alongside:
T019 → T020 → T021 → T022    |    T023 RekkertCore/Presentation/AwayText.swift
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: baseline and fingerprint, committed.
2. Phase 2: absences, the event, carried draws, protocol 4 and the gate.
3. Phase 3: leaving between rounds.
4. **Stop and validate**: quickstart levels 1–3, steps 1 and 7. Cross-build.
5. It can ship to TestFlight here. Players leave between rounds only, and the sheet says so
   mid-round.

### Incremental Delivery

1. **US2**: leaving at any moment. It ships with US1 for the release, because a sheet that only
   works between rounds is a stopgap.
2. **US3**: the numbers in the confirmation, and the short-of-players courts screen.
3. **US4**: labels in the table, History and the TV board.
4. **US5**: coming back.
5. **Polish**: help, README, the gate, cross-build, simulators tapped, then one real evening.

### Notes

- Commit after each task or logical group, in the conventional style already in the history,
  with no AI trailers.
- A test that passes before its implementation is a wrong test. T003 and T041 are the
  exceptions: they pin existing behaviour on purpose.
- Never edit the fingerprint's pinned values to make a task pass.
