# Contract: What Travels Between Devices (changes for 008)

**Feature**: [../spec.md](../spec.md) · **Data model**: [../data-model.md](../data-model.md) ·
**Builds on**: [spec 006's contract](../../006-friendly-pairing-rules/contracts/wire-protocol.md)

The event format, version vectors and merge are unchanged. This release adds:

- one event kind;
- one optional field on a value that already travels;
- a placement on Americano draws;
- protocol 4, which keeps older devices off a tournament someone has left.

## Values inside events and snapshots

These travel inside `configure`, `restore` and `snapshot`, and are stored in `active.json` and
History.

| Value | Field | Status | Rule |
|---|---|---|---|
| `Tournament` | `absences: [TournamentAbsence]` | **New, optional** | Written only when not empty. Absent means nobody has left. An older build drops it unread, which is why the gate below exists. A `configure` correction never carries or changes it. |
| `TournamentAbsence` | `player`, `from`, `until?` | **New** | See the data model. |

**A tournament nobody left encodes exactly as today.**

## Events

| Event | Status | Rule |
|---|---|---|
| `setAway(player:isAway:after:placed:)` | **New** | Folded by `TournamentEngine.settingAway`. `after` is the marking device's last round index, and `placed` its redraw of the round in play, if any. An older build decodes it as `.unrecognised`, keeps it and passes it on, so the log stays whole. Not undoable. |
| `nextRound(after:at:sitOuts:placed:)` for Americano | **Now carries `placed`** | The receiving reducer adopts it when it fits the relaxed rule (data model, `RoundPlacement`), so a departure that sorts before a draw can never re-partner it. Older builds ignore `placed` for Americano and draw for themselves. That gives the same round whenever nothing raced the draw, which `scripts/cross-build.sh` checks. |
| `nextRound` for Mexicano and ladders | Unchanged | They already carry `placed`. The fit check is the relaxed one. |

## Sharing scope (host ↔ guests)

| Message | Status | Rule |
|---|---|---|
| `Wire.sharingProtocol` | **3 → 4** | Sent in `hello` and `GuestCard` as today. |
| `hello` from a guest | **Generalised admission** | While the host's state needs protocol N (`sharingProtocolNeeded`), a guest below N is turned away and its link refused. Protocols 2 and 3 get `needsUpdate`; 1.1 gets `noRoom`. A friendly with rules still needs only 3, so a guest on protocol 3 can still join one. |
| The need rises with older guests on | **Generalised** | When the host folds a state that needs more than the previous one, every linked guest below the new need gets the same refusal. The host's confirmation has already said how many that will be. |
| A guest offering "Who's here…" | **New guest rule** | Only when the host's last `hello` carried 4 or later. |

## Pair scope (phone ↔ its own watch)

| Rule | Detail |
|---|---|
| **A watch below the need is held back** | As in 006, with the need read from `sharingProtocolNeeded`. A watch on protocol 3 is held back from a tournament with absences, and the phone's board says it needs updating. |
| **Released** | When the watch says hello at the protocol needed, or the session in play changes to one that doesn't need it. |

## Compatibility rules

1. **Nobody left, nothing changes** for any build, `placed` on Americano included.
2. **Someone has left, nobody older is on**: older guests are turned away, and an older own watch
   is held back.
3. **The need lasts** for the rest of the tournament, even after everyone is back. An older build
   would draw every round since the first departure again, differently.
4. **An older host never gets the action.** A newer guest doesn't offer it.
5. **No carried draw is re-partnered**, whichever order a departure and a draw arrive in.
