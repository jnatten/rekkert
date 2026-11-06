# Contract: What the Screens Ask and Offer

**Feature**: [../spec.md](../spec.md) · **Builds on**: [spec 001's watch UI contract](../../001-fix-session-sharing/contracts/watch-ui.md)

"Ada" stands for the host's name. With no name given, the text reads "the host" ("The host"
at the start of a sentence). Taps are counted the way spec 001 counts them. All text is
English literals in the views, as today.

## The questions and notices

### End of match, host (FR-001 – FR-007)

| | Phone (alert over the result, or over Home if there is no result) | Watch (in place of **Done** on the result) |
|---|---|---|
| Title | "Keep sharing for the next match?" | "Keep sharing?" |
| Message | "3 people are on. They get your next match unless you stop." · with nobody on: "Nobody is on yet." | "3 on" · "Nobody on yet" |
| Buttons | **Keep sharing** (default) · **Stop sharing** (destructive, no second confirmation, FR-003) | **Keep sharing** · **Stop sharing** |
| Watch can't reach the phone on Stop | | "Can't reach your iPhone", and nothing changes. The question stays (FR-007). |

Stop sharing is one tap from the result (SC-003).

### End of match, guest (FR-008 – FR-012)

| | Phone (alert over the result, or over Home) | Watch (in place of **Done** on the result) |
|---|---|---|
| Title | "Stay for Ada's next match?" | "Stay for Ada's next match?" |
| Message | "Ada is keeping it shared." once the host has said Keep · otherwise: "If you stay, Ada's next match comes here." | Only the "keeping it shared" line, when it applies |
| Buttons | **Stay** (default) · **Leave** (destructive) | **Stay** · **Leave** |

If the host stops sharing first, this is replaced by the stop notice below.

### The host's next match arrives (FR-012, FR-013)

| | Phone | Watch |
|---|---|---|
| Form | Alert over the new match. Scoring is off until it is answered. | Full-screen alert with a `.notification` wrist tap, following the haptics setting. Scoring is off until it is answered. |
| Title | "Ada started a new match" | "Ada started a new match" |
| Message | "You're on it. Leave if you're done for the evening." | |
| Buttons | **OK** (default) · **Leave** (destructive) | **OK** · **Leave** |

OK on either device closes it on both (FR-013). From the end of one match to scoring the
next is one tap: **OK**.

### The notification (FR-027)

Posted by a guest's phone when the host's next match arrives while the phone's app is not
active and its watch is not reachable:

- Title: "Ada started a new match"
- Body: "Tap to open it."
- It shows on the watch when the phone is locked. A tap opens Rekkert on the new-match alert
  on whichever device it was tapped on.
- It is withdrawn once the alert is answered on either device.
- If notifications are not allowed, the alert is there the next time Rekkert is opened.

### Sharing stopped

| Situation | Phone | Watch |
|---|---|---|
| Host stopped, seen by a guest (existing) | "Ada stopped sharing" · "The match as it stood is saved in History." | "Ada stopped sharing. Saved in History." |
| Stopped after 30 minutes, seen by a guest (new) | "Ada's sharing has ended" · "Nobody had a match on for 30 minutes. Your matches are in History." | "Ada's sharing ended after 30 minutes without a match." |
| Stopped after 30 minutes, seen by the host (new) | "Sharing stopped" · "Nobody had a match on for 30 minutes, so Rekkert stopped sharing. Share again to carry on." | "Sharing stopped after 30 minutes without a match." |

## Between matches: the phone's Home ("Play together" section)

| This phone is… | Rows | Taps |
|---|---|---|
| Not sharing, not on anyone's | **Share** ("Others at the court follow and score your matches until you stop") · **Join a match** (as today) | Share → code sheet: 1 |
| Hosting | "Sharing on 482 915" ("3 on · until you stop") → code sheet · **Stop sharing** → confirm "Stop sharing? Everyone else stops following your matches." | Code: 1 (SC-005) · Stop: 2 |
| A guest, waiting | "On Ada's sharing" ("Waiting for Ada's next match") · **Leave** → confirm "Leave Ada's sharing? Your watch leaves too." | Leave: 2 (SC-004) |
| Left, with a kept code | **Join again** (no code typed) beside **Join a match** | 1 |

The section's footer reads: "Everyone at the court sees the same scoreboard and can score it.
Sharing lasts until it's stopped, or until 30 minutes go by with no match on."

The host-only rows show only on the host's phone, and Leave only on a guest's (FR-017,
FR-019).

## Between matches: the watch's start screen (top card)

| This watch's phone is… | Card | Taps |
|---|---|---|
| Not sharing | **Share** → the code page once the phone is sharing · "Can't reach your iPhone" otherwise | 1, then the code shows |
| Hosting | "Sharing · 3 on" · **Code** · **Stop sharing** → confirm | Code: 1 (SC-005) · Stop: 2 |
| A guest, waiting | "On Ada's sharing" · "Waiting for the next match" · **Leave** → confirm "Leave Ada's sharing? Your iPhone leaves too." | Leave: 2 (SC-004) |

**Quick match** and the presets stay below the card.

## Starting a match while sharing (FR-020, FR-021)

| Where | Host | Guest, waiting |
|---|---|---|
| `NewSessionView` | A line above **Start**: "Shared with 3 on 482 915" | **Start** asks: "Start your own match? This takes you off Ada's sharing." · **Start anyway** / **Cancel** |
| Presets on Home | The sharing section sits above them and says "Sharing on …" | Same confirmation as above |
| Watch start screen | The card says "Sharing · 3 on" above Quick match | Existing confirmation (spec 001 FR-030), now worded "This takes your iPhone off Ada's sharing." |

## Wording that moves from "this match" to "sharing" (FR-022)

| Where | Today | After |
|---|---|---|
| Match menu (phone) | "Share this match" · "Share this match again" | "Share" · "Share again" |
| Share sheet title | "Share this match" | "Sharing" |
| Share sheet's Stop | "Stop sharing" | Unchanged. Its confirmation, where there is one, uses the line below. |
| Watch Stop confirmation | "Stop sharing? Everyone else leaves this match." | "Stop sharing? Everyone else stops following your matches." |
| Watch Leave confirmation | "Leave Ada's match? Your iPhone leaves too." | "Leave Ada's sharing? Your iPhone leaves too." |
| Watch match menu | "Share match" | "Share" |

## Accessibility (FR-023)

- The alerts are system alerts, and read as such.
- Each card and row has one combined VoiceOver label. Examples:
  - "Sharing on 4 8 2 9 1 5, 3 on."
  - "On Ada's sharing, waiting for the next match."
- Digits are read one by one, as on spec 001's code page.
- Every new row uses the scaled fonts already used on Home and the watch idle screen
  (`scaledFont`), and wraps rather than truncates at the largest sizes.
