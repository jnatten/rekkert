# Research: Leaving an Americano or Mexicano Early

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

What the code does today (R-1 to R-9), then what this feature decides (D-1 to D-13). Line
numbers are at `497bdf8`.

## What the code does today

### R-1 The roster is the draw's only idea of who is here

`Tournament.players` is fixed at setup. Every scheduler reads it whole:

- `AmericanoScheduler` and `MexicanoScheduler` hand it to `RoundScheduler.split`
  (`RoundScheduler.swift:477`, `:500`).
- `TournamentEngine.bench` hands it to the Americano turn planner and the Mexicano bench mixer
  (`:595`, `:602`).
- `RoundScheduler.chosen` validates a picked bench against it (`:341`).
- `RoundPlacement.round(for:)` accepts a carried draw only if it places exactly these players
  (`RoundPlacement.swift:19`).
- `playableCourts` and `benchSize` divide its count (`Tournament.swift:183-190`).

Nothing anywhere marks a player as absent. The sit-out pick is the only lever, and it is
bounded by `benchSize`.

### R-2 Standings credit the bench, not absence

`Leaderboard.standings` (`Leaderboard.swift:19-51`) adds points for every court a player is on
and compensation for every round they are in `sitOuts`. A player in neither earns nothing for
that round. The table lists every roster player, ranked by total, then difference, then name.

The Players page builds contests only from courts that were played (`Contests.swift:52-66`) and
never reads `sitOuts`. A player's average and share already count only the rounds they played.

### R-3 Draws are folded on every device, and Americano is recomputed

`nextRound(after:at:sitOuts:placed:)` is folded by `SessionReducer` (`SessionReducer.swift:147-167`):

- Mexicano and ladders adopt `placed` when it fits (`RoundScheduler.swift:536-540`).
- Americano ignores it. `TournamentEngine.placement` returns nil for Americano
  (`:565-575`), and every device draws the round again from the seed, the bench carried in
  `sitOuts` and the pairing history.

That is safe today because nothing that changes an Americano draw's inputs can race a draw.
A cancel only lands on the last round (`MatchEvent.swift:30-31`), and the bench travels with
the draw.

### R-4 A court can be settled on its own; points then stop landing

`CourtMatch.isConfirmed` is per court. `setRoundConfirmed` sets it on every court of a round
(`SessionReducer.swift:133-139`), but nothing stops one court being confirmed by itself.

- `mutateCourt` drops points and corrections addressed to a confirmed court
  (`SessionReducer.swift:341-344`).
- `isDone` treats a round as done when every court is confirmed or finished
  (`Tournament+Courts.swift:58-61`).
- `Leaderboard`, with `onlyConfirmed` for Mexicano's ranking, counts confirmed courts as
  they stand.

### R-5 Redrawing the round in play is already a thing, guarded by "nothing played"

`canRedrawCurrentRound` (`Tournament.swift:194-197`) is true while no court in the last round
was played or confirmed. Picking the bench by hand records `nextRound(after: last - 1, sitOuts:,
placed:)`, which draws the round again with the same seed (`RoundScheduler.swift:550-560`). Same
index and same seed, so picking the bench it already has gives back the same round. The codebase
treats an unscored round as not yet walked onto.

### R-6 Benches are chosen by sit-out count, then rest

- `split` orders by (picked first, fewest sit-outs, longest since last sit-out under
  `.longestRested`) (`RoundScheduler.swift:50-99`).
- The Americano turn planner orders by sit-out count and avoids benching anyone two rounds
  running (`:207-305`).
- The Mexicano mixer orders by sit-out count and spreads the gaps (`:144-205`).

All of them read `PairingHistory`, which is rebuilt from the rounds (`PairingHistory.swift:24-28`).
A player absent for three rounds would have fewer sit-outs than everyone, and an old
`lastSatOut`, so every bench order would send them to the bench first.

### R-7 Full rotation counts pairs among the whole roster

`Tournament.plan` (`Tournament+Length.swift:61-101`) builds the unpaired set from every
`players` pair. With a player gone for good, the rotation can never complete, and "N
partnerships to go" never reaches zero.

### R-8 Older builds can't be told, so they're kept off

An event kind an older build doesn't know decodes as `.unrecognised`. It is kept and passed on,
but changes nothing there (`MatchEvent.swift:68-71`). An older build would therefore keep
drawing an absent player, and, recomputing Americano rounds from the log, re-draw every round
since the departure differently.

Spec 006 solved the same problem for pairing rules (`MatchStore.swift:2974-3038`):

- the host turns away guests below protocol 3 while the state needs it, at hello and when the
  need appears;
- a phone holds the session back from its own watch below 3;
- a guest offers the action only to a host at 3 or later.

That code asks one rules-specific question (`hasActiveRules`) against one constant
(`pairingRulesProtocol`).

### R-9 Where the organiser acts on a tournament

The tournament doesn't use `MatchOptionsMenu`. The courts screen's `managementSection`
(`TournamentView.swift:288-386`) holds every round-running action, gated by
`model.store.canRunRounds`. The sit-out picker is a sheet from there (`:242-258`, `:97-99`). The
finish offer is held back while that sheet or a court is open (`:443-448`).

The standings tab (`StandingsView.swift`) has a free subtitle line per row (`:55-58`). The
finish screen, History and the TV board's final standings all render
`SessionResult.placings`, whose `detail` is nil for Americano and Mexicano
(`SessionResult.swift:275-282`). The watch shows standings, but the spec doesn't ask it to show
anything new.

## Decisions

### D-1 A tournament holds absences, and draws read the players present

`Tournament` gains `absences: [TournamentAbsence]`. Each one has a player, `from` (the first
round index they miss) and `until` (the first round index they are back, nil while still away).
It is written only when not empty, so a tournament nobody left encodes byte for byte as today.

`present(inRound:)` is the roster minus everyone away for that round, in roster order. Every
reader in R-1 asks it for the round being drawn (`rounds.count`) instead of using `players`:

- the schedulers;
- the bench planner and mixer;
- the sit-out pick validation;
- the placement fit;
- `playableCourts` and `benchSize`.

Redrawing pops the last round first, so "the round being drawn" is right for both paths without
a second parameter. The roster itself never shrinks: names, History, the Players page and the
table keep everyone.

*Alternatives*:

- **Removing the player from `players`.** Loses their name from the table and History, and
  can't express coming back.
- **Benching them every round.** Credits compensation (R-2) and needs a bench seat (R-1).

### D-2 One new event, `setAway`, folded by the engine

`EventKind.setAway(player:isAway:after:placed:)`:

- `after` is the last round index the marking device held (-1 for none).
- `placed` is the round in play as that device redrew it, when it redrew one.

The reducer calls `TournamentEngine.settingAway`, a pure function, so every device folds it
identically. It is not undoable: Undo keeps meaning "take back the last thing that changed the
score" (FR-012), and bringing a player back is the same event with `isAway: false`.

*Alternatives*:

- **A `configure` correction carrying the absences**, as 006 did with rules. A whole-state
  correction can't address the round in play, and two corrections racing would overwrite each
  other's absences.

### D-3 Folding a departure: three cases, decided by the state at fold time

Let `L` be the last round in the state when the event folds. The event's `after` doesn't
choose the case. It only says whether the carried `placed` may be used.

1. **No round yet, or `L` is cancelled or done**: `from = L.index + 1` (or 0).
2. **`L` has nothing played and nothing confirmed** (R-5): `from = L.index`, and `L` is drawn
   again for the players present. The rest of `L`'s bench is passed as picks, in its order and
   cut to the new bench size, and any seats left over are drawn as usual. A round stores only
   its bench, not which of it was picked by hand, so keeping the whole bench is the only rule
   every device can follow. The carried `placed` is taken when `after == L.index` and it fits;
   otherwise the round is redrawn here. This is the existing redraw, so an unscored round
   changes exactly as it does when the bench is picked (FR-006).
3. **`L` is in play with points**: `from = L.index + 1`. If the player is on a court of `L` that
   isn't finished, that court is confirmed where it stands (R-4): points stop landing on it, it
   counts for all four, and `L` is done once the other courts finish (FR-007). A player on
   `L`'s bench keeps that round's credit.

**Their court has no points but another court does** is case 3: the court confirms at 0–0, as
the spec's edge case says.

Marking a player who is already away re-applies cases 2 and 3 to `L` and leaves `from` alone.
That is how the organiser settles a round the player was drawn into by a race (D-5).

### D-4 Coming back mirrors leaving, and a mistake leaves no trace

`setAway(isAway: false)` closes the open absence:

- **`L` has nothing played**: `until = L.index`, and `L` is redrawn with them, the same way as D-3
  case 2: the bench `L` already has stays as picks, and a seat the larger group adds to the
  bench is drawn as usual.
- **Otherwise**: `until = L.index + 1`.

An absence whose `until` equals its `from` is removed. A player marked and brought back before
another round counts is drawn as if never marked: same seed, same players, same round (R-5,
Story 5 scenario 2). The one exception is a bench picked by hand that the departure shrank. The
redraw on return picks the missing seats as the draw would, because the earlier pick is no
longer recorded anywhere. The organiser picks it again as they would today.

### D-5 Americano draws carry where they put everybody, and a carried draw is never re-partnered

A departure can now race a draw. Device A marks Eve away while device B, out of contact, draws
round R with Eve and starts scoring it. If A's event sorts first, recomputing R on B's device
would re-partner a round people walked onto (Principle II). The fix has two parts.

**`TournamentEngine.placement` returns a placement for Americano too**, as Mexicano, ladders and
friendlies already do. Older builds ignore `placed` for Americano and recompute. Without a race
that gives the same round, as it does for Mexicano today, and once a tournament has an absence
they are kept off anyway (D-9).

**`RoundPlacement.round(for:)` relaxes its fit check.** A placement fits when it:

- places every player present, each once;
- places nobody outside the roster;
- puts two a side on as many courts as the players it places can fill.

It may include players who are away, which is the race. Away players it put on the bench are
dropped from that round's `sitOuts`, so they earn no credit.

The round stands as drawn, and the phone flags any away player on a court of the round in play
(see the screens contract). Marking them again settles it by D-3.

*Alternatives*:

- **Recompute a raced draw.** Re-partners a round that may have points on it.
- **Refuse a departure while any device might be drawing.** There is no way to know.

### D-6 A returner is owed neither a rest nor a game

When `PairingHistory` is built, it reaches each absence's `until` round and adjusts the returner
before that round is drawn:

- their sit-out count becomes the larger of their own and the fewest held by anyone else present
  for that round;
- their last sit-out becomes the round just before.

So every bench order (R-6) treats them as level with whoever is next due, and as having just
rested. They play their first round back (nobody sits out twice running), then rejoin the
rotation where the least-rested are. The adjustment is computed from the rounds alone, so every
device makes it the same way. It touches only the bench's bookkeeping: the table counts real
sit-outs (R-2).

*Alternatives*:

- **Count the away rounds as sit-outs.** That is owed games: they would be kept off the bench
  for as many rounds as they missed.
- **No adjustment.** That is owed rest: they would be benched first (R-6).

### D-7 Lengths and the finish

- A number of rounds is untouched.
- A full rotation counts pairs among the players present for the next round (R-7). Pairs
  partnered while someone was here still count as partnered.
- With fewer than four present, `playableCourts` is 0. `canDrawNextRound` already lets the draw
  no-op, and `Tournament.isShortOfPlayers` tells the courts screen to say why and offer Finish
  (FR-010).
- Leaving never finishes anything by itself.

### D-8 The table says who left; the ranking doesn't change

`Standing` gains `away: [AwayStretch]`, each a first missed round and an optional return round,
1-based for display. `Leaderboard`'s order is unchanged (FR-011, clarified).

The sentences live in `RekkertCore/Presentation/AwayText.swift`: "Left after round 4",
"Away rounds 5–6", and an open absence after a return, "Away rounds 3–4 · left after round 7".
They appear:

- under each standings row;
- as `Placing.detail` for Americano and Mexicano (the finish screen, History, the TV board's
  final standings);
- as a "left" mark after the name on the TV board's live standings, where `detail` already
  holds the difference;
- as "Away: …" on the round's line in History.

The watch and the Live Activity are unchanged (spec scope; the Live Activity's 4 KB limit).

### D-9 Older builds: one gate for every state that needs a newer build

- `Wire.sharingProtocol` goes 3 → 4.
- `SessionState.sharingProtocolNeeded` (RekkertCore) is 3 for a friendly with active rules, 4
  for a tournament with any absence, past or present, and 1 otherwise. An older build would
  re-draw every round since the first departure (R-8), so the need lasts for the rest of the
  tournament.
- `MatchStore`'s rules-specific gate is generalised to "below the protocol the state needs":
  turning guests away at hello and when the need rises, holding the session back from a lagging
  own watch, and the count shown before confirming. 006's behaviour is unchanged, because its
  need stays 3.
- A guest offers leaving and coming back only to a host whose hello carried 4 or later.
- `pairNeedsUpdateForRules` becomes `pairNeedsUpdate`, and the board's wording drops "for the
  pairing rules".

### D-10 Who may do it, and where

`MatchStore.canMarkAway` requires all of:

- `canRunRounds`;
- a tournament that is Americano or Mexicano and not finished;
- for a guest, a host at protocol 4.

The action is `setAway(_:isAway:)`, which records the event with the placement it redrew
(D-3, D-4). The watch doesn't offer it.

### D-11 The sheet: "Who's here?"

A button **Who's here…** (`person.crop.circle.badge.xmark`) goes in the courts screen's
management section for anyone who may mark players away. It opens a sheet listing every roster
player with their state ("Playing", "Left after round 4"). Tapping one asks to confirm with
`AwayPreview`'s sentences (D-12), then records it.

That is three taps: button, player, confirm (SC-001). The sheet joins the finish offer's
hold-back condition (R-9). The new symbol gets a help item, or `HelpTests` fails.

*Alternatives*:

- **A context menu on standings rows.** Hidden, and the standings are another tab.
- **The options menu.** Shown to everyone, so it would need gating per item.

### D-12 The confirmation is worked out by the engine

`TournamentEngine.awayPreview(_:isAway:in:)` returns what the fold would do:

- the next round's courts and bench, before and after;
- whether the round in play is redrawn;
- the court that stops, and its score;
- whether fewer than four remain.

`AwayText` turns it into sentences, for example:

- "From round 6: 1 court, 3 sit out each round."
- "Court 2 stops at 9–7 and counts as it stands."
- "Round 6 hasn't started, so it's drawn again without Eve."
- "Fewer than four are left, so no more rounds can be drawn."

The host adds "2 phones on an older Rekkert will be taken off this tournament." from
`MatchStore` (D-9).

### D-13 Pins before the draw changes

`TournamentNoAbsenceFingerprintTests` is committed green on today's code before any scheduler
changes. It pins every Americano and Mexicano round for 5 to 16 players on 1 to 4 courts over
20 rounds, with a hand-picked bench in round 3. `scripts/cross-build.sh` must still fold every
round the same against the last two TestFlight builds. That shows carrying `placed` for
Americano (D-5) changes nothing an older build sees.
