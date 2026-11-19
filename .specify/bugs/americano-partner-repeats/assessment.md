# Bug Assessment: Americano gives the same partners two rounds running before everyone has partnered everyone

- **Slug**: americano-partner-repeats
- **Created**: 2026-11-18 (updated 2026-11-19 with the session's rounds and the decisions below)
- **Source**: pasted text, the session's rounds as played, and its sharing records (`~/Downloads/americano-18112026/`, four phones)
- **Verdict**: valid (confirmed on the session's own rounds)
- **Severity**: medium

## Report (verbatim or summarized)

> We also seems to have a bug in the americano round drawing i think?
> In round 5 and 6 mattis and endre were teammates. Two rounds in a row before a full rotation.

The session was an Americano on 18 November 2026: 9 players, 2 courts, so one player sat out
each round, 12 rounds in all. It ran 17:57–19:31 on mixed builds:
- the host and one guest on 1.2 (79) `3c81acc`, which has the `americano-draw-randomness` fix;
- one guest on 1.2 (78) `890e0c5`;
- one guest on 1.1 (75) `576fb35`.

The sharing records hold no draw data, and the app can't export a finished tournament. The
user supplied the rounds as played:

| Round | Court 1 | Court 2 | Sat out |
|---|---|---|---|
| 1 | celine & johannes v jonas & amandus | magnus & torgrim v endre & marlen | mattis |
| 2 | magnus & marlen v mattis & jonas | endre & torgrim v amandus & johannes | celine |
| 3 | torgrim & johannes v magnus & celine | mattis & marlen v jonas & endre | amandus |
| 4 | mattis & celine v johannes & magnus | amandus & endre v jonas & marlen | torgrim |
| 5 | magnus & amandus v **mattis & endre** | johannes & marlen v torgrim & celine | jonas |
| 6 | magnus & jonas v torgrim & amandus | celine & marlen v **mattis & endre** | johannes |
| 7 | marlen & torgrim v jonas & johannes | magnus & mattis v amandus & celine | endre |
| 8 | torgrim & jonas v celine & endre | marlen & amandus v johannes & mattis | magnus |
| 9 | johannes & torgrim v amandus & mattis | celine & jonas v magnus & endre | marlen |
| 10 | marlen & amandus v torgrim & celine | endre & johannes v jonas & magnus | mattis |
| 11 | jonas & torgrim v mattis & magnus | johannes & amandus v marlen & endre | celine |
| 12 | torgrim & mattis v celine & endre | johannes & magnus v jonas & marlen | amandus |

## Symptom

Within the first turn of partners, the draw pairs two players who were partners the round
before, even though another arrangement of the same players repeats nobody. README.md:117
promises that "Americano builds each round so everyone partners everyone, avoiding repeat
partners". Expected, as decided on 2026-11-19: **no repeated partner within a full turn**, a
turn being the rounds it takes for everyone to partner everyone. Sit-outs should stay as fair
as that allows.

## Reproduction

**From the session's rounds** (above). The analysis used a Python reimplementation of the
shipped seeded shuffle, sit-out split and `PairingSearch`. It reproduces
`SeededDrawTests.americanoOnTwoCourtsDrawsAsItAlwaysHas` exactly: three rounds, courts and
benches.

| Round | Repeated partners | Back to back | Fewest possible with the same players on court |
|---|---|---|---|
| 1–5 | 0 | 0 | 0 |
| 6 | 1: endre+mattis | **1: endre+mattis** | **0** |
| 7–8 | 0 | 0 | 0 |
| 9 | 1: johannes+torgrim | 0 | 1 |
| 10 | 3 | 0 | 3 |
| 11 | 4 | 0 | 3 |
| 12 | 3 | 0 | 3 |

- **Round 6 was avoidable.** With johannes out, 6 ways to pair the other eight repeat nobody,
  e.g. amandus+marlen, celine+endre, jonas+magnus, mattis+torgrim. Over all 40 320 orders the
  seeded shuffle could give those eight, the shipped search pairs mattis+endre again in
  3 347 (8 %). The session drew one of them.
- **Rounds 9–12 were mostly forced by earlier choices.** After nine rounds (36 partnerships,
  exactly the 36 pairs), endre+johannes and mattis+torgrim had never partnered, while
  endre+mattis and johannes+torgrim had partnered twice. A nine-round schedule with everyone
  partnering everyone exactly once exists: K9 has a near-1-factorisation.
- **Sit-outs:** everyone sat out once in rounds 1–9. Rounds 10–12 repeated the order of rounds
  1–3 (mattis, celine, amandus). With one player sitting out, the new rule had two equally good
  candidates in each of those rounds, so the repeat is allowed and not this bug. The records
  can't say which device drew which round.

**In general**, with the shipped engine over 400 tournament ids (`…5001`–`…5190`) and rounds
equal to one turn of partners. Builds 78 and 79 give identical numbers:

| Players / courts (rounds) | Back-to-back partners | …avoidable with the same players | Any repeated partner |
|---|---|---|---|
| 8 / 2 (7) | 1 | 1 of 1 | 5 |
| 9 / 2 (9) | 35 (1 in rounds 5–6, as here) | 37 of 37 | 179 |
| 10 / 2 (9) | 21 | 21 of 21 | 133 |
| 11 / 2 (11) | 19 | 20 of 20 | 148 |
| 12 / 3 (11) | 29 | 32 of 32 | 208 |
| 13 / 3 (13) | 54 | 55 of 55 | 288 |

**Not caused by `americano-draw-randomness`.** With one player sitting out, the old and new
sit-out rules pick the same player through the first turn, and the team search is unchanged.
That is why builds 78 and 79 give the same numbers.

## Suspected Code Paths

- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift:248-350`
  (`PairingSearch`), the team search:
  - Every earlier partnership costs the same `repeatPartnerCost = 100`, however long ago
    (`:249`, `cost` at `:307-317`). Nothing prefers a partner from five rounds ago over last
    round's.
  - `greedyTeams` (`:260-282`) takes the players in their seeded order.
  - `improve` (`:320-349`) swaps one player at a time, four passes, strict improvements only.
    It stops in local minima: round 6 above, and every back-to-back repeat in the simulations.
- `RoundScheduler.swift:352-370` (`AmericanoScheduler.nextRound`): `playing` is the bench
  split's seeded shuffle, and the teams are `PairingSearch.teams(from: playing, …)` (`:368`).
- `RoundScheduler.swift:418-427` (`TournamentEngine.appendingRound`): for Americano, `placed`
  is ignored, and `placement(of:)` returns nil for it (`:458`). **Every installed build works
  out an Americano round's teams itself**, from the bench it is given. The bench (`sitOuts`)
  is the only part of the draw an older build takes from the event.
- `RoundScheduler.swift:144-200` (`RoundScheduler.mixedBench`), `:472` (`TournamentEngine.bench`)
  and `:493` (`TournamentEngine.sitOuts`), plus `MatchStore.swift:357` and `:375`: where the
  drawing device chooses the bench and puts it in the event. The fix goes here.
- `PairingHistory.swift:41,60`: partnerships are counted, but not when they happened.

## Root Cause Hypothesis

**Confidence: high.** The team search optimises one round at a time with a cost blind to
recency, and its single-swap improvement often ends in a local minimum. Round 6 of the session
had six arrangements that repeat nobody; from about one order in twelve, the search lands on one
that repeats last round's pair. Choosing one round at a time also paints the schedule into
corners. By round 9 the session had two pairs twice and two never, where a perfect turn
exists, and rounds 9–12 then had repeats that no arrangement of those players could avoid.

This is long-standing, not a regression: with no pairing rules, `PairingSearch` gives identical
teams in every build since 22 September. The cross-build checks for `americano-draw-randomness`
found identical teams for the same bench in all 8 installed versions of the draw code.

## Proposed Remediation

**Decisions (2026-11-19)**:
- **No repeated partner within a full turn of Americano.** This wins over everything else.
  Sit-outs stay as fair as possible within that limit.
- **Plan the whole turn in this fix,** not one round at a time.
- **Leave setups where nobody sits out (8, 12, 16 players) for now.**
- **Older devices must keep working with newer ones** (decided 2026-11-18, for
  `americano-draw-randomness`). Every installed build works out Americano teams itself and
  ignores a carried placement, so **`PairingSearch` must not change**. The lever is who sits
  out, which every build since 25 September takes from the event's `sitOuts`.

**Feasibility.** Measured with the validated Python reimplementation of the shipped shuffle,
sit-out split and `PairingSearch`. For each random tournament id, search the sit-outs of a
whole turn, depth first, for one that makes the unchanged team search repeat nobody. The search
keeps sit-out counts even, never sits anyone out twice running, and tries benches in today's
sit-out order (gap shortfall, then sitting out together, then the seeded order).

| Players / courts | Full turn | Turns with no repeated partner | Team draws tried: median / worst | Shortest sit-out gap: typical (worst) | Repeated sit-out pairs |
|---|---|---|---|---|---|
| 5 / 1 | 5 rounds | 100 / 100 | 5 / 8 | nobody sits out twice | – |
| 6 / 1 | 7 rounds | 100 / 100 | 9 / 12 | 2 (2) | 6 % |
| 9 / 2 | 9 rounds | 100 / 100 | 10 / 28 | nobody sits out twice | – |
| 10 / 2 | 11 rounds | 60 / 60 | 17 / 29 | 4 (2) | 5 % |
| 11 / 2 | 13 rounds | 40 / 40 | 26 / 82 | 3 (2) | 19 % |
| 13 / 3 | 13 rounds | 30 / 30 | 14 / 33 | nobody sits out twice | – |
| 14 / 3 | 15 rounds | 30 / 30 | 27 / 50 | 5 (3) | 4 % |

A turn is `⌊n(n−1)/2 ÷ 2·courts⌋` rounds, the most rounds in which every partnership can be
new. In every row: sit-out counts even after every round, nobody twice running. Today, by
comparison:
- **Shortest sit-out gap:** 2 at 6/1, 4 at 10/2, 3 at 11/2, 6 at 14/3.
- **Repeated sit-out pairs:** 0 %, 0 %, 15 % and 0 % respectively.
- **Turns with a repeated partner:** 34–74 % (see Reproduction).

**Preferred: plan the turn's sit-outs so the unchanged team search repeats nobody.**
`RoundScheduler.mixedBench`, for Americano, runs a bounded depth-first search on every draw.
It plans from the current state to the end of the turn:
- **The plan's first bench is this round's bench.** It goes out in `sitOuts` as now, so every
  installed build since 25 September draws the same teams.
- **Each candidate bench is tried** in today's sit-out order: fewest sit-outs (hard), never
  twice running (hard), gap shortfall, sitting out together, then the seeded order.
- **Each candidate's teams are drawn** with the unchanged `PairingSearch`, on the order every
  build uses: that round's seeded shuffle, minus the bench. The seeded shuffle depends only on
  the tournament id and the round number, so later rounds' orders are known in advance.
- **A candidate whose teams repeat a partner is pruned.**
- **The first plan that gets through the turn wins.** The search is deterministic: the same
  history gives the same plan on any device, and each round's re-plan finds the continuation
  of the last.
- **When nothing gets through within a fixed budget,** counted in team draws and the same on
  every device, fall back. This happens after a hand-picked sit-out, a round an older build
  drew, a player added mid-turn, or a cancelled round. The fallback picks the bench with:
  1. the fewest pairs who partnered last round;
  2. then the fewest repeated partners;
  3. then today's sit-out order.

  Re-plan from there next round.
- **Mexicano is untouched:** it ranks courts from the table and never calls `PairingSearch`.

**Alternatives**:
- **Per-round steering only** (the 2026-11-18 proposal): choose this round's bench for its
  teams, with no plan. Cheaper, but leaves turns with a repeat: 85 of 300 at 9/2, 56–67 of
  300 at 11/2. It fails the decided requirement. It stays as the fallback.
- **A better team search, carried in the event** (a recency cost, an exhaustive search). The
  only route for setups where nobody sits out, but every installed build would disagree.
  Deferred by decision; see Open Questions.

**Files likely to change**:
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift`:
  - the turn planner, inside or beside `mixedBench`, with its budget and fallback;
  - a format flag through `TournamentEngine.bench(for:)`/`sitOuts(for:)`;
  - a read-only way to draw a candidate's teams for a future round: the seeded shuffle for
    round *k*, minus the bench, through the unchanged `PairingSearch`.
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/PairingHistory.swift`: a mutable copy for
  the search to extend and roll back. `record` exists; it needs an undo or a cheap copy, and
  which pairs partnered last round, for the fallback.
- `Packages/RekkertKit/Tests/RekkertCoreTests/`: `MixedBenchTests.swift` expectations, and a
  new `PartnerTurnTests.swift`.
- `README.md:117` and the sit-out sentences from `americano-draw-randomness`: no repeated
  partner within a turn wherever somebody sits out; sit-outs even, never twice running.
- `App/Sources/Views/SitOutPickerView.swift:93`: the footer's description of how open places
  are filled.

**Tests to add or update**:
- **This session:** rounds 1–5 as history, the round-6 bench steered. No partner repeated.
- **Every setup in the feasibility table,** several seeds each: no repeated partner within the
  turn; sit-outs even after every round; nobody twice running.
- **Re-planning is stable:** drawing round by round gives the same rounds as the plan made at
  round 1.
- **Fallback:**
  - after a hand-picked sit-out, a round drawn without `sitOuts` (an older build), or an added
    player: no back-to-back partners, the fewest repeats available, and later rounds plan again;
  - with the budget at 0: the fallback's bench, the same on every device.
- **Every older build still agrees:** each round equals
  `TournamentEngine.appendingRound(to: before, sitOuts: round.sitOuts)`. Extend
  `anOlderBuildFollowsTheBenchTheDrawCarries`.
- **`MixedBenchTests`:** loosen the sit-out expectations to the new guarantees: even, never
  twice running, gaps reported rather than pinned.
- **Mexicano, winner court, and 8 players / 2 courts:** drawn exactly as today.
- **Timing, release build:** worst case at 11/2 and 14/3, and at 12/2 with 4 sitting out
  (more candidates per round), within the watch's budget.
- **Cross-build:** rerun the handoff and live checks from `americano-draw-randomness/test.md`
  against the installed builds. Add their scripts to the repo's tooling, since the earlier
  ones lived in a scratchpad that is gone.

## Risks & Considerations

- **Sit-out spread gets a little worse, by decision.**
  - **Shortest gap:** 4 → 2 at 10/2, 6 → 3 at 14/3. Typical gaps barely move.
  - **Repeated sit-out pairs:** up to 6 % at 6/1, 10/2 and 14/3; 19 % at 11/2.

  Say so in the README and release notes. Partially undoing `americano-draw-randomness` is the
  stated trade.
- **The plan breaks when people intervene.** Hand-picked sit-outs, players added or removed,
  cancelled rounds, and rounds drawn by an older device all change the history. The
  re-plan may then find no repeat-free completion, and the fallback applies. Measure how often.
- **After the first turn:** repeats are then unavoidable. The requirement says nothing about
  later turns; see Open Questions. Rounds past the turn should at least never repeat last
  round's partners, and should spread second partnerships evenly.
- **Computing on the drawing device:** up to 82 team draws per draw in the table. Larger
  benches (12/2 with 4 out) and bigger groups have more candidates per round. Keep the budget
  fixed and the same everywhere, and measure on an Apple Watch SE, which can draw.
- **Opponents are not considered;** the plan optimises partners only. Opponent spread may get
  slightly worse; measure it.
- **More events carry a bench.** Two devices drawing at once with different benches still
  settle on one round, as the live checks showed, but this will happen more often.
- **No help without a bench:** 8, 12 and 16 players get nothing from this, by decision. 12/3
  repeats a partner within a turn in about half of tournaments (208 of 400 over 11 rounds).
- **Builds from before 25 September** ignore the carried bench, so they don't follow the plan.
  They already disagree.
- **Friendlies** with 5–6 players also use `PairingSearch` on one court
  (`FriendlyScheduler.swift:53`). A friendly carries its placement, and builds since spec 006
  honour it. Out of scope here.
- **On-court checks need the round record.** Spec 005 T099 (`roundShown(n; digest)`) would let
  a report like this one be checked from the sharing records, instead of from rounds typed in
  by hand.

## Open Questions

- [NEEDS CLARIFICATION: what should happen after the first turn? For example: no pair partners
  a third time before every pair has partnered twice, and never last round's partners again.]
- [NEEDS CLARIFICATION: setups where nobody sits out (8, 12, 16 players) are left for now. When
  to revisit the two-step route, i.e. newer builds taking a carried Americano placement first
  and a better team search later?]
- Answered 2026-11-19:
  - the session's rounds (table above);
  - no repeated partner within a full turn, winning over everything else, with sit-outs as fair
    as that allows;
  - plan the turn in this fix;
  - leave setups without sit-outs for now.
