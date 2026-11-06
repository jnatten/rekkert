# Contract: Sharing Record Lines (additions for 004)

**Feature**: [../spec.md](../spec.md) · **Format**: [spec 001's contract](../../001-fix-session-sharing/contracts/sharing-record.md)

The export format is unchanged. The new events are written on the `radio` link with the
session they are about, so they sort into the evening like any other line. They name no
player, host, score or code (Principle V).

| Kind (as written) | Written when | Session column |
|---|---|---|
| `endOfMatchAsked` | The end-of-match question opens on this device | The match that ended |
| `endOfMatchAnswered(keepSharing\|stopSharing\|stay\|leave)` | It is answered on this device | The match that ended |
| `endOfMatchUnanswered` | The host's next match closed it unanswered | The match that ended |
| `newMatchShown` | The new-match dialog opens on this device | The new match |
| `newMatchAnswered(ok\|leave)` | It is answered on this device | The new match |
| `idleStop` | Sharing stopped, or this guest left, after 30 minutes with no match on | The last match, if any |

An answer given on the other half of the pair is written there, and reaches this phone's
export once the watch's record is merged in. The record shows who answered where, which is
what tells "the watch said Leave" apart from "the phone said Leave".

## Example

```text
2026-11-07 20:14:02.511  phone  radio       endOfMatchAsked             match 5E1B…
2026-11-07 20:14:02.530  watch  radio       endOfMatchAsked             match 5E1B…
2026-11-07 20:14:09.118  watch  radio       endOfMatchAnswered(stay)    match 5E1B…
2026-11-07 20:19:40.004  phone  radio       newMatchShown               match 91C0…
2026-11-07 20:19:40.020  phone  radio       notificationPosted          match 91C0…
2026-11-07 20:19:52.731  watch  radio       newMatchAnswered(ok)        match 91C0…
2026-11-07 21:52:10.090  phone  radio       idleStop                    match 91C0…
```

`LinkRecordTests` gains a round trip for every new kind: written, exported, and read back
with `init(text:)`.
