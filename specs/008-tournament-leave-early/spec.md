# Feature Specification: Leaving an Americano or Mexicano Early

**Feature Branch**: `008-tournament-leave-early`

**Created**: 2026-11-20

**Status**: Draft

**Input**: User description: "lets add a way to have someone leave early from a americano and a mexicano round"

## Clarifications

### Session 2026-11-20

- Q: Someone leaves mid-round from a court that already has points on it. What happens to that
  court? → A: It counts as it stands for all four, as a court confirmed as it stands does today,
  and the round closes once the other courts finish.
- Q: How is a player who left ranked against those who stayed? → A: By total points, like
  everyone else, with "left after round N" next to their name. The ranking itself is unchanged.
- Q: Can a player who left come back later in the evening? → A: Yes, at any time. They are drawn
  again from the next round. A newcomer joining a tournament under way stays out of scope.

## User Scenarios & Testing *(mandatory)*

### How a tournament copes with someone leaving today

An Americano or Mexicano is played over rounds on one or more courts. Every round, the draw
puts four players on each court and benches whoever is over: whoever has sat out least plays
next. Americano partners everyone with everyone; Mexicano re-ranks after every round and puts
the top four on court 1. The table ranks players by their points, plus a set number of points
for every round they sat out (half the target by default).

The player list is fixed once the tournament starts. When somebody has to go home at nine,
nothing in the app knows they are gone, and the draw keeps putting them on court. The only
way round it is to pick them to sit out by hand, round after round, before the first point.
Each time, that takes a bench seat from someone who wanted a rest. It also only works while
there are more players than seats, and it hands the absent player sit-out points for rounds
they were not there for. With exactly 4, 8, 12 or 16 players there is no bench at all, so
the organiser has to finish the tournament or play on a player short.

This feature lets the organiser say that a player has left. From the next round on, the draw
leaves them out, the bench and the courts fit the players who are still there, and the table
stops crediting the player who has gone.

### User Story 1 - Someone leaves between rounds (Priority: P1)

Nine players are playing an Americano on two courts, one sitting out each round. After round 4,
Eve has to go. The organiser opens Eve on the phone and marks her as gone. Round 5 is drawn
with the eight who are left: both courts full, nobody sitting out. Eve's points from rounds
1–4 stay hers, and she earns nothing more.

**Why this priority**: this is the case that was asked for, and the most common one: somebody
says goodbye while the next round is being called.

**Independent Test**: Start a nine-player Americano on two courts, play two rounds, mark one
player as having left, and draw the next five rounds. That player is in none of them. Nobody
sits out, since eight fill two courts. The player who left keeps exactly the points they had
after round 2.

**Acceptance Scenarios**:

1. **Given** a tournament between rounds, **When** the organiser marks a player as having
   left, **Then** the next round drawn leaves that player out of every court and the bench.
2. **Given** a player has left, **When** later rounds are drawn, **Then** that player is in
   none of them, and the bench and courts are sized for the players who are still there.
3. **Given** a player has left, **When** the table is shown, **Then** that player keeps every
   point and sit-out credit earned before leaving, and earns none after.
4. **Given** a Mexicano where a player has left, **When** the next round is drawn, **Then**
   the players still there are ranked and placed on courts as usual, as if the one who left
   had never been in the ranking.
5. **Given** an Americano where a player has left, **When** later rounds are drawn, **Then**
   among the players still there the draw keeps avoiding repeat partners as it does today.

---

### User Story 2 - Someone leaves while their court is playing (Priority: P1)

Halfway through round 6, Bob turns his ankle and can't go on. His court has been played to
9–7. The organiser marks Bob as having left. Bob's court stops at 9–7 and counts as it stands
for all four, as if it had been confirmed there. The round closes once the other court
finishes, and Bob plays no further rounds.

**Why this priority**: injuries and phone calls don't wait for a round to end, and a
round with a court that can't finish can't be closed today without cancelling it for
everybody.

**Independent Test**: In a two-court Americano, score court 1 to 9–7, mark one of its players
as having left, and finish court 2. The round closes, court 1 counts 9–7 for all four, and the
next round leaves the player out.

**Acceptance Scenarios**:

1. **Given** a round in play where nothing has been scored yet, **When** a player in it is
   marked as having left, **Then** the round is drawn again without them, as it is today when
   the bench is picked by hand.
2. **Given** a round in play where points have been scored, **When** a player in it is marked
   as having left, **Then** nobody else's partner, opponent, court or score in that round
   changes, on any device.
3. **Given** a round in play where a player has left from a court with points on it, **When**
   they are marked as having left, **Then** that court stops where it stands and counts as it
   stands for all four players on it, as a confirmed court does.
4. **Given** that round, **When** the other courts are played out, **Then** the round closes
   and the next one can be drawn, without cancelling the round for anyone.
5. **Given** a player marked as having left while sitting a round out, **When** the round
   ends, **Then** the round counts for everyone else as usual, and the player keeps the
   sit-out credit for that round.

---

### User Story 3 - Fewer players change the shape of the evening (Priority: P2)

Eight players are playing on two courts when one leaves. Seven can't fill two courts, so
from the next round one court is played and three sit out. Before the organiser confirms,
the phone says what the evening becomes. If so many leave that four are no longer there,
the phone says no more rounds can be drawn and offers to finish.

**Why this priority**: leaving one player out is the core. Saying beforehand what it costs
the rest is what stops the organiser being surprised by a round on one court.

**Independent Test**: In an eight-player, two-court tournament, mark one player as having
left. Before confirming, the phone says the next rounds will be played on one court with
three sitting out. After confirming, the next round is drawn that way.

**Acceptance Scenarios**:

1. **Given** the confirmation of a player leaving, **When** it would change how many courts
   are played or how many sit out each round, **Then** the phone says so in numbers before the
   organiser confirms.
2. **Given** a tournament with a Length set to a number of rounds, **When** a player leaves,
   **Then** the number of rounds planned does not change.
3. **Given** an Americano played to a full rotation, **When** a player leaves, **Then** the
   rotation counts only the partnerships among the players still there, and the courts screen
   shows the new count left.
4. **Given** a tournament left with fewer than four players, **When** the organiser looks at
   it, **Then** no further round can be drawn, and the phone says so and offers to finish.

---

### User Story 4 - The table and History say who left (Priority: P2)

At the end of the evening, the table still lists Eve. It shows that she left after round 4,
so nobody mistakes her place for a bad night. History and the Players page show her rounds
as played, like everyone else's.

**Why this priority**: the result is what people talk about afterwards. A player who went
home early shouldn't look like they lost every round they missed, nor be quietly dropped from
a result they helped make.

**Independent Test**: Finish a tournament in which one player left after round 4. The final
table and the History entry both show that player, the round they left after, and the points
they earned. Their per-round average on the Players page counts only the rounds they played.

**Acceptance Scenarios**:

1. **Given** a player who left, **When** the table is shown during or after the tournament,
   **Then** that player appears with the round they left after.
2. **Given** a player who left, **When** players are ranked, **Then** they are ranked by total
   points like everyone else, under the same tie-breaks as today. The only difference is the
   label.
3. **Given** a finished tournament with a player who left, **When** it is opened in History,
   **Then** it shows the same table and the same "left after round N" as at the end.
4. **Given** a player who left, **When** their record is opened on the Players page, **Then**
   only the rounds they played count towards their average and share of points.

---

### User Story 5 - Coming back (Priority: P3)

The organiser marks the wrong player, or Eve comes back after an hour away. Either way, the
organiser brings her back on the phone, at any point in the evening, and she is drawn again
from the next round.

**Why this priority**: mistakes happen on a busy court, and some people step out rather than
go home. Without it, a wrong tap would cost a player the rest of the evening.

**Independent Test**: In a nine-player Americano, mark a player as having left after round 2,
play rounds 3 and 4 without them, bring them back, and draw round 5. They are in round 5, they
earned nothing for rounds 3 and 4, and no round already played changes.

**Acceptance Scenarios**:

1. **Given** a player marked as having left, **When** the organiser brings them back at any
   point before the tournament is finished, **Then** the next round drawn includes them again.
2. **Given** a player marked as having left by mistake, **When** they are brought back before
   another round is drawn, **Then** the next round is drawn as if they had never been marked.
3. **Given** a player brought back after missing rounds, **When** the bench is chosen, **Then**
   they are not sent straight back to the bench, nor kept off it, because of the rounds they
   missed.
4. **Given** a player brought back after missing rounds, **When** the table is shown, **Then**
   the rounds they missed earn them nothing, and the label says which rounds they missed (for
   example "away rounds 3–4") instead of "left after round 2".
5. **Given** a player brought back, **When** the confirmation is shown, **Then** it says how
   many courts will be played and how many will sit out from the next round, as when leaving.

---

### Edge Cases

- **The last four.** Down to exactly four, every round is one court with nobody sitting out.
  Below four, no round can be drawn (Story 3).
- **Several leave at once.** A group that came together goes home together. Marking several
  players in one go gives the same rounds as marking them one by one.
- **A sit-out picked by hand.** Before the first point of a round, the bench can be picked by
  hand. A player who has left is never offered in that pick, and can't be benched.
- **A round already drawn but not yet started.** Leaving redraws it, as picking the bench does
  today (Story 2, scenario 1).
- **Their court has no points yet, but another court does.** The round can no longer be drawn
  again, so the court of the player who left counts as it stands, 0–0, for all four. The
  confirmation says so before the organiser confirms.
- **The round in play is cancelled afterwards.** It counts for nobody, as today. The player who
  left is still gone from the next round.
- **The finish offer.** A Length reached on the rounds already played still offers to finish
  once, as today. Leaving never finishes a tournament by itself.
- **Winner court and ladder tournaments.** These are out of scope. Their players change courts
  by results, and leaving there raises different questions.
- **A shared tournament.** Every phone and watch following it shows the same player as gone,
  from the same round, and draws the same next round. A device whose version can't follow this
  is handled as an older device is for pairing rules: the host's phone says before confirming
  that it will be taken off, and it is never left drawing a different round.
- **Undo.** Undoing the last point never brings back a player who left (FR-012).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The phone MUST let a player in an Americano or Mexicano be marked as having left,
  from the tournament screen, at any time before the tournament is finished.
- **FR-002**: Only a phone that may run rounds MUST be offered this: the host and guests with
  Full access, as with picking the bench. Guests with Only score or Read-only access MUST NOT
  be offered it, and the watch MUST NOT offer it.
- **FR-003**: Marking a player as having left MUST ask for confirmation. The confirmation MUST
  name the player and, where it changes, say how many courts will be played and how many will
  sit out each round from then on.
- **FR-004**: Every round drawn after a player has left MUST leave them out of every court and
  the bench, and MUST size the courts and the bench for the players still there.
- **FR-005**: A player who has left MUST keep every point, point against, round played and
  sit-out credit earned before leaving, and MUST NOT earn sit-out credit or anything else for
  rounds after it.
- **FR-006**: A round in play where nothing has been scored MUST be drawn again without the
  player who left, as when the bench is picked by hand.
- **FR-007**: A round in play where points have been scored MUST keep every other player's
  partner, opponent, court and score. The court of the player who left MUST stop where it
  stands and count as it stands for all four players on it, as a confirmed court does. The
  round MUST close once the other courts are played out, without cancelling it for anyone.
- **FR-008**: In Mexicano, the ranking that places players on courts MUST leave out players
  who have left. In Americano, the draw MUST keep its rules against repeat partners and repeat
  opponents among the players still there.
- **FR-009**: A Length of a set number of rounds MUST be unchanged by a player leaving. A full
  rotation MUST count only the partnerships among the players still there, and the courts
  screen MUST show the updated count.
- **FR-010**: With fewer than four players left, the tournament MUST NOT draw another round, and
  the phone MUST say why and offer to finish.
- **FR-011**: The table, on the phone, the TV board and the finished tournament in History,
  MUST show every player who left, with the round they left after, or, for a player who came
  back, the rounds they missed. Everyone MUST be ranked by total points under today's
  tie-breaks, whether they left or not.
- **FR-012**: Undoing points MUST NOT undo a player leaving. Bringing a player back MUST be a
  separate action on the phone, offered to the same phones as FR-002, at any time before the
  tournament is finished. It MUST include them from the next round drawn, and a player brought
  back before another round is drawn MUST be drawn as if they had never been marked.
- **FR-013**: Every device following the tournament MUST show the same players as having left,
  from the same round, and MUST draw identical rounds. No round already played or in play may
  change for anyone other than the player who left (Principle II).
- **FR-014**: A device that cannot follow a tournament with a player who has left MUST NOT draw
  rounds that differ from the others'. Before confirming, the host's phone MUST say how many
  devices on an older Rekkert will be taken off, as it does for pairing rules.
- **FR-015**: The Players page MUST count only the rounds a player actually played towards
  their per-round average and share of points.
- **FR-016**: The bench MUST treat a player who came back neither as owed a rest nor as owed a
  game because of the rounds they missed.

### Key Entities

- **Departure**: a player's leaving a tournament: who, and the round from which they no longer
  play. Part of the tournament's shared history, so every device agrees on it.
- **Return**: a player who left being brought back: who, and the round from which they play
  again.
- **Player status in a tournament**: playing, or away from a given round, possibly until a
  given round. The draw, the bench, the length and the table read it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Marking a player as having left takes the organiser no more than three taps from
  the tournament screen, and under 15 seconds.
- **SC-002**: In 100% of rounds drawn after a player has left, that player is on no court and
  not on the bench. Checked over every player count from 5 to 16, on 1 to 4 courts, in both
  formats.
- **SC-003**: The player who left has exactly the same points and sit-out credit at the end of
  the tournament as when they left.
- **SC-004**: Two phones and a watch following the same tournament show identical rounds,
  benches and tables after a player leaves, within 5 seconds of each draw.
- **SC-005**: Over a full rotation of the players still there, an Americano with someone who
  left repeats no partner more often than an Americano started with that many players would.
- **SC-006**: No round played before the player left, and no score in the round in play other
  than on their own court, changes on any device.

## Assumptions

- "Round" in the request means the evening's Americano or Mexicano as a whole, and the
  request covers players who leave both between rounds and during one.
- Only Americano and Mexicano are in scope. Winner court and ladder tournaments, friendlies
  and single matches are not.
- A newcomer joining a tournament already under way is out of scope. Only players in the
  tournament from the start can leave and come back.
- Leaving is marked on the phone only. The watch shows its effect (the player gone from the
  rounds) but doesn't offer it, as with picking the bench.
- Sit-out credit stays as it is for everyone else. A player still there earns it only for
  rounds they are benched, and the bench may shrink or vanish once someone leaves.
- Devices on older versions are kept off rather than allowed to diverge, as was done for
  pairing rules (spec 006). The exact mechanism belongs to the plan.
- The player's name stays in the tournament and its History entry. Leaving removes them from
  the draw, not from the record.
