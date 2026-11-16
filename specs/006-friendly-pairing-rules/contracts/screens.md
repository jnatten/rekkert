# Contract: Screens and Wording

**Feature**: [../spec.md](../spec.md) · **Engine API**: [engine-api.md](engine-api.md)

All of this is on the iPhone (and iPad). The watch has no new screens (research D-13). Every
string below comes from the engine's values. The views only lay them out.

## 1. Friendly setup — a Pairing section

Placement: `NewSessionView.friendlySections`, directly below the Players section.

| State | Shown |
|---|---|
| Fewer than four named players | Header **Pairing**, no rows. Footer: "Pairing rules apply when four or more play doubles." |
| Four or more, no rules | Rows: **Keep players apart…** and **Keep two together…**. Footer: "Say who should never be partners, or who always should, to even the matches." |
| Rules set | One row per rule, then the two add rows. Swipe to delete; tap to edit. |
| A rule row | "Ada and Bob apart" · "Ada, Bob and Cy apart" · "Cy and Dan together". The names follow the list as typed. |
| A clash | The clashing rows show a warning glyph. The footer names it: "Ada and Bob can't be kept both apart and together." · "Cy can only be kept together with one player." · "Cy and Dan are kept together, so they can't be in a group kept apart." **Start** is disabled while any clash stands. |
| A forecast that breaks | Footer line: "Ada, Bob and Cy can't all be kept apart in 2 of every 5 rounds — whoever sits out decides." When every round of the rotation breaks (`breaking == rounds`), for example four players with three kept apart: "Ada, Bob and Cy can't all be kept apart in any round with these players." Start stays enabled. |
| A forecast that holds | No line. |

Removing a player from the list removes them from every rule at once. A rule left with too few
players disappears, and no message is shown for it.

The setup form fixes the friendly's id when it opens, and starts with that id, so the forecast
is the draw (research D-7).

## 2. The rule editor

One sheet, `PairingRulesEditor`, opened from a setup row or from the match menu (§3).

- **Title**: "Keep apart" or "Keep together".
- **Body**: the players as a checklist.
  - Keep apart: two or more. Done is disabled below two.
  - Keep together: exactly two. A third tick replaces the oldest.
- **Footer**:
  - Keep apart: "None of these will be partners. They can still play against each other."
  - Keep together: "These two will be partners whenever both are on court. If one sits out, the
    other plays with whoever is drawn."
- Clashes show as in §1 and disable Done.

## 3. During the friendly — Pairing rules…

Placement: `MatchOptionsMenu`, beside the change-ends picker, shown when
`store.canEditPairingRules`. It is absent for Only score and Read-only guests, on a guest whose
host is older, and in singles.

- **Item**: **Pairing rules…** (`person.2.badge.gearshape`).
- **Sheet**: the §1 section on its own, titled "Pairing rules", with Cancel and Save.
- **Footer line**: "Changes apply from the next round. The round being played stays as it is."
- **Forecast**: as in §1, played forward from the rounds so far.
- **On the host, when older phones are on and the change adds the first rule**: "2 phones on an
  older Rekkert will be taken off this match. They can join again once updated." Save stays
  enabled.
- Save records the change. The up-next block (§4) updates at once on every device.

## 4. The notices (FR-007)

Shown on every phone in the friendly, guests included. Never on the watch or the TV board.

| Where | When | Text |
|---|---|---|
| Up next block (`FriendlyMatchView.upNext`), under the names and bench | `nextDraw()?.unkept` is not empty | "Ada and Bob are partners — the rules couldn't keep them apart this round." · "Cy and Dan are on opposite sides — the rules couldn't keep them together this round." Several unkept pairs are joined with a line each. |
| Under the board, with the bench line, while a round is in play | `currentRound.unkept` is not empty | The same sentences in the past tense of the round: "Ada and Bob are partners this round — the rules couldn't keep them apart." |

**Style**: footnote, secondary, with an `exclamationmark.triangle` glyph, the same weight as the
bench line. It sits after the bench line in both places.

## 5. History, results, rounds sheet, watch

Unchanged. Rules are not shown there (spec, Assumptions).

## 6. Words elsewhere

- **README › Friendly**: a paragraph after the draw's description saying:
  - rules can keep players apart or together;
  - the bench stays as fair as ever, and leans towards the rules only where players are equally
    due to sit out;
  - a round that cannot keep them says so;
  - rules can be changed in play from the match menu, and apply from the next round.
- **README › Who may do what**: add "the pairing rules" to the list *Only score* cannot touch.
- **ModeHelp › friendly**: a fourth point: "Keep players apart or together to even the matches."
