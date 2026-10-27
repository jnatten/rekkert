# Contract: The Exported Sharing Record

**Feature**: [../spec.md](../spec.md) · **Entity**: `LinkRecordEntry` in
[../data-model.md](../data-model.md)

Exported from Settings → Sharing record → Share, as a plain-text file named
`rekkert-sharing-2026-10-27.txt`. It covers the last 7 days of this phone and its watch.

## Format

```text
Rekkert sharing record
App 1.0 (56) abc1234 · iOS 26.1 · watchOS 26.1
This phone 7F3A… · its watch 19C2…
Covers 2026-10-20 to 2026-10-27

2026-10-26 19:02:11.204  phone  radio       launched(user)
2026-10-26 19:02:15.880  phone  radio       sharingStarted              match 5E1B…
2026-10-26 19:03:02.117  phone  guest A41D  proven                      match 5E1B…
2026-10-26 19:03:02.119  phone  guest A41D  joined                      match 5E1B…
2026-10-26 19:41:57.006  watch  pair        dropped(timeout)
2026-10-26 19:42:30.512  phone  guest A41D  outOfReach                  match 5E1B…
2026-10-26 19:43:10.001  phone  radio       launched(restored)
2026-10-26 19:43:10.004  phone  radio       appHadBeenEnded
2026-10-26 19:43:10.240  phone  radio       sharingRestored             match 5E1B…
2026-10-26 19:43:18.733  phone  guest A41D  backInStep                  match 5E1B…
```

**One line per entry**, sorted by time. The columns are:

1. local date and time, to milliseconds;
2. which device wrote it, `phone` or `watch`;
3. the link: `pair`, `host` or `guest` followed by the first four hex digits of that
   device's id, or `radio`;
4. the event kind, with its reason;
5. optionally, the first four hex digits of the match's session id.

## Rules

- **Never in it**: player names, scores, or the code.
- **Device ids** are the app's own random identifiers, shortened to four hex digits on each
  line. The header gives this phone's and its watch's in full, so two exports from the same
  evening can be lined up.
- **Covered by tests**: it can be read back into entries, and parsing an export is part of
  `LinkRecordTests`.
- **Watch entries** that have not reached the phone yet are missing. The header then says
  "Watch entries up to 19:41 (not in touch since)".
