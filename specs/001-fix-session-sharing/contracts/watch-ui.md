# Contract: What the Screens Offer

**Feature**: [../spec.md](../spec.md)

A tap is counted from the watch's scoreboard, the court page. Opening the menu page is
taken as one tap, as on the watch today.

## Host's watch

| Want | Path | Taps | Shows |
|---|---|---|---|
| Share the match (phone in a bag) | Menu → **Share match** | 2 | The code page once the phone reports it is sharing. "Can't reach your iPhone" otherwise, and nothing changes (FR-020) |
| Read out the code | Menu → **Code** | 2 | Six digits as `482 915` across the screen, the QR image below, and "Scan with the Camera to join" (FR-017, FR-018) |
| See who is on | Menu → **Who's on** | 2 | One row per participant: name (or "Phone 1"…) and a state: **In step**, **Catching up**, or **Out of reach since 20:41** (FR-010, FR-020) |
| Stop sharing | Menu → **Stop sharing** → confirm | 3 | "Stop sharing? Everyone else leaves this match." On confirm, guests are told (D-9) |

- **Share match** shows only while a match is on and the phone is not sharing. **Code**,
  **Who's on** and **Stop sharing** show only while it is. None of them shows on a guest's
  watch, and **Leave** never shows on the host's (FR-020, FR-022).
- The court page shows "Sharing · 3 on" beneath the score while sharing.
- When a code changes (FR-019), the code page updates in place.

## Guest's watch

| Want | Path | Taps | Shows |
|---|---|---|---|
| Join from the start screen | **Join a match** → six digits | 1 + 6 | The sixth digit joins, as today |
| Join from a match screen | Menu → **Join a match** → six digits | 2 + 6 | Joining replaces a match of the watch's own; that match goes to History (FR-015, FR-021) |
| Get on the phone's match | Banner "Your iPhone is on Ada's match" → **Get on it** | 1 | No code typed (FR-016) |
| Leave | Menu → **Leave** → confirm | 3 | "Leave Ada's match? Your iPhone leaves too." (FR-022) |
| Join again | Menu or start screen → **Join again** | 1–2 | Shown while a kept code is unexpired and the watch is off that match (FR-024) |

**Status lines.** These appear on the court page beneath the score, and in full on the menu:

| Situation | Text |
|---|---|
| On the match, in step | (nothing beneath the score) · Menu: "On the host's iPhone" |
| Phone not reachable | "iPhone out of reach" (kept apart from the match line, FR-011) |
| Host out of reach | "Host out of reach since 20:41" (FR-007, FR-026) |
| Joining | "Looking for the match…" |
| Refused | "No match on 482 915 nearby" / "No room on this match" / "Bluetooth is off on your iPhone" / "Rekkert can't use Bluetooth: allow it in Settings" (FR-008) |
| Phone's app ended, watch standing in | "Your iPhone's app was closed: following on the watch" |
| Phone's app ended, watch can't reach host | "Open Rekkert on your iPhone" (FR-009) |
| Sharing stopped by host | "Ada stopped sharing. Saved in History." |

Only one status line fits beneath the score on the court page. When more than one applies,
the match comes first: "Host out of reach since…" outranks "iPhone out of reach". The menu
shows every line that applies (FR-011).

**Starting a match of its own while the phone is a guest**: a confirmation, "This takes your
iPhone off Ada's match." (FR-030)

## Notification that brings the watch (FR-027)

Posted by a guest's phone when it joins and its watch cannot be reached:

- Title: "You're on Ada's match"
- Body: "Tap to follow on your watch."
- A tap on the watch opens Rekkert on the match. A tap on the phone opens the match there.
- It is withdrawn once the watch is on the match.

## Phone

| Where | Change |
|---|---|
| Share sheet | Lists participants with their state, as on the watch. The phone count no longer counts a standing-in watch, and no longer claims "an older Rekkert" for it. |
| Sharing badge (host) | Shows "Not sharing: tap to share again on 482 915" when a kept code exists but hosting is down |
| Sharing badge (guest) | "Host out of reach since 20:41" while the host is gone |
| Settings → **Sharing record** | The merged record of the phone and its watch, newest first, with **Share** (see [sharing-record.md](sharing-record.md)) |
