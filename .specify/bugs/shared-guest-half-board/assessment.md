# Bug Assessment: A guest's watch showed one half without its number, and once the same player on both sides

- **Slug**: shared-guest-half-board
- **Created**: 2026-11-23
- **Revised**: 2026-11-24, after the reporter said it was seen with the wrist raised
- **Source**: pasted text, two sharing records (`rekkert-sharing-2026-11-23_host.txt`, `rekkert-sharing-2026-11-23_magnus_bugged.txt`) and answers given during the assessment
- **Verdict**: likely valid, needs reproduction. The cause has not been found. What he described looks like the watch board part way through its own animation, but nothing here makes the board stay that way while the app is running.
- **Severity**: medium

## Report (verbatim or summarized)

> We encountered a bug today with session sharing.
>
> We did a americano session. Where multiple people joined. One on latest testflight (along with the host). And multiple on older versions.
>
> The one who joined on the latest testflight version got a bug where he could only see half the scoreboard.
> He also mentioned that one time one of the players were on both sides of the court.

Asked during the assessment:

- Where he saw it: **on his Apple Watch**, an Ultra 2 on the newest watchOS patch.
- What "half" looked like: "there was no number on the orange court on his watch. Maybe no names either. Not entierly sure".
- The player on both sides: **the host's phone showed the right teams at the same time**.
- His phone ran 1.2 (82) at `181886a` on iOS 27.2.1. Nobody looked at his phone while it happened.

Added on 24 November:

> he did see this with the wrist raised. it also didnt help to quit (not hardclose as that is no longer possible on the newest watchos) and reopen the app on the watch.

## Symptom

On a shared Americano, a guest's watch drew a court with no number on its orange half, with the wrist raised, and went on doing so after the app was left and opened again. At another moment it named one player on both sides of a court. The host showed the right teams throughout. Expected: the wrist shows both teams and both scores.

## What the records say

Both phones ran 1.2 (82). The match is `6078…`, shared 17:56 to 20:00, with six guests. The guest who saw it is `B701`.

- **No point was lost.** Both records hold 529 points. His watch took all 375 that were not its own, and scored the other 154.
- **His watch was not behind.** Its slowest hop from its phone was 3.43 s. Its link to its phone held from 17:57 to 20:06 without a drop.
- **His watch app never stopped working.** Points went on arriving at it in every ten minutes of the evening, so the app was not hung.
- **Nobody was turned away**, so nobody was marked as gone and no older build was kept off.
- **His watch did not relaunch** during the match.
- **He tapped points on his watch in four stretches**: 18:08 to 18:13, 18:21 to 18:41, 19:03 to 19:16 and 19:25 to 19:44. Between 18:42 and 19:02 it tapped one. The records cannot say whether that gap is a bench, somebody else scoring his court, or the fault.

The records note nothing about a draw or about what a board showed, and name only the phone's build.

## What was tried

All of it in scratch copies and on simulators made for it. Nothing here ran on a watch.

**Folding partial logs.** Six copies of one shared Americano, 8 to 13 players on 2 or 3 courts, each scoring, drawing, redrawing, cancelling and taking back against what it held, with events reaching the others late, doubled, out of order and with gaps. Each copy was folded as build 82 and again as a build that draws an Americano round itself.

- 6,312 folds. None had a court with an empty side, an unknown player, or a player in it twice.
- Copies holding the same events always showed the same teams.

So the data cannot produce what he saw, on build 82 or on an older build.

**The watch's build.** Nothing under `WatchApp/` or `Shared/` changed between build 79 (`3c81acc`, which he ran on 18 November) and build 82. A watch still on 79 would draw the board with the same code. It could fold other teams from a raced log, but it could not lose a number.

**The watch app playing by itself** (Apple Watch Ultra 49 mm simulator, watchOS 26.0). A two-court Americano with a bench, scored and drawn on a timer, with "I'm playing as" set and a workout starting part way in.

- 760 screenshots over some twenty-five rounds. Every one was a court split down the middle. The pages never came to rest between two courts.
- After every point, the number on the half that scored is a blur for the length of the animation. See `live-number-faint.png`.
- At every round change, the old names fade out while the new ones fade in, on both halves at once. For that moment a player who changes sides is named on both. The serve mark does the same.

**The app stopped part way.** With the app's process paused, the screen stays on the in-between frame: 13 of 40 screenshots taken 1.5 s after a pause still showed one (`paused-number-mid-roll.png`, `paused-round-change.png`). The app draws this animation itself, frame by frame.

**Whether the board ever stays that way while the app runs** (the board as it was at `181886a`, on watchOS 26.0 and on an Apple Watch Ultra 2 simulator on watchOS 27.2). Each trial let the game play, stopped it, and looked at the board nine seconds after the last change:

- with nothing else going on;
- with the app in the background for 17 s while points landed, then brought back;
- with the court pages changing while the standings page was on screen, then shown;
- with the pages following the wearer from court to court, and with the workout page in the deck.

18 of 18 trials came to rest on watchOS 26.0, and 18 of 18 on 27.2. Reduce Motion made no difference.

**Touch, on watchOS 27.2.** A UI test worked the board while points went on landing: 26 taps on the halves, 8 holds to undo, 15 colour swaps from the controls page and 21 moves between pages, some dragged only part way. All 108 screenshots of the board, each taken a second or more after a touch, were at rest.

So on a simulator, the board always finishes its animation while the app is running.

## Reproduction

Not reproduced.

What a simulator can show is the in-between frame, by pausing the app (`scripts/board-at-rest.sh` on the code before the fix: 6 of 30 at rest). What it cannot show is a board that stays there with the app running, which is what he saw.

[NEEDS CLARIFICATION: a screenshot or a photo of the watch the next time it happens. The side button and the crown pressed together take one.]

## Suspected Code Paths

As they stood at `181886a`:

- `Shared/ScoreButton.swift:64-69`: the number is drawn with `.contentTransition(.numericText())`, which blurs the old digit out and the new one in.
- `Shared/ScoreButton.swift:99`: `.animation(.snappy, value: value)` sits on the whole half, so the names and the serve mark animate with the number.
- `Shared/ScoreboardView.swift:46`: `.animation(.snappy, value: layout.isMirrored)` moves the two halves across each other when the board turns over.
- `WatchApp/Sources/Views/WatchCourtPage.swift:93-102`: the watch draws its board with these.

All of it has been there since `55803aa` (2026-09-11), and he used the same code on 14 and 18 November without this.

Ruled out:

- The links and the log: see the records and the first experiment.
- `Packages/RekkertKit/Sources/RekkertCore/Presentation/ScoreboardSnapshot.swift:222-263`: a side's number is `String(points)` and is never empty.
- `RoundPlacement.swift:22-35` and `RoundScheduler.swift:465-486`: no draw can put a player on both sides.
- `WatchApp/Sources/Views/WatchRootView.swift:150-169`: the court pages and `showMyCourt`, which never left a page out of place.
- `DisplayPreferences.adopting` and `HapticPreferences.adopting`: the colour swap and "I'm playing as" travel between phone and watch by a revision that only goes up, so the two cannot keep flipping each other.
- A lowered wrist and the Always On display: he saw it with the wrist raised.
- A 32-bit watch: an Ultra 2 is 64-bit.

## Root Cause Hypothesis

Not known. **Confidence: low.**

A half with no readable number, and a court naming a player on both sides, are both what this board looks like part way through an animation. Nothing else in the code or the data draws either. But the animation finishes within half a second whenever the app is drawing, on both watchOS versions tried, whatever was done to it.

That leaves two possibilities:

1. **On his watch that evening, the animation did not run to its end.** Something about the device rather than the app: the watch not resuming animations after Always On, Low Power Mode, or a fault in his watchOS patch. The board would then sit on the first frame of each change until the next one. This fits both things he saw, and fits him being the only one, but nothing here shows it.
2. **It was something else that only resembles this.** Then nothing found so far explains it.

## Proposed Remediation

**Preferred**: two steps, neither a known cure.

- **The watch board changes without animating.** Already applied (see `fix.md`). Each change is then one complete frame, so nothing can be held part way, whatever stopped the animation. If possibility 1 is right this cures it. If he sees it again on a build with this change, possibility 1 is wrong.
- **Make the next one decidable.** The sharing record names the watch's build, watchOS and model, and whether Low Power Mode and Reduce Motion were on, beside the phone's line (`LinkRecord.swift:288-296`). And he is asked for a screenshot when it happens.

**Alternatives**:

- Wait for a screenshot before changing anything. Nothing is risked by the change, though, and a build without animations is itself the test of possibility 1.

**Files likely to change**:

- `Shared/ScoreButton.swift`, `Shared/ScoreboardView.swift` (done)
- `Packages/RekkertKit/Sources/RekkertCore/Sync/LinkRecord.swift`, `Packages/RekkertKit/Sources/RekkertSync/LinkRecorder.swift` and the watch's side of the record, for the second step

**Tests to add or update**:

- `scripts/board-at-rest.sh` (done): the board paused at arbitrary moments has both its numbers.
- The record's export carries the watch's line and still reads records written before it.

## Risks & Considerations

- The change may not be the cure. It must not be read as one until he has played an evening on it.
- The wrist loses the rolling digit, which is the only sign that a point just landed besides the buzz.
- If the device stopped animating, other things on his watch that evening would have looked wrong too, in this app and in others. Nobody has said so.

## Found on the Way

Not this bug, but seen while looking:

- **Older builds can end up with other teams than build 82 from the same log.** Build 82 takes an Americano round as the draw carried it. Older builds draw it themselves, and land elsewhere when an undo, a cancel or a redraw crosses the draw. That happened in 14 of 40 heavily raced runs of the first experiment, and never when events arrived in order.
- **The record's first battery reading after a launch is stale.** His watch reads 95% at 17:56 and 80% ten minutes later, then loses 7% an hour. On 18 November it reads 100% and then 55% twenty-one minutes later. The summary's "watch 15%/h" comes from that first reading.
- **The host's own watch lost its phone 430 times** during the match and was opened afresh at 18:34 and 18:37.
- **The host's watch scored 18 points within about three seconds** at 19:02:41. If that was a round's result being tapped in, it is what it looks like; if not, something touched the screen.

## Open Questions

- [NEEDS CLARIFICATION: was the orange half there, in colour, with nothing on it? Or was that part of the screen showing something else?]
- [NEEDS CLARIFICATION: when in the evening, for how long, and did it put itself right? His watch tapped almost nothing between 18:42 and 19:02.]
- [NEEDS CLARIFICATION: while it looked like that, did a tap on that half still score?]
- [NEEDS CLARIFICATION: was Low Power Mode on, is Reduce Motion on, and did anything else on the watch look odd that evening?]
- [NEEDS CLARIFICATION: which watches the host and the other guests wear, and on which watchOS.]
