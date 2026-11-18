# Bug Assessment: Americano benches the same players together every rotation

- **Slug**: americano-draw-randomness
- **Created**: 2026-11-18
- **Source**: pasted text
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

> Can we investigate how drawing of rounds work in americano.
> We feel like it is not that random.
> For example when we are 10 people it seems you always sit out with the same people.

## Symptom

With 10 players on 2 courts, the two people who sit out a round together in the first five
rounds sit out together again in every later five-round block, in the same order. Expected:
who you sit out with changes from block to block. Sit-outs should still stay even, and nobody
should sit out twice in a row.

## Reproduction

Reproduced with the real engine (`TournamentEngine.appendingRound`) in a scratch copy of
`RekkertKit`. The repo was not modified. Tournament id `…00FF`, 10 players, 2 courts, default
settings:

| Round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | … |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Bench | P1 P7 | P3 P6 | P0 P5 | P4 P9 | P2 P8 | **P1 P7** | **P3 P6** | **P0 P5** | **P4 P9** | **P2 P8** | **P1 P7** | … |

1. Create a new Americano tournament with 10 players and 2 courts (2 sit out per round).
2. Draw 10 or more rounds.
3. Round *n + 5* benches exactly the same pair as round *n*.

The same thing happens wherever the bench size divides the player count, for example 6 players
on 1 court, 12 on 2 or 14 on 3. Groups drift slowly when it doesn't (11 on 2). Mexicano and
winner court use the same bench code, so they behave the same way.

## Suspected Code Paths

- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift:13-21`: the
  `BenchDue` sort key is `(notChosen, sitOuts, rested)`, and the seeded shuffle only breaks
  ties after that.
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift:43-57`: under
  `.longestRested`, `rested = history.lastSitOut(id)`. Players benched in the same round share
  `lastSitOut`, so they sort next to each other and get benched together again.
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/Tournament.swift:128`: new tournaments
  default to `benchOrder: .longestRested`. Decoding without the key falls back to
  `.fewestSitOuts` (line 155).
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift:278-280` (Americano),
  `:301-303` (Mexicano) and `LadderScheduler.swift:24-26` (winner court) all pass
  `tournament.benchOrder` into `split`.
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/PairingHistory.swift:23-24,49-52`: records
  only *when* each player last sat out, not *who with*, so nothing in the draw can see repeated
  bench company.
- `Packages/RekkertKit/Tests/RekkertCoreTests/TournamentTests.swift:246-253`
  (`theBenchComesRoundInTheOrderItFirstWent`): pins the repeating queue on purpose, with
  5 players and a bench of 1, where it does no harm.
- Introduced by `889a227b` "feat: the bench goes to whoever sat out longest ago once everyone has
  had a turn" (2026-09-25). Its message says the aim is to "make the rotation a queue".

## Root Cause Hypothesis

**Confidence: high (reproduced).** `.longestRested` turns the bench into a strict queue. The
first rotation is random: everyone has 0 sit-outs and no `lastSitOut`, so the seeded shuffle
decides. After that, everyone has the same sit-out count, so the next key is `lastSitOut`, and
the group benched earliest in the last rotation is the unique minimum. That whole group is
benched together again, and the seed never gets a vote. When the bench size *b* divides the
player count *n*, every later rotation copies the first exactly.

This follows from the goal, not from a coding slip. With *b | n*, requiring every player's gap
between sit-outs to be the full *n / b* rounds forces each player into the same slot of every
rotation, and so into the same group. Mixing up who sits out together therefore has to give up
a little of the gap: in the prototype below, the shortest gap for 10 players drops from 5 to 4.
`889a227b` fixed back-to-back sit-outs under `.fewestSitOuts` without noticing this side
effect.

Measured over 100 tournaments per row (ids `…0001`–`…0064`, at least three rotations each),
current engine:

| Players / courts (bench) | Bench order | Bench pairings that repeat | Back-to-back sit-outs | Shortest gap |
|---|---|---|---|---|
| 10 / 2 (2) | `longestRested` (today) | **66.7 %** (every pairing after rotation 1) | 0 | 5 |
| 10 / 2 (2) | `fewestSitOuts` (legacy) | 10.3 % | 161 | 1 |
| 6 / 1 (2) | `longestRested` | 75.0 % | 0 | 3 |
| 12 / 2 (4) | `longestRested` | 75.0 % | 0 | 3 |
| 14 / 3 (2) | `longestRested` | 66.7 % | 0 | 7 |
| 11 / 2 (3) | `longestRested` | 31.8 % | 0 | 3 |

### Teams and opponents

`PairingSearch.teams` (`RoundScheduler.swift:163-265`) does not have the same flaw. It starts
from the seeded shuffle, then swaps players to avoid repeated partners (weight 100) and
repeated opponents (weight 1). Measured over 60 tournaments per row with today's engine, the
mixed-bench prototype, and fully random teams on the prototype's bench:

| Players / courts / rounds | Draw | Partner repeats beyond the unavoidable | Most rounds with one partner | Opponent spread (max − min) | Pairs never on a court together | Same four on a court again |
|---|---|---|---|---|---|---|
| 10 / 2 / 15 | today | 0.0 | 2.0 | 3.0 | 0.0 | 0.4 |
| 10 / 2 / 15 | mixed bench | 0.0 | 2.0 | 3.0 | 0.0 | 0.4 |
| 10 / 2 / 15 | random teams | 11.1 | 4.2 | 5.8 | 0.3 | 1.7 |
| 8 / 2 / 7 | today | 0.03 | 1.0 | 2.3 | 0.0 | 1.1 |
| 8 / 2 / 7 | random teams | 9.6 | 3.3 | 4.5 | 0.5 | 1.1 |
| 6 / 1 / 12 | today | 0.0 | 2.0 | 4.0 | 0.0 | **9.0** |
| 6 / 1 / 12 | mixed bench | 0.0 | 2.0 | 1.9 | 0.0 | 0.1 |

- **Partners:** already as spread as they can be. Fully random teams would make players see
  more repeats, not fewer: about 11 extra repeated partnerships in a 10-player evening, and
  someone partnering the same person 4 times.
- **The bench leaks onto a single court:** with one court, the four playing are simply
  everyone not sitting out. Today's repeating bench therefore puts **the exact same four
  together every rotation** (6 players: each round is identical to the one three rounds
  earlier, 100 % of the time; 5 players: likewise). The mixed bench removes this (0 %).
- **Opponents:** less even than partners because of the low weight. With 8 players over
  7 rounds, an ideal schedule has every pair facing each other exactly twice. The search
  ends with a spread of about 2. It is not a visible pattern, but it is the next thing to
  improve.
- **Evening out opponents costs randomness.** Prototype: 16 extra seeded starting points for
  the search, with the opponent weight left at 1 or raised to 10 or 50. Measured over 40
  tournaments per row. "Different next rounds" counts how many distinct rounds 30 seeds draw
  from the same history; "likeliest" is how often the most common one comes up.

  | Players / courts / rounds | Draw | Opponent spread | Most times facing one person | Partner repeats | Different next rounds (of 30) | Likeliest next round |
  |---|---|---|---|---|---|---|
  | 8 / 2 / 7 | today | 2.2 | 3.2 | 0.05 | 9.3 | 41 % |
  | 8 / 2 / 7 | harder search | 0.5 | 2.25 | 0.0 | 7.6 | 45 % |
  | 10 / 2 / 15 | today | 3.0 | 4.2 | 0.0 | 14.2 | 25 % |
  | 10 / 2 / 15 | harder search | 2.2 | 3.9 | 0.0 | 10.7 | 35 % |
  | 12 / 3 / 11 | today | 3.4 | 4.0 | 0.8 | 20.2 | 18 % |
  | 12 / 3 / 11 | harder search | 2.3 | 3.3 | 0.8 | 12.0 | 40 % |

  The improvement comes from searching harder. Raising the opponent weight to 10 or 50 changed
  almost nothing. Partners stay as spread as before. The search costs about 17× today's work
  per round.

## Proposed Remediation

**Preferred: the device that draws picks the bench with a new rule that mixes up who sits out
together, and writes it into the round event, in the `sitOuts` field older builds already
obey.**

Decided 2026-11-18: older builds must keep working alongside new ones, so turning them away
with a protocol bump is ruled out.

1. **The bench travels in the event.** `MatchStore.nextRound()` and
   `MatchStore.redrawRound(sittingOut:)` (`RekkertSync/MatchStore.swift:351-381`) work out the
   bench with the new rule and record it as
   `.nextRound(after:at:sitOuts:placed:)`'s `sitOuts`. Every build since 25 Sep 2026
   (`b35b43df`) folds `sitOuts` the same way: exactly those players sit out, and the courts are
   drawn around them with the same seeded shuffle and team search. So older and newer devices
   reach the same round.
   - **Verified** on the scratch prototype: 3 150 rounds across 7 setups. An older build given
     the bench drew identical courts and the same people on the bench every time. The order of
     the bench list differed in 916 rounds only because the prototype folded its own draw
     differently. Here every device folds the same event through the same reducer, so that
     difference disappears.
   - **On a redraw**, players picked by hand stay picked, and the new rule fills the rest of
     the bench. The full bench goes in the event.
   - **Send `sitOuts` only when the new rule's bench differs from what the event would draw
     without it.** That happened in 1 331 of the 3 150 rounds; the first rotation never
     differs. Every other event stays exactly as today's.
2. **Nothing new for an older build to read.** `SessionReducer`, `Tournament` and `BenchOrder`
   don't change: no new case and no new key. An event without `sitOuts` is drawn exactly as
   today. So:
   - An older build never meets a value it cannot decode.
   - A tournament in progress when the app updates keeps every round it has played. Rounds
     drawn by an updated device from then on mix company.
   - A round drawn by an older device is drawn the old way, and every device follows it.
3. `PairingHistory` also counts how often each pair has sat out together (`benchedTogether`,
   keyed by `PairKey`), filled in from `record(_:sitOuts:)`. It is built from the rounds
   already in the state, so nothing changes on the wire.
4. The new rule is a new public function in `RekkertCore` (for example
   `TournamentEngine.bench(for:picked:)`) that the store calls before recording. It works like
   this:
   - Keep `(notChosen, sitOuts)` as the leading key. Chosen sit-outs still go first, and
     sit-out counts never differ by more than one.
   - Drop `rested` from the key, so everyone with the same count is a candidate.
   - Walk the candidate benches with the existing `forEachBench`, in seeded order.
   - Pick the bench with the lowest `(gap shortfall, times sat out together)`:
     - **Gap shortfall:** for each member, `max(0, minGap − rounds since their last
       sit-out)`, with `minGap = max(2, ⌈n / b⌉ − 1)`.
     - **Times sat out together:** summed over every pair on the bench.
     - Include the best possible next round in both numbers (one round of lookahead, like
       `benchKeeping`), so the end of a rotation doesn't force a repeated pair.
   - Ties go to the seeded order. Put a fixed cap on the number of benches tried, so every
     device stops at the same point and draws the same bench. Wall-clock limits would break
     that.
5. **Mexicano is included** (decided 2026-11-18). The store passes the bench as `sitOuts` and
   works out `placed` around it (`TournamentEngine.placement(of:sitOuts:)`), so `placed`
   carries the same bench:
   - Older builds that know `placed` take the round as placed.
   - Builds from before `placed` fall back to `sitOuts`.

   Mexicano's bench reads only who has played and sat out with whom, never the scores, so
   the new rule applies unchanged. Winner court stays as it is. Its chosen sit-outs are whole
   units (`chosenUnits`), and fixed pairs sitting out together is intended there.

A throwaway prototype of exactly this (scratch copy only) gave:

| Players / courts (bench) | Repeats today → prototype | Shortest gap today → prototype | Back-to-back | Sit-outs stay even |
|---|---|---|---|---|
| 10 / 2 (2) | 66.7 % → **0.0 %** | 5 → 4 | 0 | yes |
| 6 / 1 (2) | 75.0 % → 1.3 % | 3 → 2 | 0 | yes |
| 14 / 3 (2) | 66.7 % → 0.0 % | 7 → 6 | 0 | yes |
| 12 / 2 (4) | 75.0 % → 27.0 % | 3 → 2 | 0 | yes |
| 11 / 2 (3) | 31.8 % → 17.0 % | 3 → 3 | 0 | yes |
| 13 / 2 (5) | 47.0 % → 42.5 % | 2 → 2 | 0 | yes |

The first rotation came out identical to today's draw, because with no history every bench
scores zero and the seeded order wins. A sample 10-player run gave 15 different bench pairs in
15 rounds: P1 P7, P3 P6, P0 P5, P4 P9, P2 P8, P1 P6, P0 P7, P4 P5, P8 P9, P2 P3, P0 P1, P5 P6,
P4 P7, P2 P9, P3 P8. With 12 / 2 and 13 / 2 the bench is a large share of the players, so some
repeats can't be avoided.

**Alternatives**:
- *A new `BenchOrder` case stored on the tournament* (this assessment's first proposal). Every
  device would draw the bench itself from the stored setting. Rejected: an older build fails
  to decode a `BenchOrder` raw value it doesn't know. Even if it decoded, it would draw its own
  bench and disagree. That leaves protocol-gating older devices, which is ruled out.
- *Make `.fewestSitOuts` the default again.* A one-line change with plenty of variety (10.3 %
  repeats), but back-to-back sit-outs return, which is the bug `889a227b` fixed. Not
  recommended.
- *Round `rested` into buckets, e.g. `lastSitOut / 2`, so the shuffle can mix neighbouring
  groups.* Very small change, but it doesn't actively avoid repeats: with 10 players the round-6
  pair is still the same as round 1's one time in three, and the gap guarantee gets looser.
- *Plan each rotation up front:* a fresh seeded permutation per rotation, with the end of the
  last rotation kept away from the start of the next. Clean when *b | n*. But the scheduler
  keeps no state between rounds, so the plan would have to be rebuilt from history every round.
  Players chosen to sit out, players added mid-tournament, cancelled rounds and *b ∤ n* all
  complicate it.

**Files likely to change**:
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift`: the new bench
  function and its search. `split` and `BenchOrder` stay as they are.
- `Packages/RekkertKit/Sources/RekkertCore/Tournament/PairingHistory.swift`: count who sat out
  together.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift`: `nextRound()` and
  `redrawRound(sittingOut:)` record the bench.
- `Packages/RekkertKit/Tests/RekkertCoreTests/`: new bench-rule tests.
- `Packages/RekkertKit/Tests/RekkertSyncTests/`: tests mixing older and newer devices.
- `README.md:122-124` and `App/Sources/Views/SitOutPickerView.swift:93`: both say "whoever sat
  out longest ago".

**Tests to add or update**:
- **Rule:** 10 players / 2 courts, 15 rounds. No bench pair repeats, no gap below 4, sit-out
  counts never differ by more than 1.
- **Rule:** the same check across several seeds and setups (6/1, 10/2, 14/3, 11/2), bounding
  repeats and shortest gap rather than pinning exact benches.
- **Rule:** the first rotation equals today's draw, so no `sitOuts` gets sent for it.
- **Older and newer together:** a newer host and an older guest (`actsAsOlderBuild`, as in
  `OlderHostTests`) play 15 rounds with 10 players. Both end with identical rounds, and the
  bench pairs don't repeat.
- **Older and newer together:** an older device draws a round in the middle. Every device
  follows it, and later rounds drawn by the newer device mix company again.
- **Older and newer together:** a redraw with one player picked by hand, recorded on a newer
  device and folded on an older one, gives the same round on both.
- **Mexicano:** 10 players over 15 rounds with a newer host and an older guest. Identical rounds
  on both, bench pairs that don't repeat, and courts still ranked from the table.
- **Winner court:** draws exactly as before.
- **Update:** a log recorded before the update replays with every round unchanged.
- **Update:** a tournament in progress when the app updates keeps the rounds it has played.
- **Racing taps:** two newer devices tap "next round" at once. One round results, the same on
  both.
- **Unchanged and still passing:** the `SeededDrawTests` pins,
  `theBenchComesRoundInTheOrderItFirstWent` (it now guards replay of events without
  `sitOuts`), `aTournamentBegunBeforeTheTieBreakKeepsItsDraws`,
  `aTournamentKeepsItsBenchOrderThroughAnEncode` and `aChosenBenchIsTheBench`.

## Risks & Considerations

- **Older devices.** Covered by putting the bench in `sitOuts` (see Preferred). Things to keep
  in mind:
  - **Never let the reducer draw with the new rule.** If it did, an event without `sitOuts`
    would give a different round on an older device. The new rule only ever runs on the
    device recording the event.
  - **Who draws decides the bench.** A round drawn by an older phone or watch benches the old
    way, so company mixes only as much as newer devices do the drawing.
  - **Builds from before 25 Sep 2026** drop `sitOuts` and never knew `benchOrder`. After the
    first rotation of a new tournament, they already draw different benches from current
    builds. This change doesn't make that worse.
- **Two taps at once.** Today a second `nextRound(after: n)` is ignored. With `sitOuts` set, the
  reducer treats it as a redraw while nothing has been played
  (`SessionReducer.swift:152-158`). Usually it lands on the same bench and courts, and only
  the round's `startedAt` moves to the later tap. If the two devices saw different histories
  (a cancel racing the draw), the round can change once, the same way on every device.
  Sending `sitOuts` only when it differs from the default draw keeps this rare.
- **Replaying stored tournaments.** With nothing changed in the reducer, `split` or
  `BenchOrder`, replaying an existing log gives exactly the rounds it gave before.
- **Speed on the watch.** The bench is worked out only on the device that draws, which may be
  the Apple Watch SE. Replaying a log costs the same as today. In a debug build the prototype
  took roughly 5× longer per tournament than today, mostly in the lookahead. Large benches (13 / 2: C(13,5) = 1 287 benches, each with its own lookahead)
  need a fixed cap on the *total* number of benches tried across both levels. Measure on a
  release build.
- **Shorter gaps.** The shortest gap drops by one round (5 → 4 for 10 players). That is the
  unavoidable price of changing company. Back-to-back sit-outs stay at zero in every setup
  measured.
- **Wider effect.** Americano and Mexicano change. Winner court does not. Call it out in the
  release notes and the README; the README's Mexicano and winner-court paragraph (line 64)
  says they sit out "as in Americano".
- **Friendly mode** calls `split` without an order (`.fewestSitOuts`) and is unaffected. It
  can still bench someone two rounds running, which is out of scope here.

## Open Questions

- Goal stated by the user (2026-11-18): the draw should "feel as random as possible". Read as
  unpredictable from round to round, with as few repeats as possible, not as literally random
  teams, which measure worse (see Teams and opponents).
- Decided (2026-11-18): evening out opponents is a follow-up, not part of this fix. The team
  search (`PairingSearch`) stays as it is.
- Decided (2026-11-18): the shortest gap may drop by one round (`minGap = max(2, ⌈n / b⌉ − 1)`),
  e.g. 5 → 4 for 10 players, in exchange for varied company.
- Decided (2026-11-18): a bench of one follows the same rule, so its order also varies between
  rotations. With 5 players on one court, a round repeats the foursome from one rotation
  earlier 39 % of the time instead of every time. Only five foursomes exist, so some repeats
  can't be avoided.
- Decided (2026-11-18): older builds must keep working with newer ones, so no protocol gating.
  The bench travels in `sitOuts`. As a result, a tournament in progress mixes company from the
  first round an updated device draws.
- Decided (2026-11-18): Mexicano is included. Winner court stays as it is.
