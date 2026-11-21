# Contract: What RekkertCore and MatchStore Expose

**Feature**: [../spec.md](../spec.md) · **Data model**: [../data-model.md](../data-model.md)

Every rule below is a pure function in `RekkertCore`, testable on macOS. `MatchStore` only gates
and records.

## TournamentEngine

### `settingAway(_ player: PlayerID, isAway: Bool, after: Int, placed: RoundPlacement?, in: Tournament) -> Tournament`

The fold of `setAway`. Returns the tournament unchanged when it is a ladder, finished, or the
player is not on the roster. Otherwise, with `L` the last round, if any:

| Situation | `isAway: true` | `isAway: false` |
|---|---|---|
| No round, or `L` cancelled or done | Open an absence from `L.index + 1` (or 0). | Close the open absence at `L.index + 1` (or 0). |
| `L` has nothing played or confirmed | Open from `L.index`. Redraw `L` for the players present, with `L`'s bench less the player as picks. | Close at `L.index`, and redraw `L` the same way. |
| `L` in play with points | Open from `L.index + 1`. If the player is on an unfinished court of `L`, confirm that court. | Close at `L.index + 1`. |

- An absence closed at its own `from` is removed.
- Marking a player who is already away keeps their `from`, and still applies the middle and last
  rows to `L`.
- Bringing back a player who is not away changes nothing.
- A redraw takes `placed` when `after == L.index` and `placed` fits (below). Otherwise it is drawn
  here, with the same seed and the same picks.

**Guarantees**:

- Deterministic in its inputs.
- No court with points ever changes teams.
- Without absences, the result encodes exactly as the input did.

### `awayPreview(_ player: PlayerID, isAway: Bool, in: Tournament) -> AwayPreview?`

What `settingAway` would do now, for the confirmation. Nil when it would do nothing.

### `appendingRound`, `redrawingLastRound`, `bench`, `sitOuts`, `placement` (changed)

- **Who they draw for**: the players present for the round being drawn, never the whole roster.
- **`placement` and Americano**: now returns a placement for Americano too.
- **Without absences**: every one of these returns what it returns today, pinned by
  `TournamentNoAbsenceFingerprintTests`.

## RoundPlacement

### `round(for: Tournament) -> Round?` (changed fit)

- **Fits when it**:
  - places every player present for the round, each once;
  - places nobody outside the roster;
  - puts two a side on as many courts as it can fill.
- **Away players**: they may be in it (a raced draw, D-5). Any it benched are dropped from
  `sitOuts`.
- **Otherwise**: nil, and the round is drawn here as before.

## Tournament

| Member | Contract |
|---|---|
| `absences` | See the data model. Only `settingAway` changes it. |
| `isPresent(_:inRound:)`, `present(inRound:)`, `presentPlayers`, `isAway(_:)` | Read only from `absences`. |
| `playableCourts`, `benchSize` | From `presentPlayers`. |
| `isShortOfPlayers` | No round can be drawn for want of four present players. |
| `plan` | A full rotation counts pairs among `presentPlayers`. A number of rounds is unchanged. |
| `awayPlayersOnCourt(inRound:)` | Players away for that round who a raced draw put on a court of it. Drives the race notice. |

## Leaderboard

`standings(for:onlyConfirmed:)`:

- Every roster player has a row, with `away` filled from `absences`.
- The order is unchanged.
- Points and compensation come from `matches` and `sitOuts` as today. An away player is in
  neither, so they earn nothing for the rounds they miss.

## AwayText (new, `RekkertCore/Presentation`)

Builds every sentence in [screens.md](screens.md) from `AwayStretch`, `AwayPreview` and names.
Each sentence is pinned in `AwayTextTests`.

## SessionState

`sharingProtocolNeeded` is 3 for a friendly with active rules, 4 for a tournament with absences,
and 1 otherwise.

## MatchStore (RekkertSync)

| Member | Contract |
|---|---|
| `canMarkAway` | `canRunRounds` and an unfinished Americano or Mexicano. For a guest, the host's hello also carried protocol ≥ 4. |
| `setAway(_:isAway:)` | Guarded by `canMarkAway`. Records `.setAway(player:isAway:after: rounds.count - 1, placed:)`, with `placed` the redrawn round in play when D-3 case 2 or D-4's redraw applies. |
| `olderPeersTurnedAway(ifNeeding:)` | On the host: linked guests whose protocol is below the argument. 0 elsewhere. |
| `pairNeedsUpdate` | The state needs more than the paired watch speaks. While true, the phone holds the session back from it, as 006 does. |
| Host admission | At hello, and whenever `sharingProtocolNeeded` rises, guests below it are turned away: protocol 2 and 3 with `needsUpdate`, 1.1 with `noRoom`. |
