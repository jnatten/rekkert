# Bug Assessment: The host marks guests out of reach between points, though their links are up

- **Slug**: host-loses-quiet-guests
- **Created**: 2026-11-15
- **Source**: pasted text, with the three sharing records it names
- **Verdict**: likely valid, needs reproduction. The symptom is plain in the host's record, and the guests' records rule out real absences. Half the cause is confirmed in the code. The other half, why the 1.1 guest said nothing between points, is not yet found.
- **Severity**: medium

## Report (verbatim or summarized)

> A 1.2 host (build 76) keeps losing track of guests, worst for a 1.1 guest. Friendly game 2026-11-14 10:01–12:00, host 57FA on 1.2 (76), guest B701 (Magnus) on 1.2 (76), guest 255B (Amandus) on 1.1 (75). [...] The host recorded 255B outOfReach 143 times (20.5 min) and B701 59 times (4.4 min). On 9 Nov, with the host on 1.1 and the same phones, it was 19 times (1.0 min) and 11 times (0.7 min). Neither guest's own record shows the host going out of reach, apart from Magnus once at the break (10:57–10:58). [...] Nobody noticed anything on screen during the game, but nobody can be sure. Spec 005 FR-015: nothing in this release may stop a 1.1 guest from following a match.

Records: `rekkert-sharing-2026-11-15_host.txt`, `..._guest_magnus.txt` and `..._amandus.txt`, exported on 15 Nov. The game is the 14 Nov entries.

## Symptom

On the host, a guest counts as out of reach after 15 s without being heard (`Participant.quietLimit`, FR-003, FR-010). During the game, the host recorded both guests out of reach again and again while their Bluetooth links stayed up and the guests themselves never lost the host. Expected: a guest whose link is up and who answers the host is never out of reach.

What the records show:

| | 255B (Amandus, 1.1) | B701 (Magnus, 1.2) |
|---|---|---|
| Times out of reach / time away | 143 / 20.5 min | 59 / 4.4 min |
| Back within 3 s after a point reached the host's phone | 96 of 143 | 29 of 59 |
| Gone out of reach 15–17 s after the last point | 48 of 144 | 5 of 60 |
| Episodes under 2 s | 36 | 42 |
| Bluetooth drops, either side | none | one, at the break |
| The guest's own record: host out of reach | never | once, 10:57:20–10:58:07, at the break |

- **Points:** all 264 were tapped on the host's watch, and no guest scored. The median gap between points was 20.5 s, and 82% of gaps were longer than 15 s.
- **Wi-Fi is not the cause.** From 11:08, 255B was on Bluetooth alone, and the host still lost it 74 times an hour, 15% of the time. While its Wi-Fi was still dropping, it was 71 times an hour.
- **Both guests at once.** 23 of B701's out-of-reach entries start in the same millisecond as 255B's. Each time, both come back together about a second later, usually just after the next point. Example: a point at 10:55:30.771; both out at 10:55:53.063; the next point at 10:55:53.327; both back at 10:55:54.07.
- **The host kept running.** The host's own once-a-second check was running all game: its battery entries land within about a second of every 10-minute mark. So these are not late checks after iOS had paused the app.
- **The score still reached Amandus.** 255B answered the host's push of every point, with what it held. So the score was reaching it, and FR-015's "follows the match" held. What is wrong is the host's picture of it, and every number built on that picture.

## Reproduction

From the records (done, 2026-11-15):

1. Take the host's 14 Nov entries. Pair each guest's `outOfReach` with the next `backInStep`, and line them up against `phone pair pointArrived` times.
2. Result: as in the table above. For 255B, most drop-outs start about 15 s after the last point and end just after the next one.

In the harness (not yet done):

1. Build a `CourtHarness` with the host and two guests: one on this build, and one with `actsAsOlderBuild = true`. The second joins on its watch, which hands over to its phone, as Amandus did (watch on the host at 10:02:38.808, handed over at 10:02:39.254). Let only the host's watch score, a point every 20 s, for 10 simulated minutes. Guests never tap.
2. Expected (bug): the guest on this build is recorded out of reach for a second or two at a time. This should show, because of the clock answers described under Root Cause Hypothesis.
3. The guest acting as 1.1 may **not** go out of reach in the harness. `actsAsOlderBuild` only leaves out the clock fields, and the simulated phone runs its 10-second check without a break. [NEEDS CLARIFICATION: what silenced the real 1.1 phone between points. See Root Cause Hypothesis, part 3.]

On devices: a host on this build and a guest on 1.1 (75), with phones locked and in bags. Score on the host's watch only, about one point every 20 s, for 10 minutes. Then export the host's record and count `guest … outOfReach`.

## Suspected Code Paths

- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:577` `noteParticipant` — the host marks a guest heard only when something **arrives from it** on a link: a hello, a guest card, its own `clock` question, events.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1639` `acknowledge(_:for:on:)` — the one answer that also counts: a guest's hello in reply to a push of points on one link (`deliver`, :1624). This is why guests come back just after each point.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1297` `askTheTime(on:)` and :1708 `learnClock` — the host asks each guest on this build the time every 30 s, per link. The answer only sets the clock bounds and does not count as hearing the guest.
- `Packages/RekkertKit/Sources/RekkertSync/Radio/RadioCore.swift:336` `sendLive(_:)` with `LinkReplies.isAcknowledgement` (`LinkReplies.swift:17`) — when the host asks every link at once, a hello reply counts as an acknowledgement and is not handed on as a packet. That does not count as hearing the guest either.
- `Packages/RekkertKit/Sources/RekkertSync/Radio/LinkLiveness.swift:9` and `RadioCore.swift:292` — a following guest speaks up only when its own writes on the link have been quiet for 10 s. Every write resets that: `liveness.sent` at `RadioCore.swift:538` and :551. That includes answers the host does not count.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1335` `watchParticipants` and `Packages/RekkertKit/Sources/RekkertCore/Sync/ParticipantState.swift:23` `quietLimit = 15` — the check that writes `outOfReach` / `backInStep`.
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift:1412` `consumeReachability`, with `cameOrWent` at :1433 — spec 005's D-6 (R-3). One link of several coming or going no longer starts a full round on every link. In 1.1, every guest's Wi-Fi drop started one, on the host and on that guest.

## Root Cause Hypothesis

1. **The host waits to be told (high confidence).** A guest that only follows is heard when it answers a push of points, or when it speaks on its own. Nothing else the host sends it counts. The host never asks a quiet guest whether it is still there. So as soon as two points are more than 15 s apart and the guest's own message doesn't arrive in between, the guest goes out of reach until the next point.
2. **On this build, the clock questions push the guest's own message back (medium confidence).** The host asks each guest on this build the time every 30 s on each link. The guest's answer is a write on its link, so it resets the guest's 10-second quiet timer, but the host doesn't count it as hearing the guest. For example: a point at 0 s is heard. A clock answer at 8 s is not counted, and moves the guest's own message to 18 s. The guest is out of reach at 15 s and back at 18 s. This fits B701's many episodes under 2 s. B701 still does better than 255B because it also asks the host the time every 30 s, and the host does count that.
3. **What silenced the 1.1 guest between points is not found (low confidence).** 255B's own 10-second message should reach the host. In 1.1 it sets off a full round (`synchroniseOnce`), and its hello is counted on arrival. The 1.1 code read for this assessment has no wait without a time limit that could block it. Candidates:
   - iOS kept the 1.1 app paused between Bluetooth wake-ups, so its timer never ran. Amandus's phone was very likely in his bag the whole match. 1.1 records no battery readings, so its record can't show whether it kept running. Magnus's 1.2 phone did keep running.
   - Something the host sends a 1.1 guest that it answers without being counted, as in part 2, which this assessment did not find.
   - Joining on the watch was ruled out as the cause. Amandus joined on his watch, which handed over to his phone a second later. In 1.1 and in this build, handing over only cuts the watch's links (`SharedSession.standDown`). It sends no leaving card, so it doesn't put the phone's link among the host's `departedLinks`, and that is the one thing that would make the host ignore the phone's own hello.

   Either way, a host that asks a quiet guest instead of waiting fixes it. So this need not be settled before the fix, but the harness test can only show the failure for the 1.1 guest if it can model whatever this turns out to be.
4. **Why 9 Nov looked fine (medium confidence).** 9 Nov is not a clean comparison: four guests, all on 1.1, with 282 Wi-Fi drops between them. In 1.1, each drop and each return made the host and that guest run a full round on every link. That traffic kept everyone heard. Spec 005's D-6 removed it on purpose (R-3), and with it the cover over gap 1.

## Proposed Remediation

**Preferred**: the host asks a quiet guest, rather than waiting for it.

1. In `watchParticipants`, or a loop beside it, find each guest that has gone 10 s unheard and still has a link up.
2. Send it the host's hello on one of its links, Bluetooth first.
3. Count the answer as hearing it, the way `greet` does: `handle(InboundPacket(payload: reply, link: link))`. Every build answers a hello, 1.0 and 1.1 included, so this covers older guests without changing them (FR-015).
4. Also count an answer to `askTheTime` as hearing that guest.

"Out of reach" then means "did not answer the host for 15 s", which is what FR-003 and FR-010 mean by it.

**Alternatives**:
- **Raise `quietLimit`.** Rejected: 15 s is the spec's definition (FR-003, FR-010). It would also be slower to show a guest who has really gone.
- **Change the guest.** Stop answers from resetting the guest's quiet timer, or make it speak every 10 s regardless. This helps guests on this build only. 1.1 guests in the field stay as they are, so it can only complement the preferred fix.
- **Have the transport mark a peer heard on any frame it receives, replies included**, and have the store read that. This is broader, but it changes `RadioCore`, `LocalNetworkTransport` and every test double.

**Files likely to change**:
- `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift`
- `Packages/RekkertKit/Tests/RekkertSyncTests/QuietGuestTests.swift` (new)
- `Packages/RekkertKit/Tests/RekkertSyncTests/CourtHarness.swift`, if a phone has to be able to pause for the 1.1 case
- `README.md`, the "How syncing works" lines on out of reach, if they say how a guest is heard

**Tests to add or update**:
- **`QuietGuestTests`**: the host, one guest on this build and one acting as 1.1. Only the host's watch scores, every 20 s, for 10 simulated minutes.
  - Neither guest is ever recorded `outOfReach`, and the session summary shows no unreachable time.
  - Each test must fail on today's code first. If the 1.1 case passes there, the harness is missing what silenced the real phone. That gap is itself the finding: write it down here, and extend the harness before going on.
- **A guest that really leaves** is still recorded `outOfReach` within 16 s, and `backInStep` within a second or two of coming back, so the fix doesn't hide real absences. `ResilienceTests` and `RejoinTests` may already cover this; check them.
- **Traffic budget**: `LinkChangeTrafficTests` and `deliveryDoesNotSnowball` still pass. Also add a check that a match where nobody scores for a few minutes sends each guest at most one hello every 10 s.
- **`BusyHallTests` and `ClubNightTests`**: FR-010's numbers do not get worse.

## Risks & Considerations

- **Bluetooth load.** A quiet break with nine guests means about one hello a second through the host's Bluetooth queue. That is the queue that scales worst (R-5). Ask only guests unheard for 10 s, on one link, and not while a push to them is in flight.
- **The fix must not slow real absences.** A guest that has truly gone must still show as out of reach at 15 s.
- **Records already taken stay wrong.** Records from before the fix overstate absences:
  - The summary's "unreachable" says 255B 20:37 and B701 4:26 for 14 Nov.
  - `Calibration.measure` (`Tests/RekkertSyncTests/Calibration.swift:55`) would replay every out-of-reach entry as the guest leaving and coming back: 202 false absences from this game alone.
  - `ArrivalConditions` throws out a guest's points for 30 s after each one.
  - T060 should not calibrate from a record taken before the fix. If one must be used, its absences need filtering against the guests' own records.
- **The host's screens.** The share sheet (`App/Sources/Views/ShareCodeSheet.swift:139`) and the watch's guest list (`WatchApp/Sources/Views/WatchGuestsView.swift:40`) turn a guest orange, "Out of reach since …", for these seconds. Nobody noticed during the game, but nobody can be sure these screens were open.
- **Old guests still won't be timed.** With this fix, a 1.1 guest will stop flickering on the host, but its delays still read unknown (FR-006).

## Open Questions

- Answered 2026-11-15: Amandus's phone was very likely in his bag the whole match, and he joined on his watch.
- [NEEDS CLARIFICATION: Were phones in bags on 9 Nov? This bears on whether that evening is any comparison at all.]
- Answered 2026-11-15: nobody noticed anything on screen, but nobody can be sure the share sheet or the watch's guest list was open.
- Should this ship before the T058 field run? Yes: otherwise that run's records carry the same false absences into calibration.
