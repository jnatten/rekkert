# Contract: Sharing Record Additions for 005

**Feature**: [../spec.md](../spec.md) · **Format**: [spec 001's contract](../../001-fix-session-sharing/contracts/sharing-record.md) · **Decisions**: [../research.md](../research.md) D-1, D-3, D-4, D-12

## Rules

- **The export format keeps its columns.** The radio is added to the link column, and the drop
  detail inside the kind, so `LinkRecord.parse` keeps reading older exports unchanged.
- **Nothing new names a player, host, score or code** (Principle V). A delay is a number of
  seconds; a battery reading is a percentage.
- **Delay entries are written in every build** (FR-001), not only debug builds.

## Row additions

| What | Written as | Example |
|---|---|---|
| The radio of a host or guest link | `bt` or `wifi` after the short device name, in the link column | `host 57FA wifi` |
| Why a Wi-Fi link dropped | After the reason, inside `dropped(…)` | `dropped(closedByPeer; ETIMEDOUT)` |
| A point's delay, known | `pointArrived(<seconds, 3 places>s)` | `pointArrived(0.412s)` |
| A point's delay, unknown (FR-006) | `pointArrived(unknown)` | `pointArrived(unknown)` |
| A point's delay, unknown because it came from or through a 1.1 device | `pointArrived(unknown; older)` | `pointArrived(unknown; older)` |
| A battery reading | `battery(<percent>%)`, on the `radio` link | `battery(83%)` |
| Reach on the host, with the radios up | Both radios up gives `bt+wifi` | `guest 255B bt+wifi  outOfReach` |

## The summary (FR-003, D-4)

Each sharing stint starts with an indented summary line, before its first row:

```text
  summary  guest · 18:08–20:00 · 1,184 points (1,170 timed, 0 older) · median 0.34 s · slowest 1.87 s · 97% within 1 s · 100% within 2 s · drops wifi 3, bt 0 · host Bluetooth restarted 1 · host unreachable 0:00 · battery phone 6%/h, watch 9%/h · watch up to 19:58
2026-11-09 18:08:52.596  phone  radio            joinStarted
2026-11-09 18:08:55.597  phone  radio            joined                       match 4B3D…
2026-11-09 18:08:56.165  phone  host 57FA bt     proven                       match 8E65…
2026-11-09 18:08:59.993  phone  host 57FA wifi   proven                       match 8E65…
2026-11-09 18:09:01.204  phone  host 57FA wifi   pointArrived(0.287s)         match 8E65…
2026-11-09 18:09:13.880  watch  pair             pointArrived(0.412s)         match 8E65…
2026-11-09 18:09:22.952  phone  host 57FA wifi   dropped(closedByPeer; ETIMEDOUT)  match 8E65…
2026-11-09 18:09:24.101  phone  host 57FA bt     pointArrived(unknown)        match 8E65…
2026-11-09 18:10:00.000  phone  radio            battery(91%)
```

- **A host's summary** reads `host`, and lists unreachable time per guest:
  `unreachable 255B 0:31, B701 0:12`.
- **Fields with no data** read `–`.
- **A stint that cannot be judged** has fewer than 100 timed points, or more than 10% unknown.
  It shows `not enough timed points` or `too many unknown` in place of the two shares.
- **`watch up to`** appears only when the watch has not been in touch since that time.
- **`timed`** counts the points whose delay is known.
- **The parser skips the summary line**, as it skips any line it cannot read (LR:233-246).
  `SharingRecordView` shows the same numbers as a section header above the stint's rows.

## Tests

`LinkRecordTests` gains:

- a round trip for `pointArrived(unknown)`, `battery`, a radio on each link kind, and a drop
  detail;
- an older export without radios parsing unchanged.

`SharingSummaryTests` gains:

- stint boundaries: started, restored, joined, stopped, left, and end of file;
- the percentiles;
- unknown delays left out of the shares;
- battery drain per hour.
