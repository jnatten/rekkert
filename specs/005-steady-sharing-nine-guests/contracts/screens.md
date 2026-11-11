# Contract: Screens and Wording for 005

**Feature**: [../spec.md](../spec.md) · **Decisions**: [../research.md](../research.md) D-4, D-13

Only the count, the full-match text and the record view change. `M` is the host's limit:
from `Participants.limit` on the host, from `HostingStatus.limit` on its watch, and from
`noRoom`'s `limit` on a turned-away guest. People are counted, not links (FR-012).

## Counts (FR-014)

| Where | Today | After | When `M` is unknown |
|---|---|---|---|
| Share sheet, phone (`ShareCodeSheet.swift:113-119`) | "N guests joined" | "N of M joined" ("Nobody has joined yet" when N = 0) | Today's text |
| Home sharing row, phone (`SharingSection.swift:49-51`) | "N on · until you stop" | "N of M on · until you stop" | Today's text |
| End-of-match line, phone (`RootView.swift:337-343`) | "N people are on. They get your next match unless you stop." | "N of M are on. They get your next match unless you stop." | — (the host's own limit is always known) |
| Sharing card, watch (`WatchSharingCard.swift:18`) | "Sharing · N on" | "Sharing · N of M" | Today's text |
| Start screen, watch (`WatchRootView.swift:382`) | "Sharing · N on" | "Sharing · N of M" | Today's text |
| Court page, watch (`WatchCourtPage.swift:75-76`) | "Sharing · N on", leaving out guests who are out of reach | "Sharing · N of M", everyone on, in reach or not | "Sharing · N on" |
| Guests list, watch (`WatchGuestsView.swift`) | Title "Who's on" | Title "N of M on" | "Who's on" |
| End-of-match question, watch (`WatchEndOfMatchQuestion.swift:53`) | "N on" | "N of M on" | Today's text |

The VoiceOver labels read the same words, for example "Sharing on 6 0 4 2 1 8, 9 of 9 on".

## Full match (FR-013)

| Where | Title | Advice |
|---|---|---|
| Join sheet, phone (`JoinMatchSheet.swift:239, 256`) | "No room on this match" (unchanged) | "The host already has M others on. One of them has to leave before you can join." Falls back to "The host's match is full. One person has to leave before you can join." |
| Join, watch (`WatchJoinView.swift:199, 213`) | "No room on this match" (unchanged) | "The host already has M others on. One of them has to leave first." Falls back to "The match is full. One person has to leave first." |
| Wrist join with the phone in a bag (`WatchStandIn.joining == .failed(.noRoom)`) | "No room on this match" | As on the watch above, within 15 s of the join, whichever half heard it |

## Sharing record (FR-003, SC-007)

`SharingRecordView` groups entries by stint, newest first. Each group has a header:

```text
Guest · 9 Nov, 18:08–20:00
0.4 s typical · 97% within 1 s · 99% within 2 s · slowest 1.9 s · 1,170 of 1,184 timed
Wi-Fi dropped 3 times · Bluetooth 0 · host never unreachable
Battery: iPhone 6%/h · Watch 9%/h
```

- The rows below the header are as today, with the radio after the device name, as in
  [sharing-record.md](sharing-record.md).
- Lines with no data are left out.
- The Share button exports the same summaries above each stint's rows.
- The view works with VoiceOver and larger text sizes, as spec 001 FR-031 requires.
