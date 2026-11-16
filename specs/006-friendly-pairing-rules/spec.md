# Feature Specification: Pairing Rules for a Friendly

**Feature Branch**: `006-friendly-pairing-rules`

**Created**: 2026-11-16

**Status**: Draft

**Input**: User description: "We want a feature added to the friendly format where we can decide who plays together (or who does not play together) to make the matches even. For example if we have 4 players where 2 are good and 2 are bad we should be able to say that 2 arent going to play together."

## Clarifications

### Session 2026-11-16

- Q: When the bench leaves more of a keep-apart group on court than can be kept apart, what
  gives way — the even rotation of the bench, or the rule? → A: The bench stays as even as it
  is today; where several players are equally due to sit out, it picks the ones that let the
  rules hold. If no such bench exists, the round breaks as few rules as it can and the phone
  says which.
- Q: Can the rules be changed once the friendly has started? → A: Yes, from the phone's match
  menu. A change applies from the next round drawn; the round in play and the rounds before it
  never change.

## User Scenarios & Testing *(mandatory)*

### How a friendly draws its rounds today

A friendly is a group playing real matches on one court, re-partnered after every match. Four
or more play doubles; two or three play singles. Whoever is over the four seats sits the round
out, and the bench goes to whoever has sat out least. Among those on court, the draw puts
nobody with the same partner twice while a fresh partner is available and, after that, avoids
repeating match-ups. With exactly four players there are three ways to pair up; the first three
rounds use them all, and from then on they come round again in the order first drawn.

The draw knows nothing about how good anybody is, and it never reads the scores. With two
strong players and two weaker ones, one round in three puts the two strong players together
against the two weaker ones, and that round is rarely a match. Today nothing can stop it.

This feature lets whoever sets up the friendly say who must never be partners and who must
always be, so the rounds it draws are the even ones.

### User Story 1 - Keep two players apart (Priority: P1)

Four friends set up a friendly. Ada and Bob are clearly the strongest, so in setup the
organiser says Ada and Bob are never to be partners. Every round the draw then puts Ada and Bob
on opposite sides, each with one of the other two, and the two possible line-ups take turns.

**Why this priority**: this is the example that was asked for, and it is the smallest thing
that makes an uneven foursome play even matches.

**Independent Test**: Set up a friendly with Ada, Bob, Cy and Dan, keep Ada and Bob apart, and
play ten rounds. Ada and Bob are on opposite sides in all ten; the rounds alternate between
Ada & Cy vs Bob & Dan and Ada & Dan vs Bob & Cy, each line-up on the same sides every time it
comes round.

**Acceptance Scenarios**:

1. **Given** a friendly being set up with four players, **When** the organiser keeps two of
   them apart and starts, **Then** round 1 puts those two on opposite sides, and so does every
   round after it.
2. **Given** that friendly after round 1, **When** round 2 is drawn, **Then** it is the other
   allowed line-up, so each kept-apart player has a new partner.
3. **Given** that friendly after round 2, **When** round 3 is drawn, **Then** it is round 1's
   line-up again, same pairs on the same sides, and the rounds go on alternating.
4. **Given** the board at the end of any round, **When** it offers the next one, **Then** the
   partnership it names keeps the two apart.

---

### User Story 2 - Keep a group of strong players apart (Priority: P2)

Eight players turn up, four of them a level above the rest. Rather than naming every pair of
strong players, the organiser puts the four strong players in one keep-apart group. No two of
them are ever partners, so every team on court that has a strong player pairs them with one of
the others.

**Why this priority**: a keep-apart pair covers a foursome, but larger groups are where
uneven partnerships are hardest to avoid by hand, and listing every pair would take six rules
for four players.

**Independent Test**: Set up eight players with four of them in one keep-apart group and play
twelve rounds. No round has two of the four as partners, and nobody partners the same person
twice while an allowed fresh partner is on court.

**Acceptance Scenarios**:

1. **Given** a keep-apart group of three or more players, **When** a round is drawn with two
   of them on court, **Then** they are on opposite sides.
2. **Given** a keep-apart group, **When** rounds are drawn, **Then** among the line-ups that
   keep the group apart the draw still prefers fresh partners, then fresh match-ups, as it
   does today.
3. **Given** a keep-apart group and more players than seats, **When** several players are
   equally due to sit out, **Then** the draw benches the ones that leave no more than two of
   the group on court.
4. **Given** a round where every fair bench leaves three or more of the group on court,
   **When** it is drawn, **Then** it breaks as few rules as it can, and the phone says which
   players it could not keep apart.

---

### User Story 3 - Keep two players together (Priority: P2)

Two players are much weaker than the rest of the group, or a couple simply want to play on the
same side all evening. The organiser says the two are always to be partners. Whenever both are
on court they are on the same side, and the draw re-partners everyone else around them.

**Why this priority**: it is the other half of what was asked ("who plays together"), and it
uses the same setup, but most uneven groups are evened out by keeping players apart.

**Independent Test**: Set up six players with Cy and Dan always together and play eight rounds.
Every round with both Cy and Dan on court has them as partners; the other four rotate as usual.

**Acceptance Scenarios**:

1. **Given** two players kept together, **When** a round is drawn with both of them on court,
   **Then** they are partners.
2. **Given** two players kept together and one of them on the bench this round, **When** the
   round is drawn, **Then** the other plays with whoever the draw picks, as if the rule were
   not there.
3. **Given** exactly four players and two of them kept together, **When** rounds are drawn,
   **Then** every round is the same line-up on the same sides.

---

### User Story 4 - Change the rules during the evening (Priority: P3)

After a couple of rounds it is clear the matches are lopsided. The organiser opens the rules on
the phone, keeps the two strongest apart, and the next round drawn follows the new rule. The
round being played, and every round already played, stay exactly as they were.

**Why this priority**: an organiser often only sees who is stronger once play has started, but
setting the rules up front already covers the case that was asked for.

**Independent Test**: Start a friendly with no rules, play one round, add a keep-apart rule,
and draw the next round. The new round keeps the two apart; round 1 and its result are
unchanged on the phone and on the watch.

**Acceptance Scenarios**:

1. **Given** a friendly in progress, **When** the organiser opens the match menu on the phone,
   **Then** they can add, change and remove pairing rules there, under the same checks as in
   setup.
2. **Given** a rule changed while a round is in play, **When** the organiser returns to the
   board, **Then** the round in play is unchanged and the next round it offers follows the
   new rule.
3. **Given** a rule changed while a round is in play, **When** the change arrives on the watch
   or a guest's device, **Then** the round in play keeps its partnerships and the next round
   offered follows the new rule on every device.

---

### User Story 5 - The rules come back with the group's preset (Priority: P3)

The same group plays every Friday, and the same two are the strongest every week. The friendly
is saved as a preset with its rules; starting from the preset next week brings the players and
their rules back without setting them up again.

**Why this priority**: it saves a minute of setup a week for a regular group, but nothing is
lost without it.

**Independent Test**: Set up a friendly with a keep-apart pair and a keep-together pair, save
it as a preset, and start a new friendly from it. Both rules are there; removing one of the
players in the new setup removes them from their rule.

**Acceptance Scenarios**:

1. **Given** a friendly preset saved with pairing rules, **When** a friendly is started from
   it, **Then** the rules are set up as they were saved.
2. **Given** a preset whose rules name a player who is then removed from the list, **When** the
   friendly starts, **Then** that player is in no rule, and a rule left with fewer than two
   players is gone.

---

### Edge Cases

- **Singles.** Two or three players play singles and have no partners, so pairing rules have
  nothing to act on. Setup says so rather than offering rules that do nothing. If the list is
  cut to three during a friendly, the rules are kept but unused, and apply again if it grows
  back to four.
- **Rules that contradict each other.** The same two players kept both apart and together, one
  player kept together with two different people, or two players kept together who are also in
  the same keep-apart group. Setup does not accept these and says which rule clashes with which.
- **Rules that cannot hold with the players listed.** With four players, a keep-apart group of
  three cannot be kept: someone in it has to partner someone else in it. Setup says before the
  friendly starts that the rules cannot always be kept, and the friendly can still be started.
- **Rules the bench breaks.** With players sitting out, who is on court changes every round,
  and some benches leave more of a keep-apart group on court than can be kept apart. The bench
  stays as even as today, and only its tie-breaks lean towards the rules, so with five players
  and three of them kept apart, two rounds in every five break the rule (FR-006).
- **Four players and fewer allowed line-ups.** Four pair up in three ways. A keep-apart pair
  leaves two, a keep-together pair leaves one. The rounds cycle through whatever is allowed,
  in the order first drawn, same pairs on the same sides, just as all three cycle today.
- **A player is removed from the list.** They leave every rule they were in. A keep-apart
  group left with one player and a keep-together pair left with one player are dropped.
- **A name is corrected.** The rules follow the person, not the spelling: renaming Bob keeps
  Bob in his rules.
- **A late point.** Rules, like everything else the draw reads, never come from the scores, so
  correcting or undoing a point cannot change who partners whom in a round already drawn.
- **A device on an older Rekkert.** A guest's phone or watch on a version that predates pairing
  rules would draw without them. See FR-014.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Setting up a friendly with four or more players MUST let the organiser add
  pairing rules of two kinds: **keep apart**, naming two or more players, and **keep
  together**, naming exactly two.
- **FR-002**: A keep-apart rule MUST mean that no two of its players are partners in any round
  drawn while the rule stands. They may be opponents.
- **FR-003**: A keep-together rule MUST mean that its two players are partners in every round
  drawn while the rule stands in which both are on court. It MUST NOT by itself decide who
  sits out; when one of the two is on the bench, the other is drawn as if the rule were not
  there.
- **FR-004**: The draw MUST keep the rules ahead of its existing preferences. Among the
  line-ups that keep every rule, it MUST still prefer fresh partners, and then fresh
  match-ups, exactly as it does today.
- **FR-005**: A friendly with no pairing rules MUST draw exactly the rounds it would have drawn
  before this feature: the same benches, partners and sides, round for round, for the same
  session.
- **FR-006**: The bench MUST stay as even as it is today: it goes to whoever has sat out
  least. Where several players are equally due to sit out, the draw MUST pick a bench that
  lets every rule be kept, if one exists. If none does, the round MUST break the rules as
  little as it can: as few partnerships inside a keep-apart group, and as few keep-together
  pairs split up while both are on court, as the players on court allow.
- **FR-007**: When a round's line-up breaks a rule, the phone MUST say so where it offers that
  round, naming the players the rule could not keep apart or together.
- **FR-008**: With exactly four players, the draw MUST use each allowed line-up once before
  repeating any, and then cycle through them in the order first drawn, same pairs on the same
  sides. With no rules this is today's behaviour; a keep-apart pair leaves two line-ups that
  alternate, a keep-together pair leaves one that repeats.
- **FR-009**: Setup MUST NOT accept rules that contradict each other: the same two players
  kept apart and together, one player in two keep-together rules, or a keep-together pair
  inside a keep-apart group. It MUST say which rules clash.
- **FR-010**: Setup MUST tell the organiser, before the friendly starts, when the rules cannot
  be kept in every round with the players listed, and MUST still let the friendly start.
- **FR-011**: Rules MUST follow the person: correcting a player's name keeps them in their
  rules; removing a player takes them out of every rule, and drops any rule left with fewer
  than two players.
- **FR-012**: Every device on the friendly — the phone, its watch, and any guest — MUST draw
  the same round from the same events. The rules travel with the friendly, and the draw stays
  a function of the session, the round number, who has played with and against whom, and the
  rules; never of the scores.
- **FR-013**: The organiser MUST be able to add, change and remove pairing rules during the
  friendly from the phone's match menu, under the same checks as setup (FR-009, FR-010).
  A change MUST NOT alter any round already drawn, including the round in play; it applies
  to the rounds drawn after it, and to the next round the board offers.
- **FR-014**: A device on a version of Rekkert that predates pairing rules MUST NOT be left
  scoring a friendly with rules on partnerships other than the ones every up-to-date device
  shows. Keeping such a device out of a friendly that has rules, and telling it to update, is
  acceptable.
- **FR-015**: A friendly preset MUST save its pairing rules, and a friendly started from it
  MUST start with them, subject to FR-011 for any player removed before it starts.
- **FR-016**: Pairing rules MUST apply only to the Friendly format. Match, Winner court,
  Americano and Mexicano draw exactly as they do today.

### Key Entities

- **Pairing rule**: something the organiser has said about partners in a friendly. Either keep
  apart, with two or more players none of whom may partner each other, or keep together, with
  two players who partner each other whenever both play. Refers to players as people, so it
  survives a corrected name.
- **Friendly**: the session the rules belong to, alongside its players, scoring rules and
  rounds. Its rules are read by every draw made after they were set, and by none before.
- **Friendly preset**: a saved setup for a regular group; now also holds its pairing rules.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With four players and two of them kept apart, the two are on opposite sides in
  every round of a 20-round friendly, and the two allowed line-ups alternate.
- **SC-002**: An organiser who has entered four names can keep two of them apart and start the
  friendly in under 15 seconds.
- **SC-003**: For friendlies with no rules, from 2 to 12 players over 30 rounds, every round is
  identical to the one drawn before this feature.
- **SC-004**: In every friendly with rules played on a phone and its watch, with or without
  guests, all devices show identical partnerships for every round.
- **SC-005**: With eight players and a keep-apart group of four, no round in 30 has two of the
  group as partners, and nobody partners the same person twice while an allowed fresh partner
  is on court.
- **SC-006**: When a rule could not be kept, the phone said so on the round that broke it, in
  every case.
- **SC-007**: The next round is offered as promptly as it is today once a round ends, with up
  to 16 players and any rules.

## Assumptions

- Rules are about partners only. A friendly is played on one court, so two players who are
  not partners and are both on court are opponents; there is no separate rule about who faces
  whom.
- Rules are set up on the phone. The watch shows and plays the rounds the rules produce, but
  does not set or change them.
- The draw does not learn levels or ratings, and does not even teams up from scores: it reads
  no scores, which the project's convergence principle requires. Balancing by skill rating is
  out of scope.
- Rules are not shown in History or on the result screen; those keep showing the rounds as
  played.
- Picking the teams for one particular round by hand is out of scope; rules shape every draw.
- Sitting out keeps today's promise: the bench goes to whoever has sat out least. The rules
  only decide between players equally due to sit out (FR-006); a friendly with no rules breaks
  those ties as it does today (FR-005).
- Breaking older versions is acceptable for a friendly that has rules, in line with spec 005,
  so long as no device is left showing partnerships different from the others (FR-014).
