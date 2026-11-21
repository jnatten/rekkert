# Contract: Screens and Wording

**Feature**: [../spec.md](../spec.md) · **Engine API**: [engine-api.md](engine-api.md)

Everything here is on the iPhone (and iPad). The watch gets nothing new to do or show (spec
Assumptions). `AwayText` builds every sentence, so all of them are tested on macOS. Rounds are
numbered from 1 on screen.

## 1. Courts screen — "Who's here…"

**Placement**: `TournamentView.swift`'s management section, with the other round-running
actions. Shown when `model.store.canMarkAway`.

- **Button**: **Who's here…** (`person.crop.circle.badge.xmark`).
- **Footer**, only when someone is away: "Ada and Eve have left. The draw leaves them out." (one
  name: "Eve has left. …").

**When fewer than four are present**: the Draw button is replaced by this line and **Finish
tournament**: "Fewer than four players are here, so no more rounds can be drawn."

## 2. The "Who's here?" sheet

Titled **Who's here?**, with **Done**. It lists every roster player in roster order:

| State | Row |
|---|---|
| Playing | Name. Subtitle: nothing. |
| Away | Name in secondary colour. Subtitle: "Left after round 4", or "Away rounds 3–4 · left after round 7" after an earlier return. |
| Away but on a court of the round in play (a race) | Subtitle adds: "Still drawn on court 2 in round 6." with a warning glyph. |

Tapping a row opens a confirmation dialog. For the race row it offers both **Take Eve off round
6** (records her leaving again, which settles the round by D-3) and **Eve is back**.

**Leaving** — title "Has Eve left?", button **Eve has left** (destructive), then Cancel.
Message, as many lines as apply, from `AwayPreview`:

- "Round 6 hasn't started, so it's drawn again without her." (`redrawsRoundInPlay`)
- "Court 2 stops at 9–7 and counts as it stands." (`stoppingCourt`)
- "Court 2 stops at 0–0 and counts as it stands." (the edge case: their court has no points)
- "From round 7: 1 court, 3 sit out each round." (only when the courts or the bench change)
- "Nobody sits out from round 7." (the bench goes to zero)
- "Fewer than four are left, so no more rounds can be drawn." (`isShortOfPlayers`)
- On the host only: "2 phones on an older Rekkert will be taken off this tournament. They can
  join again once updated." (from `olderPeersTurnedAway(ifNeeding: 4)`, when it is more than 0)

**Coming back** — title "Is Eve back?", button **Eve is back**, then Cancel. Message:

- "Round 6 hasn't started, so it's drawn again with her." / "She plays again from round 7."
- The courts and bench line, as above.

Pronouns are not used in the real strings: the sentences repeat the name ("drawn again without
Eve"). The examples above shorten them.

The sheet holds the finish offer back while it is open (`showingFinishOffer`).

## 3. Standings tab

Under the row's existing subtitle ("N played · N sat out · ±diff"), a second line in secondary
colour for anyone with `away`: "Left after round 4" / "Away rounds 5–6" / "Away rounds 3–4 · left
after round 7". The ranking is unchanged.

## 4. Finish screen, History and the TV board's final standings

`SessionResult.placings` for Americano and Mexicano sets `detail` to the same sentence for
anyone who was away, and leaves it nil for everyone else, as today.

History's per-round sections add "Away: Eve" under "Sitting out: …" for any round someone
missed.

## 5. TV board, live standings

The name is followed by " · left" while they are away. `detail` keeps the point difference.

## 6. Help and README

- `HelpCatalog` `phone.rounds` gains **Who's here…**: "Someone going home? Mark them as left and
  the draw leaves them out from the next round. Their points stay theirs, and they can be brought
  back." Its symbol is the button's, so `HelpTests` stays green.
- `ModeHelp`, Americano and Mexicano: "Someone leaving early? Who's here… takes them out of the
  draw."
- README:
  - Americano / Mexicano: a paragraph on leaving, a court left mid-round, the table, coming back,
    and older builds.
  - Who may do what: "who has left" joins the round-running actions Only score phones don't get.
