# Contract: What Travels Between Devices (changes for 006)

**Feature**: [../spec.md](../spec.md) · **Data model**: [../data-model.md](../data-model.md) ·
**Builds on**: [spec 005's contract](../../005-steady-sharing-nine-guests/contracts/wire-protocol.md)

The event format, the version vectors and the merge are unchanged. This release adds optional
fields to values that already travel, one carried value on an existing event, and a protocol
number that lets the host turn older guests away while the friendly has rules.

## Values inside events and snapshots

These travel inside `configure`, `restore` and `snapshot`, and are stored in `active.json`,
History and presets.

| Value | Field | Status | Rule |
|---|---|---|---|
| `FriendlySession` | `pairingRules: [PairingRule]` | **New, optional** | **Always written by this build, an empty list included**; absent means an older build wrote the friendly. An older build drops it unread (synthesized decoding ignores unknown keys), which is why the gates below exist. |
| `FriendlyRound` | `unkept: [UnkeptRule]` | **New, optional** | Written only when not empty. Filled in from the rules in force when the round was drawn; never recomputed. |
| `PairingRule` | `id`, `kind` (`"apart"`, `"together"`), `players` (sorted) | **New** | See the data model. |
| `UnkeptRule` | `kind`, `players` (two, sorted) | **New** | See the data model. |
| `PresetConfiguration.friendly` | `pairing: [PairingRule]?` | **New, optional** | Written only when not empty. Older presets read unchanged. |

**A friendly with no rules gains one key, `"pairingRules": []`, and draws exactly as it does
today.** An older build ignores the key. `placed` (below) is the only addition to its draws.

## Events

| Event | Status | Rule |
|---|---|---|
| `nextRound(after:at:sitOuts:placed:)` for a friendly | **Now carries `placed`** | `placed.courts` holds the one court's two sides, and `placed.sitOuts` the bench, as the drawing device drew them. The reducer takes it as it is when it fits the friendly's players, team size and bench size, and otherwise draws as today. It fills in `unkept` either way. Older builds ignore `placed` for a friendly and draw for themselves, which matches whenever there are no rules. `sitOuts` stays unused for a friendly. |
| `configure(.friendly(session))` mid-session | **Unchanged shape; now also carries rules** | Recorded by `setPairingRules` as `setChangeEnds` already does. The reducer's correction branch adopts the rules only when the incoming friendly carries the `pairingRules` key, and always adopts `name`, `rules` and `players`; the id and the rounds stay. An older build's correction (its "swap sides", say) carries no key and leaves the rules as they were. Not undoable, as before. |

No new `EventKind` is added.

## Sharing scope (host ↔ guests)

| Message | Status | Rule |
|---|---|---|
| `Wire.sharingProtocol` | **2 → 3** | Sent in `hello` and `GuestCard` as today. |
| `hello(…, sharingProtocol)` from a guest | **New admission rule at the host** | While the host's state is a friendly with active rules: a guest whose protocol is below 3 is turned away and the link refused. Protocol 2 gets `needsUpdate(sessionID:)`; no protocol (1.1) gets `noRoom(sessionID:limit:)`, the only refusal 1.1 reads. The sharing record notes `.refused(.needsUpdate)` for both. |
| Rules appear with an older guest on | **New host behaviour** | When the host folds a state that has active rules where the previous state had none, it sends each linked guest below 3 the same refusal as above and refuses its link. The rules editor has already told the host how many that will be. |
| A guest deciding whether to offer the rules editor | **New guest rule** | Offered only when the host's last `hello` carried protocol 3 or later. An older host could not draw with them. |

A guest's watch is reached through its phone, and guests reach each other only through the
host, so the host's gate covers every guest device.

## Pair scope (phone ↔ its own watch)

There are no new messages. A watch on this build receives the friendly, rules included, as it
receives everything today, and draws with them through the shared reducer.

| Rule | Detail |
|---|---|
| **A watch below protocol 3 is held back** | The phone reads its watch's protocol from the watch's `hello`. While the session in play is a friendly with active rules and the watch is below 3, the phone sends the watch nothing of that session: no pushed `events`, no queued events, no `events` in reply to the watch's `hello`, and no `snapshot`. `pairNeedsUpdateForRules` is true, and the phone's board says the watch needs updating. |
| **Released** | When the watch says hello at 3 or later, or the session no longer has active rules, the phone sends what the watch is missing, as it does after any gap. |
| **From the older watch** | Whatever it sends is folded as usual. A point is addressed by round and side, so one for a round already over is dropped. |

## Compatibility rules

1. **Without rules, nothing changes for anyone.** An older guest on a friendly with no rules
   draws what everyone draws, `placed` or not.
2. **With rules, nobody older is on.** The host turns protocol 2 and 1.1 guests away, at
   joining and when the rules first appear. 1.2 shows "needs updating" on the phone and the
   watch. 1.1 says the match is full: its wording cannot be changed from here (research D-9).
3. **An older host never sees rules.** A newer guest does not offer the editor to an older host.
4. **A phone's own older watch is held back** while the friendly has rules, and the phone says
   so. No device that cannot draw with the rules ever holds a friendly with rules.
5. **An older build's correction cannot wipe the rules**, because the rules are adopted only
   from a friendly that carries the key.
