# Research: Pairing Rules for a Friendly

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

The spec left nothing marked for clarification. This file records what the code does today
(R-1 to R-11), read at `0d4ff41b`, and the decisions the plan rests on (D-1 to D-13).

## What the code does today

### R-1 · The friendly draw

`FriendlyScheduler.nextRound(for:)` (`RekkertCore/Friendly/FriendlyScheduler.swift`) builds a
`PairingHistory` from every round's teams and bench, seeds a `SeededGenerator` on the session id
and the round index, and then:

1. **Two players**: same two, same sides, every round.
2. **Exactly four, after all three line-ups have been played**: `replayedTeams` replays the
   line-up played least, ties going to the one first drawn, sides and all.
3. **Otherwise**: `RoundScheduler.split` picks the bench, and then either the two left play
   singles, or `PairingSearch.teams(from:courts: 1, history:)` pairs the four.

`FriendlyTests` pins exact draws by name for five players over nine rounds, and for four
players' first three rounds. The draw depends on the order of the player list and the seed, not
on the player ids, because the shuffle permutes list positions.

### R-2 · The bench

`RoundScheduler.split` shuffles the list with the seeded generator, then sorts it by sit-out
count ascending, ties keeping the shuffled order. The first `players − seats` sit out. So the
players who *must* sit out are those with fewer sit-outs than the last bench place. Among those
on the boundary count, the shuffle alone decides who sits. Friendlies use the default
`.fewestSitOuts` order and never pass `chosen`.

### R-3 · The line-up search

`PairingSearch` (in `RoundScheduler.swift`) is greedy, then up to four passes of a swap-two-
players local search. Its cost is `100 × repeated partnerships + 1 × repeated opponents`. For
one court of four, every other partition is one swap away, so the local search always reaches
the cheapest partition. Americano uses the same search on several courts.

### R-4 · Where a draw is made, and what can move it

The draw is not carried on the wire for a friendly. Each device folds
`nextRound(after:at:sitOuts:placed:)` into a call to `FriendlyScheduler.appendingRound` inside
`SessionReducer`. The log is ordered by Lamport stamp and device id
(`MatchEvent`), and the state is a pure fold over it (`SessionReducer.state(of:)`). So an event
recorded concurrently with a draw, on another device, can sort before the draw and change what
it folds to.

For a friendly that is harmless today: the draw reads only teams and benches, which no point
can change. A setup correction (`configure`) racing a draw could already re-partner it, but the
app never sends one for the player list mid-session. Once rules can change mid-session, a rule
change racing a draw becomes an everyday case. Ladders and Mexicano met the same problem and
solved it with `placed: RoundPlacement`: the round as the drawing device worked it out, taken as
it is when it fits.

### R-5 · Changing a friendly mid-session

`MatchStore.setChangeEnds` records `.configure(.friendly(session))` with the whole session,
bypassing `MatchStore.configure` (which would reset the board). The reducer's
`(.friendly(incoming), .friendly(var session))` branch adopts only `name`, `rules` and
`players`, and keeps the id and the rounds. `.configure` is not undoable (`isUndoable`), and
`ShareAccess.score` may not undo it either.

### R-6 · How a friendly is encoded

`FriendlySession` uses synthesized `Codable`; `FriendlyRound` has a hand-written decoder that
reads new fields with `decodeIfPresent`. A synthesized decoder ignores keys it does not know.
So **an older build reading a friendly with rules silently drops them and draws without
them**.

### R-7 · Sharing and older builds

- `Wire.sharingProtocol` is `2` (spec 005). `hello` and `GuestCard` carry it, and 1.1 sends
  neither.
- The host keeps `olderDevices` and `currentDevices` as sets: "no protocol" against "some
  protocol". It does not keep the number.
- `Wire.needsUpdate` exists, and 1.2 guests show it plainly on the phone and the watch
  (`NeedsUpdateTests`). No host sends it yet; `refusesAsNeedingUpdate` is a test switch. Spec
  005 D-14 added it for "a later breaking change", and this is that change.
- 1.1 cannot read `needsUpdate`. The only refusal 1.1 understands is `noRoom`.
- Sharing is a star: guests reach each other only through the host (README, "a guest can time a
  point another guest tapped through the host"). A host-side gate therefore covers every guest.
  A guest's watch goes through its own phone.

### R-8 · Presets and setup

- `PresetConfiguration.friendly(name:players:rules:)` uses synthesized enum `Codable`. Optional
  associated values are read with `decodeIfPresent`, as `configure`'s `at:` and `warmup:`
  already rely on.
- `makeSetup()`, used by `MatchStore.start(_:)` from Home and from the watch, mints fresh player
  ids (`Player(name:)`) and a fresh `FriendlyID`.
- `NewSessionView(editing:)` keeps the preset's players and their ids. `start()` builds the
  `FriendlySession` with a fresh `FriendlyID()` at the moment of starting.

### R-9 · The friendly screens

- `FriendlyMatchView.upNext` shows `session.nextDraw()` to every phone; only the Start button
  is gated on `canRunRounds`.
- The `bench` line sits under the board while a round is in play.
- `MatchOptionsMenu` holds the mid-match corrections. The change-ends picker is the precedent
  for a `canRunRounds`-only setting.

### R-10 · The watch

The watch folds the same log through the same reducer, so it draws what the phone draws. It
shows the next round's names and can start it, and it starts friendlies only from a preset
(`WatchRootView` → `MatchStore.start(_:)`). It has no friendly setup.

### R-11 · Words that describe the draw

- README › Friendly: "The draw puts nobody with the same partner twice while a fresh pairing is
  available".
- `ModeHelp` › friendly: "Nobody partners the same person twice while a new pairing is left."
- README › Who may do what lists what *Only score* may not do.

## Decisions

### D-1 · A pairing rule is a value on the friendly (FR-001 – FR-003, FR-011)

- **Decision**:
  - A new `PairingRule` in `RekkertCore/Friendly/PairingRules.swift`: an id, a kind (`apart` or
    `together`), and the players it names, kept sorted.
  - `FriendlySession.pairingRules: [PairingRule]` is decoded with `decodeIfPresent`, and
    **encoded only when it is not empty**. A friendly without rules is byte-for-byte what it is
    today.
  - Pure helpers on `[PairingRule]` cover the rest: the conflicts (FR-009), pruning to the
    players listed (FR-011), and the rules that apply to the players on court.
- **Rationale**:
  - Principle I: the rules live in the engine.
  - An empty array omitted on the wire keeps every existing log, snapshot, history record and
    older-build exchange unchanged.
  - Sorted members make equal rules encode to equal bytes, the same habit as `ShareAccessTable`.
- **Alternatives considered**:
  - Rules as a separate event stream: rejected, because the reducer would need a new event kind
    that older builds read as `.unrecognised` and ignore. That is no better than D-9's gate,
    and more to build.
  - Skill levels on players: out of scope by the spec's assumptions.

### D-2 · Where the rules enter the draw (FR-004 – FR-006, FR-008)

- **Decision**: rules touch the draw in exactly three places, and only when some rule applies to
  the players involved.
  1. **The bench's tie-break** (D-3).
  2. **The line-up's cost.** `PairingSearch` compares `(rule breaks, today's cost)` in order,
     rather than a weighted sum. A partition that breaks fewer rules always wins, and among
     equals today's partner-then-opponent cost decides. With no rules every partition scores
     zero breaks, so each comparison resolves as it does today.
  3. **The four-player cycle.** `replayedTeams` replays among the *allowed* line-ups: the
     partitions with the fewest rule breaks under the rules in force. With no rules that is all
     three, which is today's `seen.count == 3`. Every round played counts toward "played least",
     including rounds before the rules last changed, as clarified.
- **Rationale**:
  - FR-004 asks for rules first, then today's preferences, which is what the ordered comparison
    gives.
  - A weighted sum cannot do that safely: four players kept together for 60 rounds already run
    up a partner cost of 12 000.
  - FR-005 then holds by construction. A comparison that adds a component which is always zero
    resolves as it did before.
- **Proof of FR-005 (SC-003)**: before the draw is touched, a fingerprint test captures every
  round drawn for 2 to 12 players over 30 rounds on today's code, by name. It must pass
  unchanged afterwards (Principle III). The existing pins in `FriendlyTests` and
  `SeededDrawTests` stay as they are.
- **Alternatives considered**:
  - Exhaustive search over the three partitions for one court: equivalent for a friendly, but it
    would fork the search the friendly shares with Americano. The ordered cost keeps one search,
    and the extra term is always zero for Americano (FR-016).

### D-3 · The bench's tie-break (FR-006)

- **Decision**:
  - Split the sorted list from R-2 into the players who must sit out (strictly fewer sit-outs
    than the boundary), the boundary group, and the rest.
  - From the boundary group, take every way of filling the remaining bench places, in the
    shuffled order: lexicographic by shuffled position, so the first combination is today's
    choice.
  - Keep the first whose players on court have a line-up that keeps every rule.
  - If none does, keep the one whose best line-up breaks the fewest, ties going to the earliest
    combination.
- **Rationale**:
  - The bench stays exactly as even as today, because only the boundary choice moves.
  - With no rules the first combination always passes, and it is today's bench (FR-005).
  - The worst case for SC-007's 16 players is C(16, 12) = 1 820 combinations, each checking
    three partitions of four. The search is bounded, deterministic and fast.
- **Alternatives considered**: the rejected options from the spec's clarification, which let the
  rules or the bench win outright.

### D-4 · A round remembers what it could not keep (FR-007)

- **Decision**:
  - `FriendlyRound.unkept: [UnkeptRule]` lists, at the moment the round is drawn, each pair the
    line-up puts together against a keep-apart rule, and each keep-together pair split while both
    are on court.
  - It is encoded only when it is not empty. The scheduler fills it in, and so does the reducer
    when it takes a carried round (D-5).
  - The notice under the board reads it from the round in play; the up-next notice reads it from
    `nextDraw()`.
- **Rationale**:
  - FR-013 says a rule change never alters a drawn round, and the notice should follow the same
    rule: the round in play is judged by the rules it was drawn under.
  - Every device reaches the same list, since it is a function of the fold.
- **Alternatives considered**: judging the round in play against the rules as they are now.
  Rejected: adding a rule mid-round would then flag a round that was drawn fairly.

### D-5 · A friendly draw carries where it put everybody (Principle II with FR-013)

- **Decision**:
  - `MatchStore.nextRound()` records `placed: RoundPlacement` for a friendly too: one "court"
    and the bench, as the drawing device worked it out.
  - The reducer takes it as it is when it fits: each listed player exactly once, the right
    number a side for singles or doubles, and the bench the right size. If it does not fit, the
    round is drawn as today.
  - `RoundPlacement` gains a friendly reading beside its tournament one.
- **Rationale**:
  - A rule change (D-6) that sorts before a concurrent draw would otherwise re-partner a round
    people have walked onto. That is R-4's race, and Principle II forbids it.
  - Ladders and Mexicano already work this way, and older builds already ignore a `placed` they
    do not need. With no rules, `placed` is exactly what every device would draw anyway.
- **Alternatives considered**: ordering rule changes after draws. Rejected: the log has no such
  ordering, and inventing one is a change to the reducer's core.

### D-6 · Changing rules mid-session (FR-013, US-4)

- **Decision**:
  - `MatchStore.setPairingRules(_:)` records `.configure(.friendly(session))` with the new rules,
    as `setChangeEnds` does, and the reducer's correction branch adopts `pairingRules` beside
    `name`, `rules` and `players`.
  - It is allowed when `canRunRounds` and, on a guest, only when the host speaks protocol 3 or
    later (D-9).
  - Because `.configure` is not undoable, no Undo ever takes a rule change back. That satisfies
    FR-013's ban on offering one to Only score, and Full access too, consistently.
- **Rationale**: it is the existing mechanism for exactly this kind of correction. There is no
  new event kind for older builds to ignore, and no new undo semantics.
- **Alternatives considered**: a new `EventKind.setPairingRules`. Rejected per D-1.

### D-7 · The forecast (FR-010, SC-008)

- **Decision**:
  - `FriendlyScheduler.forecast(for:)` copies the session, draws one full rotation forward, and
    counts the rounds whose `unkept` is not empty, naming their players.
  - A full rotation is `n / gcd(n, n − 4)` rounds for five or more players, and the number of
    allowed line-ups (D-2) for exactly four. It is nil for singles, where rules do not apply.
  - **Setup fixes the `FriendlyID` when the form opens** and starts the friendly with that same
    id, so the forecast draws exactly the rounds the friendly will (SC-008).
  - Mid-session, the rules editor forecasts from the session as it stands, its rounds included.
- **Rationale**:
  - The draw is a pure function of the session and never reads a score, so playing it forward
    is exact while players and rules stay unchanged.
  - Without a fixed id, setup would forecast one seed and the friendly would play another.
- **Alternatives considered**:
  - A static rule ("a keep-apart group bigger than two can break"). Rejected: it cannot give the
    count the clarification asked for, and it is wrong for eight players with four kept apart,
    who never break (SC-005).

### D-8 · Checking and pruning rules (FR-009, FR-011)

- **Decision**:
  - `PairingRules.conflicts(in:)` returns each clash, naming both rules: the same pair kept apart
    and together; one player in two keep-together rules; a keep-together pair inside a
    keep-apart group.
  - The editor will not save while any clash stands. The engine also ignores a clashing set if
    one arrives anyway, from a modified build, by treating it as no rules.
  - `pruned(to: players)` removes missing players and drops rules left under two. Setup applies
    it whenever the list changes, and the draw applies it again defensively.
- **Rationale**: the checks are pure and testable on macOS, and the views only render them.

### D-9 · Older builds (FR-014)

- **Decision**:
  1. `Wire.sharingProtocol` goes to **3**. The host keeps each device's protocol number, not
     only "older or current".
  2. **While the friendly has rules, the host turns away every guest below 3**, both at its
     hello and at the moment rules first appear with such a guest on. A protocol-2 guest gets
     `needsUpdate`, which 1.2 already shows on the phone and the watch. A 1.1 guest gets
     `noRoom`, the only refusal 1.1 can read. In both cases the link is refused.
  3. **A guest offers the rules editor only if its host speaks 3 or later.** An older host
     could not draw with them.
  4. **The host's rules editor says how many phones on the match will be turned away** before
     the change is saved.
- **Rationale**:
  - FR-014 allows keeping older devices out, and spec 005 built the refusal for this.
  - The gate is at the hub of a star (R-7), so no older guest can see a friendly with rules.
- **Known limits**:
  - **1.1 says the match is full**, not that it needs updating. Its wording cannot be changed
    from here.
  - **A watch app lagging its phone's update.** The watch app ships inside the iPhone app and
    installs with it, but if it has not yet, it would draw without rules on the wrist. Scores
    still land on the right sides, because points are addressed by round and side; only the
    names differ. This is accepted as a narrow, transient risk and recorded in plan.md. It is
    not designed around.
- **Alternatives considered**: carrying the whole drawn round so older builds take it as it is.
  Not possible: older builds already ignore `placed` for a friendly (R-4).

### D-10 · Presets (FR-015)

- **Decision**:
  - `PresetConfiguration.friendly` gains `pairing: [PairingRule]? = nil`, saved when it is not
    empty.
  - `makeSetup()` mints fresh player ids as today, but maps each rule's members through the
    old-to-new id map, and then prunes.
  - `NewSessionView(editing:)` loads the rules with the players, whose ids it already keeps.
  - The preset summary line gains "· 2 rules" when there are any.
- **Rationale**: an optional associated value reads old presets unchanged (R-8), and remapping is
  the only way rules can survive the fresh ids.

### D-11 · Screens (FR-001, FR-007, FR-009, FR-010, FR-013)

- **Decision**: one `PairingRulesEditor` view serves both setup and the mid-session sheet, with:
  - a list of rules;
  - Add Keep apart and Add Keep together;
  - a player picker per rule;
  - the clash messages (D-8);
  - the forecast line (D-7);
  - on the host, mid-session, the turned-away count (D-9).

  The friendly setup gets a Pairing section below Players. It says "Pairing rules apply when four
  or more play doubles" and offers nothing below four. The match menu gets **Pairing rules…**
  for phones that may edit. The up-next block and the line under the board gain the notice.
  Wording is in [contracts/screens.md](contracts/screens.md).
- **Rationale**: one editor means one set of checks on screen, matching FR-013's "same checks as
  setup".

### D-12 · Words (R-11)

- **Decision**:
  - README › Friendly gains a paragraph on pairing rules.
  - README › Who may do what adds pairing rules to what *Only score* may not change.
  - `ModeHelp` gains one bullet: "Keep players apart or together to even the matches."
- **Rationale**: the README is the project's runtime guide (constitution, Governance).

### D-13 · The watch (R-10)

- **Decision**: no watch UI changes. The watch draws with the rules through the shared reducer,
  shows the names the rules produce, and starts presets with their rules (D-10). It shows no
  notice, per the clarification.
- **Rationale**: the spec keeps rules editing on the phone, and watchOS 10 needs no new API for
  any of this.
