# Data Model: Leaving an Americano or Mexicano Early

**Feature**: [spec.md](spec.md) · **Research**: [research.md](research.md)

Everything here is in `RekkertCore` unless it says otherwise. New fields are optional on the
wire and written only when not empty, so a tournament nobody left encodes as it does today.

## TournamentAbsence (new)

A stretch of rounds one player misses.

| Field | Type | Rule |
|---|---|---|
| `player` | `PlayerID` | A player on the tournament's roster. |
| `from` | `Int` | The first round index they miss. |
| `until` | `Int?` | The first round index they play again; nil while still away. When set, `until > from`. |

- **Validation**:
  - A player has at most one open absence (`until == nil`).
  - Their absences don't overlap, and are kept in the order they were folded.
  - An absence closed with `until == from` is removed rather than stored (D-4).
- **Created by**: folding `setAway(isAway: true)` (D-3).
- **Closed by**: folding `setAway(isAway: false)` (D-4). It is never edited otherwise, and never
  undone by Undo.

## Tournament (changed)

| Field | Type | Rule |
|---|---|---|
| `absences` | `[TournamentAbsence]` | **New.** Decoded with `decodeIfPresent` (default `[]`), encoded only when not empty. Not touched by a `configure` correction: the reducer's correction branch keeps the absences it has (`SessionReducer.swift:244-248`). |

New computed values:

| Name | Meaning |
|---|---|
| `isPresent(_ player:inRound:)` | No absence covers that round: `from <= round` and (`until == nil` or `round < until`). |
| `present(inRound:)` | The roster, in roster order, less everyone away for that round. |
| `presentPlayers` | `present(inRound: rounds.count)`: who the next round is drawn for. |
| `isAway(_ player:)` | They have an open absence. |
| `playableCourts`, `benchSize` | **Changed**: computed from `presentPlayers.count` instead of `players.count`. A redraw pops the last round first, so they also describe the round being redrawn (D-1). |
| `isShortOfPlayers` | Americano or Mexicano, not finished, and fewer than four present for the next round (D-7). |
| `hasAbsences` | `!absences.isEmpty`. Read by the older-build gate (D-9). |

Unchanged: `players` (the roster) and `rounds`. Every player keeps their name and their rounds.

**State transitions for one player**:

```text
playing ──setAway(true)──▶ away (open absence, from = f)
away ──setAway(false)──▶ playing (until = u; removed if u == f)
away ──setAway(true)──▶ away (from unchanged; the round in play settled per D-3)
playing ──setAway(false)──▶ playing (no change)
```

## Round and CourtMatch (unchanged shape)

- A departure in a round with points confirms the player's court there (`CourtMatch.isConfirmed =
  true`), as `setRoundConfirmed` does to every court (D-3).
- An away player is in neither `matches` nor `sitOuts` of any round drawn while they are away,
  except a raced draw (D-5). Away players that draw put on its bench are dropped from `sitOuts`.

## RoundPlacement (changed rule)

`round(for:)` accepts a placement that:

- places every player present for the round, each once;
- places nobody outside the roster;
- puts two a side on as many courts as the players it places can fill, up to the courts set up.

It may place players who are away (a draw that raced a departure, D-5). Away players on its
bench are dropped from the returned round's `sitOuts`. `TournamentEngine.placement` now also
returns a placement for Americano.

## PairingHistory (changed construction)

`PairingHistory(tournament)` folds the uncancelled rounds in order, as today. Before folding
round `r` it applies every absence whose `until == r` (D-6). For that returner:

- `sitOuts` becomes `max(own, min over the others present for r)`;
- `lastSatOut` becomes `recorded - 1`.

A tournament with no absences builds exactly the history it does today.

## Standing (changed)

| Field | Type | Rule |
|---|---|---|
| `away` | `[AwayStretch]` | **New.** One per absence, in order. Empty for everyone in a tournament nobody left. |

`AwayStretch`:

- `firstMissed: Int`, the 1-based round number;
- `backFor: Int?`, the 1-based round number they came back for, nil while away.

Ranking is unchanged: total, then difference, then name, then id (FR-011).

## AwayPreview (new)

What folding `setAway` would do now, for the confirmation (D-12). Built by
`TournamentEngine.awayPreview(_:isAway:in:)` from the same rules the fold uses.

| Field | Type | Meaning |
|---|---|---|
| `player` | `PlayerID` | |
| `isAway` | `Bool` | Leaving or coming back. |
| `fromRound` | `Int` | 1-based round number the change takes effect from. |
| `courtsBefore`, `courtsAfter` | `Int` | Courts played per round, with and without the change. |
| `benchBefore`, `benchAfter` | `Int` | How many sit out per round, with and without. |
| `redrawsRoundInPlay` | `Bool` | D-3 case 2 or D-4's redraw. |
| `stoppingCourt` | `(court: Int, score: BySide<Int>)?` | D-3 case 3: the court that stops, 1-based, and where it stands. |
| `isShortOfPlayers` | `Bool` | Fewer than four present after the change. |

## SessionState (changed)

| Name | Meaning |
|---|---|
| `sharingProtocolNeeded: Int` | **New.** 3 for a friendly with active pairing rules, 4 for a tournament with `hasAbsences`, 1 otherwise. `MatchStore`'s older-build gate compares every peer against it (D-9). |

## EventKind (changed)

| Case | Fields | Rule |
|---|---|---|
| `setAway` | `player: PlayerID`, `isAway: Bool`, `after: Int`, `placed: RoundPlacement?` | **New.** Folded by `TournamentEngine.settingAway(_:isAway:after:placed:in:)` (D-3, D-4). A no-op on a ladder, a finished tournament, an unknown player, or any other session. Not undoable. An older build decodes it as `.unrecognised` and passes it on unchanged. |

## MatchStore (RekkertSync, changed)

| Name | Meaning |
|---|---|
| `canMarkAway: Bool` | `canRunRounds`, an unfinished Americano or Mexicano, and for a guest a host at protocol 4 or later (D-10). |
| `setAway(_ player:isAway:)` | Records `setAway` with `after` and, when the round in play would be redrawn, its placement. |
| `olderPeersTurnedAway(ifNeeding:)` | **Generalises** `olderGuestsTurnedAwayByRules`: linked guests below the given protocol, on the host; 0 elsewhere. |
| `pairNeedsUpdate` | **Renames** `pairNeedsUpdateForRules`: the session in play needs a protocol the own watch doesn't speak. |
