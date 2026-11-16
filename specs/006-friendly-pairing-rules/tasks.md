---

description: "Task list for Pairing Rules for a Friendly"
---

# Tasks: Pairing Rules for a Friendly

**Input**: Design documents from `specs/006-friendly-pairing-rules/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required. Principle III asks for engine tests first. In every phase the test tasks
come first, and **must fail for the stated reason before that phase's implementation**. The one
exception is T002, the no-rules fingerprint, which is written green on today's code and must
stay green through every later task (FR-005, SC-003).

**Organization**: Tasks are grouped by user story, in the spec's priority order (US1 P1; US2
and US3 P2; US4 and US5 P3), so each story can be built, tested and shipped on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: The user story the task belongs to (US1–US5, as in spec.md)
- Paths are from the repository root. Some are shortened:

  | Short | Full path |
  |---|---|
  | `RekkertCore/` | `Packages/RekkertKit/Sources/RekkertCore/` |
  | `RekkertSync/` | `Packages/RekkertKit/Sources/RekkertSync/` |
  | `CoreTests/` | `Packages/RekkertKit/Tests/RekkertCoreTests/` |
  | `SyncTests/` | `Packages/RekkertKit/Tests/RekkertSyncTests/` |

- `R-n` and `D-n` are the findings and decisions in research.md. Find code by the function
  named, not by line number.
- SwiftPM picks up new files in existing targets, and Tuist globs `App/Sources/**`, so new files
  need no package or project changes.
- All UI text comes from `PairingText` (T011–T012), which builds every sentence in
  [contracts/screens.md](contracts/screens.md). Views never compose rule wording themselves.
- Run `swift test --package-path Packages/RekkertKit --filter FriendlyNoRulesFingerprint` after
  every task that touches `RekkertCore/Friendly/` or `RekkertCore/Tournament/`. If it goes red,
  that task broke FR-005: fix the task, never the fingerprint.

### Glossary

The same idea goes by different names in the spec and in the code. They are one thing:

| Spec (user-facing) | Code and research |
|---|---|
| line-up (who partners whom, and the sides) | partition (of the four on court), with its sides |
| a round that breaks a rule | a round whose `unkept` is not empty (`UnkeptRule`) |
| the setup warning | the forecast (`PairingForecast`) |
| organiser | whoever sets up, or any phone with Full access once shared (`canEditPairingRules`) |

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A known-good baseline

- [X] T001 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh` on `b8bc5a72`, which is `0d4ff41b` plus docs, and confirm both pass. Any failure found here is not this feature's, and must be raised with the user before going on.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**:
- the FR-005 guard;
- the rule types and their stored fields;
- the sentences;
- the protocol bump;
- keeping every older build off a friendly with rules (FR-014): guests at the host, and a
  phone's own lagging watch at its phone.

Every story needs these, and the gates make even the MVP safe to share.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Pin today's draw, **before any draw code changes**.
  - **Move the helpers.** Move the `private` helpers at the top of `CoreTests/FriendlyTests.swift` into a new `CoreTests/FriendlyTestSupport.swift` as `internal`: `makeFriendly(players:id:rules:)`, `draw(_:rounds:)`, `partnerCounts`, `opponentCounts`, `benchCounts`, `drawn(_:)` and `partition(_:)`. `FriendlyTests` must compile and pass unchanged.
  - **Write the fingerprint.** Write `CoreTests/FriendlyNoRulesFingerprintTests.swift` (`@Suite("A friendly without rules draws as it always has")`). It holds one parameterised test over `2 ... 12` players that draws 30 rounds with `makeFriendly(players:)` (default id `…0000A1`) and compares `drawn(session)` with a pinned `[String]` literal per player count.
  - **Generate the literals.** Get them by temporarily printing `drawn(...)` on today's code, and paste them in verbatim. Delete the printer.
  - **Done when** the suite is green on today's code (SC-003).
- [X] T003 [P] Write `CoreTests/PairingRulesTests.swift` (`@Suite("Pairing rules")`). It fails to compile until T004–T005. Cover each of these:
  - **wellFormed**: `.apart` with 1 player or a duplicate is not well formed. `.apart` with 2 or 3 is. `.together` with exactly 2 is; with 3 it is not. Members are stored sorted whatever order they are given in.
  - **conflicts** (FR-009), one test per reason, each naming both rule ids:
    - `sameTwoBothWays`: P0 and P1 kept apart, and P0 and P1 kept together.
    - `twoPartnersForOne`: P0 with P1 together, and P0 with P2 together.
    - `togetherInsideApart`: P0 and P1 together, with P0, P1 and P2 kept apart.

    Two overlapping keep-apart groups are **not** a conflict.
  - **pruning** (FR-011), via `pruned(to:)`:
    - a removed player leaves every rule;
    - a keep-apart group of three that loses one stays as two;
    - a group of two that loses one is dropped;
    - a keep-together pair that loses one is dropped;
    - renaming a `Player` keeps the same `PlayerID` in the rule.
  - **breaks** (data-model "A set of rules"):
    - an `.apart` pair who are partners gives `UnkeptRule(kind: .apart, players: [a, b])`;
    - an `.apart` pair on opposite sides gives nothing;
    - a `.together` pair split while both play gives `UnkeptRule(kind: .together, …)`;
    - a `.together` pair with one on the bench, so absent from the teams, gives nothing.
  - **activeRules**: empty below four players; empty when the rules clash; pruned otherwise.
  - **rulesKeyIsStated** (research D-1):
    - a `FriendlySession` made by this build writes the `pairingRules` key even when it is empty;
    - JSON without the key, as an older build wrote it, decodes with `statedPairingRules == nil` and `pairingRules == []`;
    - a `FriendlyRound` with no `unkept` writes no `unkept` key, and older JSON decodes to `[]`;
    - a session with rules, and a round with `unkept`, round-trip equal.
- [X] T004 Create `RekkertCore/Friendly/PairingRules.swift` per data-model.md and contracts/engine-api.md:
  - `PairingRule`: `id: UUID`, `kind: Kind` (`.apart`/`.together`, raw `"apart"`/`"together"`), `players: [PlayerID]` "Sorted ascending, so equal rules encode to equal bytes". `isWellFormed` encodes "`.apart` needs two or more distinct players" and "`.together` needs exactly two distinct players".
  - `UnkeptRule` (`kind`, `players`: exactly two, sorted).
  - `PairingConflict` (`rules: [UUID]`, `reason`).
  - `PairingForecast` (`rounds`, `breaking`, `unkept: [UnkeptRule]`).
  - On `Array where Element == PairingRule`:
    - `conflicts`;
    - `pruned(to:)`;
    - `breaks(_ teams: BySide<[PlayerID]>) -> [UnkeptRule]`, in a deterministic order: by kind, then players;
    - an internal `breakCount(_:)` that sums breaks over several courts' teams.

  Everything is public where the engine API lists it.
- [X] T005 In `RekkertCore/Friendly/FriendlySession.swift`:
  - **The session's rules.**
    - Add the stored `var statedPairingRules: [PairingRule]?`, where `nil` means "written by an older build".
    - Add the public computed `pairingRules: [PairingRule]`: get returns `statedPairingRules ?? []`; set states it.
    - Add an `init` parameter `pairingRules: [PairingRule] = []` that *states* it, so every session this build makes states its rules.
    - Add `public func leavingPairingRulesUnstated() -> FriendlySession`, a copy with `statedPairingRules = nil`. A correction that is not about the rules (T036's `setChangeEnds`) uses it, so as not to restate them.
    - Add `activeRules` (pruned to `players`; empty when `players.count < 4` or when `conflicts` is not empty).
  - **Its coding.** Give `FriendlySession` a hand-written `init(from:)` that reads key `pairingRules` with `decodeIfPresent` into `statedPairingRules`, and an `encode(to:)` that writes it whenever it is not nil, an empty list included. Every other key is written exactly as the synthesized code did.
  - **The round's record.** Add `unkept: [UnkeptRule]` (default `[]`) to `FriendlyRound`'s init, `CodingKeys` and decoder (`decodeIfPresent ?? []`). Add a hand-written `encode(to:)` that omits it when empty.
  - **Done when** T003 passes and the T002 fingerprint stays green.
- [X] T006 [P] Add `aFriendlyWithRulesReadsAsOneWithoutOnAnOlderBuild` to `CoreTests/WireCompatibilityTests.swift`. Decode a `FriendlySession` with rules through a test-local copy of the pre-feature shape (a `Decodable` struct with the `0d4ff41b` fields only), and assert that it decodes with nothing to say about rules. This documents R-6, the reason for the gates.
- [X] T007 Bump the protocol and track it per device.
  - **In `RekkertCore/Sync/Wire.swift`**: set `Wire.sharingProtocol = 3`, and update its doc comment to "3 from spec 006 (pairing rules)".
  - **Per-device protocol.** In `RekkertSync/MatchStore.swift`, keep each device's protocol in a new `peerProtocols: [DeviceID: Int]`, filled where `hello` sets `olderDevices`/`currentDevices`, the pair's hello included (`nil` → 1). Leave those sets working as they do.
  - **Keep the pair's across relaunches** (U2). Persist the paired device's protocol beside `pairedDevice` in `persist()` and the store's restore. Read it back into `peerProtocols[pairedDevice]` on launch. A relaunched phone then knows its older watch before that watch says hello.
  - **A test switch.** Add a test-only `@ObservationIgnored var speaksProtocol: Int?` beside `actsAsOlderBuild`. When set, `ownProtocol` returns it, so a phone or a watch can stand in for 1.2 (protocol 2).
  - **Check old assumptions.** Grep the tests for a literal `2` used as the protocol, and fix any to `Wire.sharingProtocol`.
- [X] T008 [P] Write `SyncTests/PairingRulesAdmissionTests.swift` (`@Suite("Older builds stay off a friendly with rules", .serialized) @MainActor`).
  - **A harness helper.** Add `startFriendly(players: [String], rules: (([Player]) -> [PairingRule])? = nil)` to `SyncTests/CourtHarness.swift`. It configures `.friendly(FriendlySession(...))` on the host's phone and then calls `nextRound()`, as `NewSessionView.start()` does.
  - **Guests** (each fails today, because nobody is turned away):
    - `aProtocolTwoGuestIsToldToUpdate`: four players, P0 and P1 apart, shared; a guest with `speaksProtocol = 2` joins. Its phone reaches `sharing.phase == .failed(.needsUpdate)` within 15 s, and its record has `.refused(.needsUpdate)`. Model it on `NeedsUpdateTests`.
    - `aOneOneGuestIsTurnedAway`: the same with `actsAsOlderBuild = true`. Within 15 s the guest is refused as `noRoom`, and the host lists no such guest.
    - `aCurrentGuestJoins`: the same with a default guest, which joins and draws what the host draws.
    - `rulesArrivingTakeOlderGuestsOff`: a protocol-2 guest is on a rules-free friendly. The host starts a new friendly with rules (spec 004: the host's next match reaches its guests), and the guest is turned away with `needsUpdate`.
    - `withoutRulesOlderGuestsStay`: a protocol-2 guest is on a rules-free friendly of five players. It stays on through five rounds and holds the same `rounds[i].teams` as the host.
  - **The host's own watch** (C1; each fails today, because the watch is sent everything). Use a `CourtHarness` with the host's watch set to `speaksProtocol = 2`:
    - `anOlderWatchIsHeldBackAndThePhoneSaysSo`:
      1. Start a friendly with P0 and P1 apart.
      2. Within 5 s the phone's `pairNeedsUpdateForRules` is true.
      3. Draw three rounds on the phone. The watch's store never holds a friendly whose `pairingRules` is not empty, and never more rounds than it had when the rules appeared.
      4. Relaunch the phone, the way `CourtHarness` relaunches an app (U2), and draw another round before the watch says hello. The watch still receives nothing of the friendly, and `pairNeedsUpdateForRules` is true as soon as the phone is back.
    - `anOlderWatchFollowsAFriendlyWithoutRules`: with no rules, `pairNeedsUpdateForRules` stays false, and the watch holds the phone's rounds within 5 s of each draw.
    - `theWatchCatchesUpOnceUpdated`:
      1. Start as `anOlderWatchIsHeldBack…`.
      2. Set the watch's `speaksProtocol = nil` and have it say hello again, as a relaunch after updating would.
      3. Within 10 s the watch holds every round and the rules, and `pairNeedsUpdateForRules` is false.
- [X] T009 Implement the host's gate in `RekkertSync/MatchStore.swift` (contracts/wire-protocol.md, "Sharing scope"; D-9 items 1–4).
  - **At hello.** In `handle(_:)`, beside the `refusesAsNeedingUpdate` check, if `role == .host`, the packet is a non-pair `hello`, the state is a friendly with non-empty `activeRules`, and the sender's protocol is below 3: reply `.needsUpdate(sessionID:)` for protocol 2, or `.noRoom(sessionID:limit:)` for no protocol. Then `transport.refuse(link)`, insert into `refusedLinks`, note `.refused(.needsUpdate)`, and return.
  - **When rules appear.** In `refresh(to:)`, when a host's state goes from no active rules to some, do the same for every linked guest below 3, found through `linkOwners` and `peerProtocols`, and `participants.remove(_:)` each.
  - **The count.** Add `public var olderGuestsTurnedAwayByRules: Int`: on a host, the number of distinct linked guest devices (not their watches) below protocol 3; zero elsewhere.
- [X] T010 Hold a friendly with rules back from an older own watch, in `RekkertSync/MatchStore.swift` and `RekkertSync/FanOutTransport.swift` (D-9 item 5; contracts/wire-protocol.md, "Pair scope").
  - **The flag.** Add `public private(set) var pairNeedsUpdateForRules = false` to `MatchStore`. Recompute it in `refresh(to:)`, on launch (from the persisted protocol, T007), and whenever the pair's `hello` is heard. It is true when this store is the phone (`keepsHistory`), `peerProtocols[pairedDevice]` is known and below 3, and the session in play is a friendly with non-empty `activeRules`.
  - **One choke point in the transport** (U1).
    - Add `holdSessionFromPair(_ holding: Bool)` to `PeerTransport` (in `RekkertCore/Sync/Wire.swift`), declared on the protocol (a member only in an extension dispatches statically through `any PeerTransport`), with a default that does nothing, so every other transport is untouched.
    - On `FanOutTransport`, store it under its lock. While it is true, skip the `.pairedDevice` child (the scope with `isPairedDevice`) for `.events` and `.snapshot` payloads, in `sendLiveBesideLinks`, `sendLive`, `queue` and `publishSnapshot`.
    - `publishSnapshot` still updates `lastSnapshot` and every link-carrying child, because other phones read that cache. Only the watch's application context is left as it was.
    - `MatchStore` sets the switch whenever `pairNeedsUpdateForRules` changes.
  - **The reply to the watch's hello.** In `handle(_:)`, a `hello` that `isFromPairedDevice` is answered with `ownHello` instead of `.events` while the flag is true, so the watch is never left hanging.

    Links to other phones are untouched.
  - **The release.** When the flag turns false (an update, or the rules gone), send the pair what it is missing, as after any gap. Answering its next hello, or a `requestSnapshot`, is enough if that is how the code already catches it up.
  - **Done when** T008 passes in full.
- [X] T011 [P] Write `CoreTests/PairingTextTests.swift` (`@Suite("Pairing wording")`). It holds one test per sentence in contracts/screens.md §1–§4b, with Ada, Bob, Cy and Dan:
  - **rule rows**: "Ada and Bob apart", "Ada, Bob and Cy apart", "Cy and Dan together", names in list order;
  - **the three conflict sentences**;
  - **forecast**: apart-only, together-only and mixed; `breaking == rounds` gives "in any round with these players"; nil when `breaking == 0`;
  - **unkept**: both kinds, `offered: true` and `false`;
  - **turnedAway**: nil for 0, singular for 1, plural for 2;
  - **watchNeedsUpdate**: exactly "Update Rekkert on your Apple Watch to follow this friendly there."
- [X] T012 Create `RekkertCore/Presentation/PairingText.swift`, a `public enum PairingText` with `rule`, `conflict`, `forecast`, `unkept(_:in:offered:)`, `turnedAway` and `watchNeedsUpdate`, as in contracts/engine-api.md. Names are joined "Ada and Bob" or "Ada, Bob and Cy" in the order of `session.players`, and a missing player reads as `session.name(_:)` does ("—"). **Done when** T011 passes.

**Checkpoint**: Rules exist and are stored, every sentence is built, and no older device (a guest, or a phone's own watch) can hold a friendly with rules. Nothing draws with them yet. The fingerprint is still green.

---

## Phase 3: User Story 1 - Keep two players apart (Priority: P1) 🎯 MVP

**Goal**: In setup, keep two players apart; every round puts them on opposite sides, and with
four players the two allowed line-ups alternate, sides and all.

**Independent Test**: Ada, Bob, Cy and Dan, with Ada and Bob kept apart, over ten rounds. They
are on opposite sides every time, and the rounds alternate between the two line-ups, each on the
same sides whenever it comes round.

### Tests for User Story 1 ⚠️ (write first; they must fail)

- [X] T013 [P] [US1] Write `CoreTests/FriendlyPairingDrawTests.swift` (`@Suite("A friendly draws with its pairing rules")`), using `FriendlyTestSupport` with `pairingRules` set on the session. Each fails today because the rules are ignored:
  - `fourWithTwoApartAlternate`: 20 rounds with P0 and P1 apart (SC-001). P0 and P1 are never on one side. `rounds[k].teams == rounds[k % 2].teams` for every k, and the two partitions differ. Every `unkept` is empty.
  - `aPairApartIsAlwaysKept` (arguments 5…12 players): 30 rounds with P0 and P1 apart. They are never partners, and `unkept` is always empty. With four on court a pair can always be split.
  - `singlesIgnoreRules` (2 and 3 players): rounds with a rule equal rounds without it.
  - `clashingRulesDrawAsNone` (D-8): five players with a clashing set draw exactly as with none.
- [X] T014 [P] [US1] Write `SyncTests/FriendlyPairingSyncTests.swift` (`@Suite("Pairing rules across devices", .serialized) @MainActor`) with `phoneAndWatchDrawTheSameWithRules` (SC-004).
  - Use `CourtHarness` with the host's watch and `startFriendly` (T008) with six players and P0 and P1 apart.
  - Play 12 rounds. Each round: one point, then `endRound()`, then `nextRound()`, alternating which device draws.
  - Within 5 s of each draw, the phone and the watch hold equal `rounds.map(\.teams)` and `rounds.map(\.unkept)`, and P0 and P1 are never partners.

  It fails today because the rules are ignored.

### Implementation for User Story 1

- [X] T015 [US1] Make the line-up search rule-aware in `RekkertCore/Tournament/RoundScheduler.swift` (D-2).
  - Give `PairingSearch.teams(from:courts:history:)` a `rules: [PairingRule] = []` parameter.
  - In `improve`, accept a swap only when `(rules.breakCount(candidate), cost(candidate))` is lexicographically below the current pair. Use an ordered comparison, never a weighted sum.
  - Do not change `greedyTeams`, `cost` or the Americano and Mexicano callers (FR-016).
  - With `rules` empty every comparison resolves as before. Run the fingerprint and `SeededDrawTests`.
- [X] T016 [US1] Make the friendly draw rule-aware in `RekkertCore/Friendly/FriendlyScheduler.swift` (D-2, D-4).
  - **The line-up.** Pass `session.activeRules` to `PairingSearch.teams`.
  - **The four-player cycle.** Generalise `replayedTeams`: the *allowed* partitions are those of the three with the fewest `activeRules` breaks. Replay only once every allowed partition has been played, choosing among allowed ones the least played, ties going to the first drawn, with its sides. With no rules, allowed is all three, which is today's `seen.count == 3`.
  - **The round's record.** Factor the `FriendlyRound(...)` construction into an internal `makeRound(index:teams:sitOuts:in:)` that also stamps `unkept: session.activeRules.breaks(teams)` (`[]` in singles). T034 reuses it.
  - **Leave alone** the two-player path and the singles path.
  - **Done when** T013 passes, and the fingerprint, `FriendlyTests` and `SeededDrawTests` stay green.
- [X] T017 [US1] Create `App/Sources/Views/PairingRulesEditor.swift` (contracts/screens.md §1–§2; D-11):
  - **The section.** `PairingRulesSection`, bound to `[PairingRule]`, given the named `[Player]` and an optional `PairingForecast`.
    - Below four players it shows only the footer "Pairing rules apply when four or more play doubles."
    - Otherwise it shows a row per rule (`PairingText.rule`, swipe to delete, tap to edit) and a **Keep players apart…** row.
  - **The rule sheet.** `PairingRuleSheet`, titled "Keep apart", has a checklist of the players with the keep-apart footer from screens §2, and Done is disabled below two ticked.
  - Give both a `kind` parameter, so US3 adds Keep together without restructuring.
- [X] T018 [US1] Wire setup in `App/Sources/Views/NewSessionView.swift` (D-7, D-11):
  - add `@State private var friendlyID = FriendlyID()` and `@State private var pairingRules: [PairingRule] = []`;
  - put `PairingRulesSection` in `friendlySections`, directly below `playersSection(footer: friendlyFooter)`;
  - prune the rules whenever the named players change (`pairingRules = pairingRules.pruned(to: namedPlayers.map(\.id))`);
  - in `start()` for `.friendly`, build `FriendlySession(id: friendlyID, …, pairingRules: pairingRules)`.
- [X] T019 [US1] In `App/Sources/Views/FriendlyMatchView.swift`'s `footer`, show `PairingText.watchNeedsUpdate` above the bench line when `model.store.pairNeedsUpdateForRules` (screens §4b): footnote, secondary, with `Image(systemName: "applewatch.slash")`, on that phone only.

**Checkpoint**: US1 is fully usable: set up a keep-apart pair and play. A lagging watch is held back with a clear line. The fingerprint is still green.

---

## Phase 4: User Story 2 - Keep a group of strong players apart (Priority: P2)

**Goal**: A keep-apart group of three or more. The bench, as even as today, leans towards the
rules on ties. Rounds that cannot keep the group apart say so on every phone, and setup
forecasts how often.

**Independent Test**: Eight players with four of them in one keep-apart group, over twelve
rounds. No two of the four are partners, and nobody repeats a partner while an allowed fresh one
is on court.

### Tests for User Story 2 ⚠️ (write first; they must fail)

- [X] T020 [P] [US2] Add to `CoreTests/FriendlyPairingDrawTests.swift`:
  - `eightWithFourApart` (SC-005): 30 rounds, with P0–P3 apart.
    - No two of P0–P3 are ever partners.
    - Whenever a round repeats a partnership, every rule-keeping partition of those four on court also repeats one: enumerate the three partitions.
  - `benchStaysFair` (FR-006): for 5…12 players, with P0–P2 apart, sit-out counts never differ by more than one after any round.
  - `tieBreakLeansTowardsTheRules` (FR-006, edge case "Rules the bench breaks"): five players with P0–P2 apart, over ten rounds.
    - Exactly four rounds have a non-empty `unkept`.
    - Each of those holds one `.apart` pair from P0–P2.
    - In the other six, P0–P2 never partner.
  - `fourWithThreeApartFlagsEveryRound`: four players with P0–P2 apart. Every round has a non-empty `unkept`, and the rounds cycle all three line-ups as `FriendlyTests.fourPlayersReplayTheFirstThreeRoundsInOrder` expects.
  - `sixteenPlayersDrawPromptly` (SC-007): 16 players with P0–P7 apart. 30 rounds take under 0.5 s on `ContinuousClock`.
- [X] T021 [P] [US2] Write `CoreTests/PairingForecastTests.swift` (`@Suite("The pairing forecast")`):
  - `rotationLength` (D-7):
    - 5 → 5, 6 → 3, 7 → 7, 8 → 2, 12 → 3, 16 → 4, each with P0–P2 apart;
    - four players: 2 with an apart pair, 1 with a together pair, 3 with P0–P2 apart;
    - nil for 2 and 3 players, and nil with no active rules.
  - `matchesTheDraw` (SC-008): for 4…12 players and the rule sets {P0+P1 apart, P0–P2 apart, the first half apart, P0+P1 together, P0+P1 together with P2+P3 apart}, `forecast.breaking` equals the number of rounds with a non-empty `unkept` among the next `forecast.rounds` drawn, and `forecast.unkept` equals their distinct pairs in first-met order.
  - `midSessionPlaysOnFromHere`: after three rounds are drawn, the forecast equals what rounds four onward draw.
- [X] T022 [P] [US2] Add `everyDeviceRecordsTheSameBrokenRounds` to `SyncTests/FriendlyPairingSyncTests.swift` (G2; SC-004, SC-006).
  - Set up a host phone with its watch and one guest phone, all current, on a friendly of five with P0–P2 apart.
  - Play ten rounds as in T014.
  - Before each draw, the guest's `nextDraw()?.unkept` equals the host's: the source of the offer's notice.
  - Within 5 s of each draw, all three devices hold identical `rounds.map(\.unkept)`, with exactly four of the ten non-empty.

  It fails today because there is no `unkept`.

### Implementation for User Story 2

- [X] T023 [US2] Give the bench a rule-aware tie-break in `RekkertCore/Tournament/RoundScheduler.swift` (D-3). Give `RoundScheduler.split` a `rules: [PairingRule] = []` parameter.
  - **With rules and a bench:**
    1. From today's `benchFirst` order, take the players who must sit out: those with fewer sit-outs than the last bench place.
    2. Take the boundary group: those with exactly that count.
    3. Enumerate every way to fill the remaining places from the boundary group, lexicographically by position in the shuffled order, so the first combination is today's choice.
    4. Score each by `(breaks on court now, fewest breaks the next round could manage)`. The second part looks one round ahead, with the sit-outs as this bench would leave them, within a fixed budget of benches considered.
    5. Keep the first with `(0, 0)`, or failing that the lowest score, earliest on ties. Looking ahead is what stops a bench that keeps this round from forcing three of a keep-apart group onto the next court (SC-005).
  - **The bench's order.** `sitting` is `benchFirst` filtered to the chosen bench, which equals today's prefix when nothing moved. `playing` is filtered from `shuffled` as today.
  - **Without rules**, return exactly today's result.
  - **Keep it small.** A static helper that scores the three partitions of four players is enough, because doubles seats four.
- [X] T024 [US2] Use the bench rule and add the forecast in `RekkertCore/Friendly/FriendlyScheduler.swift` and `RekkertCore/Friendly/FriendlySession.swift`.
  - **The bench.** Pass `session.activeRules` to `RoundScheduler.split`.
  - **The forecast.** Add `public static func forecast(for:) -> PairingForecast?` (D-7).
    - It is nil with no active rules or fewer than four players.
    - `rounds` is `n / gcd(n, 4)` for n ≥ 5, and the number of allowed partitions for n = 4.
    - It draws that many rounds onto a copy with `appendingRound`, counts those with a non-empty `unkept`, and collects their distinct pairs in first-met order.
  - **A shortcut.** Add `FriendlySession.forecast()` calling it.
  - **Done when** T020–T022 pass and the fingerprint stays green.
- [X] T025 [US2] Show the notices in `App/Sources/Views/FriendlyMatchView.swift` (FR-007; screens §4).
  - **In `upNext`**, after `bench(session, in: next)`, show one line per `next.unkept` with `PairingText.unkept(_:in:offered: true)`.
  - **In `footer`**, while the round is in play, show the same after `bench(session, in: round)` with `offered: false`.
  - **Style**: footnote, secondary, with `Image(systemName: "exclamationmark.triangle")`, centred like the bench line.
  - **Everyone sees them**: not gated on `canRunRounds`. Nothing on the watch or the TV board.
- [X] T026 [US2] Show the forecast in setup. In `App/Sources/Views/NewSessionView.swift`, pass `FriendlySession(id: friendlyID, name: sessionName, rules: rules, players: namedPlayers, pairingRules: pairingRules).forecast()` to `PairingRulesSection`. In `App/Sources/Views/PairingRulesEditor.swift`, show `PairingText.forecast` as a footer line when it is not nil. Start stays enabled (FR-010).

**Checkpoint**: US1 and US2 both work. Groups are kept apart, the bench stays fair, broken rounds say so on every phone, and setup warns ahead.

---

## Phase 5: User Story 3 - Keep two players together (Priority: P2)

**Goal**: Two players who are always partners when both play. Setup refuses rules that
contradict each other.

**Independent Test**: Six players with Cy and Dan always together, over eight rounds. Every
round with both on court has them as partners, and the other four rotate as usual.

### Tests for User Story 3 ⚠️ (write first; they must fail)

- [X] T027 [P] [US3] Add to `CoreTests/FriendlyPairingDrawTests.swift`:
  - `fourWithTwoTogetherRepeat`: 20 rounds with P0 and P1 together. Every round has the same `teams` as round 1, sides included.
  - `sixWithTwoTogether`: 12 rounds with P0 and P1 together.
    - Every round with both on court has them as partners, and `unkept` is empty.
    - Every round with one on the bench has an empty `unkept`.
    - The sit-out counts differ by at most one.
  - `togetherAndApartThatCannotBothHoldAreFlagged`: four players, with P0 and P1 together and P2 and P3 apart. Every round has exactly one `unkept`, and the rounds still cycle.

### Implementation for User Story 3

- [X] T028 [US3] Extend `App/Sources/Views/PairingRulesEditor.swift` for keep-together and clashes (screens §1–§2; FR-009).
  - **The add row.** A **Keep two together…** row.
  - **The sheet for that kind.** Titled "Keep together"; exactly two ticked, a third tick replacing the oldest; the keep-together footer.
  - **Clashes.** A warning glyph on every row whose id appears in `rules.conflicts`, with the footer sentences from `PairingText.conflict`. Done in the sheet is disabled when saving would create a clash.
- [X] T029 [US3] In `App/Sources/Views/NewSessionView.swift`, make `canStart` for `.friendly` also require `pairingRules.pruned(to: namedPlayers.map(\.id)).conflicts.isEmpty` (FR-009). **Done when** T027 passes (the engine already handles `.together` from T004 and T016) and the editor flows in screens §1–§2 work in the simulator.

**Checkpoint**: Both kinds of rule work from setup, and contradictions cannot be started.

---

## Phase 6: User Story 4 - Change the rules during the evening (Priority: P3)

**Goal**: The host, and any guest with Full access, changes the rules from the match menu. The
change applies from the next round. A change racing a draw never re-partners the drawn round,
and an older build's correction never wipes the rules.

**Independent Test**: Start with no rules, play a round, add a keep-apart rule, and draw. The
new round keeps the two apart, and round 1 is unchanged on the phone and the watch.

### Tests for User Story 4 ⚠️ (write first; they must fail)

- [X] T030 [P] [US4] Write `CoreTests/FriendlyPlacementTests.swift` (`@Suite("A friendly draw stays where it was placed")`). Build the logs the way `SessionReducerTests` does (`MatchLog.append(_:from:)`, `merge`).
  - `aRuleChangeRacingADrawKeepsTheRound` (D-5; fails today):
    1. Four players, round 1 drawn and ended.
    2. Copy the log to device A and device B, picking the ids so B's sorts first at equal Lamport stamps.
    3. B appends `.configure(.friendly(session with P0+P1 apart))`.
    4. A appends `.nextRound(after: 0, placed: RoundPlacement(<round A drew without the rule>))`.
    5. Merge both ways.

    Both fold to round 2's `teams == ` A's placement, and the rule is in force from round 3.
  - `aPlacementThatDoesNotFitIsDrawn`: a placement with a doubled player, a missing player, three a side, or the wrong bench size is ignored, and the round is drawn as without one.
  - `unkeptIsTheDrawTimeRules` (D-4): a rule added after round 2 is drawn leaves `rounds[1].unkept` as it was, and round 3 is drawn with it.
  - `aCorrectionAdoptsTheRules`: a mid-session `.configure(.friendly(...))` with new rules keeps the session id and the rounds, and adopts the rules. A later one stating `[]` removes them. It fails today because the reducer drops them.
  - `anOlderCorrectionLeavesTheRules` (I1; research D-1, D-6):
    1. Rules are set by a stating `configure`.
    2. A later correction arrives whose friendly has `statedPairingRules == nil`, built by decoding JSON without the key, as a 1.2 guest's "swap sides" would be, and sorting after it.
    3. The rules are unchanged, and its `rules.changeEnds` is adopted.
    4. The same holds for a `setChangeEnds` correction from this build (C2), which leaves the rules out by design (T036). A rule change on one phone and "swap sides" on another, landing in either order, keep both.

    It fails until T035.
- [X] T031 [P] [US4] Add `fourAfterAMidSessionChange` to `CoreTests/FriendlyPairingDrawTests.swift` (the clarified FR-008): three rules-free rounds, then P0 and P1 apart. Round 4 is whichever of the two allowed line-ups came up first, sides included, and rounds 5 and 6 alternate from it.
- [X] T032 [P] [US4] Add `aFriendlyDrawCarriesItsPlacement` to `CoreTests/WireCompatibilityTests.swift`: a `.nextRound(after:at:sitOuts:placed:)` whose `placed` has one court and a bench round-trips through `MatchEvent` encoding.
- [X] T033 [P] [US4] Add to `SyncTests/FriendlyPairingSyncTests.swift`:
  - `aFullAccessGuestChangesTheRules` (US-4 #4, FR-013): host, guest and the host's watch on a rules-free friendly of four.
    - Mid-round, the guest calls `setPairingRules([P0+P1 apart])`.
    - Within 5 s the host and the watch hold the rule.
    - The round in play is unchanged everywhere.
    - The next round drawn, from any device, keeps P0 and P1 apart everywhere.
  - `aRuleChangeIsNeverUndone` (G1; FR-013): after `setPairingRules`, `undoLast()` on the host, then on the guest, leaves the rules in place on every device, and takes back only the last point if there is one.
  - `onlyScoreIsNotOffered`: `canEditPairingRules` is
    - true on the host;
    - false on a guest after `host.phone.store.setDefaultAccess(.score)`, and after `.readOnly`;
    - false on a guest whose host has `speaksProtocol = 2`;
    - false in a three-player friendly.
  - And in `SyncTests/PairingRulesAdmissionTests.swift`, `rulesAddedMidMatchTakeOlderGuestsOff` (FR-014): a protocol-2 guest is on a rules-free friendly. The host's `olderGuestsTurnedAwayByRules == 1`. After the host's `setPairingRules`, the guest reaches `.failed(.needsUpdate)` within 15 s.

### Implementation for User Story 4

- [X] T034 [US4] In `RekkertCore/Tournament/RoundPlacement.swift`, add `public init(_ round: FriendlyRound)` (`courts: [round.teams]`, `sitOuts: round.sitOuts`) and an internal `friendlyRound(for session: FriendlySession) -> FriendlyRound?`. It returns nil unless:
  - "every listed player appears exactly once across the sides and the bench";
  - "each side has `teamSize` players";
  - "the bench has `sitOutCount` players";
  - `courts.count == 1`.

  When it fits, it builds the round through `FriendlyScheduler.makeRound` (T016), so `unkept` and the first server are stamped as for a drawn round.
- [X] T035 [US4] In `RekkertCore/Sync/SessionReducer.swift`:
  - **The draw.** In the `.nextRound` case for `.friendly`, keep the existing guards, then use `placed?.friendlyRound(for: session)` when it is not nil, and otherwise `FriendlyScheduler.nextRound(for:)`. Append it and stamp `startedAt` as today.
  - **The correction.** In `configure`'s `(.friendly(let incoming), .friendly(var session))` branch, adopt the rules **only when stated**: `if let stated = incoming.statedPairingRules { session.statedPairingRules = stated }`. `name`, `rules` and `players` stay adopted as today.
  - **Done when** T030 and T031 pass and the fingerprint stays green.
- [X] T036 [US4] In `RekkertSync/MatchStore.swift` (D-5, D-6):
  - **The draw.** `nextRound()` for `.friendly` records `placed: session.nextDraw().map(RoundPlacement.init)`.
  - **Who may edit.** Add `public var canEditPairingRules: Bool`. It requires `canRunRounds`, a friendly state with at least four players, and, when `role == .guest`, `(hostDevice.flatMap { peerProtocols[$0] } ?? 1) >= 3`.
  - **The change.** Add `public func setPairingRules(_ rules: [PairingRule])`. It is guarded by `canEditPairingRules` and `rules.conflicts.isEmpty`, sets `session.pairingRules` to the rules pruned to the players (which states them, `[]` included), and records `.configure(.friendly(session))`, exactly as `setChangeEnds` does.
  - **Swap sides leaves the rules alone** (C2). In `setChangeEnds`'s `.friendly` case, record `.configure(.friendly(session.leavingPairingRulesUnstated()))`, so that change never restates, and never reverts, the rules a racing `setPairingRules` just set.
  - **Done when** T032 and T033 pass.
- [X] T037 [US4] Add the in-play screen (screens §3).
  - **The sheet.** In `App/Sources/Views/PairingRulesEditor.swift`, add `PairingRulesSheet`:
    - titled "Pairing rules", with Cancel and Save, editing a copy of `session.pairingRules`, with both kinds and the clash display from T028;
    - the footer "Changes apply from the next round. The round being played stays as it is.";
    - the forecast (T024) from the edited copy of the live session, rounds included;
    - when the session has no active rules and the edit adds one, `PairingText.turnedAway(model.store.olderGuestsTurnedAwayByRules)`;
    - Save disabled on a clash, and calling `model.store.setPairingRules`.
  - **The menu item.** In `App/Sources/Views/MatchOptionsMenu.swift`, add **Pairing rules…** (`person.2.badge.gearshape`) beside the change-ends picker when `model.store.canEditPairingRules`. It presents the sheet.

**Checkpoint**: Rules change in play, safely, from every phone allowed to run rounds.

---

## Phase 7: User Story 5 - The rules come back with the group's preset (Priority: P3)

**Goal**: A friendly preset keeps its rules, and starting from it brings them back attached to
the freshly minted players.

**Independent Test**: Save a friendly with a keep-apart pair and a keep-together pair as a
preset, then start it from Home. Both rules are there; removing a player in the form removes
them from their rule.

### Tests for User Story 5 ⚠️ (write first; they must fail)

- [X] T038 [P] [US5] Add to `CoreTests/PresetTests.swift`:
  - `friendlyKeepsItsRulesThroughFreshIds`: `makeSetup()` gives new `PlayerID`s, and the rules name the new ids of the same names. It fails today because rules are not saved.
  - `aPresetMissingAPlayerPrunesTheRule`.
  - `anOlderFriendlyPresetStillReads`: JSON of a `.friendly` preset without `pairing` decodes with no rules.
  - `summaryCountsTheRules`: "Friendly · 4 players · first to 6 · 2 rules", and no suffix with none.

### Implementation for User Story 5

- [X] T039 [US5] In `RekkertCore/Persistence/Preset.swift`:
  - change the case to `.friendly(name: String, players: [Player], rules: TraditionalRules, pairing: [PairingRule]? = nil)`;
  - in `makeSetup()`, map each old player id to its fresh `Player`'s id, rewrite every rule's members through the map, and prune;
  - make `summary` append " · N rule(s)" when `pairing` is not empty.

  **Done when** T038 passes.
- [X] T040 [US5] Update every pattern match on `PresetConfiguration.friendly` to the new arity. Find them with `grep -rn "\.friendly(" App Shared WatchApp Packages/RekkertKit/Sources`, which includes `Shared/AppModel.swift`'s demo preset. Then, in `App/Sources/Views/NewSessionView.swift`:
  - `init(editing:)` loads `pairing ?? []` into `pairingRules`;
  - `configuration` passes `pairing: pairingRules.isEmpty ? nil : pairingRules`.

**Checkpoint**: All five stories work.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Words, a demo switch, the gate, and evidence

- [X] T041 [P] Update `README.md` (D-12; screens §6).
  - **Friendly.** After the paragraph on the draw, add one paragraph that says:
    - keep apart and keep together exist;
    - the bench stays as fair as ever and leans towards the rules only among players equally due;
    - a round that cannot keep them says so, on the offer and under the board;
    - setup forecasts it;
    - rules change in play from the match menu and apply from the next round;
    - older Rekkert phones are kept off a friendly with rules, and a watch that has not yet updated is held back with a line on its phone.
  - **Who may do what.** Add "the pairing rules" to what *Only score* may not touch.
- [X] T042 [P] In `RekkertCore/Help/ModeHelp.swift`, replace the friendly's second point with "No repeat partners while a fresh one is left. Rules can keep players apart or together." (87 characters; `HelpTests` caps a point at 90 and a mode at three points). Run `swift test --package-path Packages/RekkertKit --filter Help`.
- [X] T043 [P] In `Shared/AppModel.swift`, add the debug flag `-rekkert-demo-friendly-apart` to the `"friendly"` demo: keep the first two demo players apart. List it in README's debug-flags paragraph beside `-rekkert-demo-friendly-players N`. It serves quickstart level 3 and `scripts/shots.sh`.
- [X] T044 Run `swift test --package-path Packages/RekkertKit` and `scripts/verify.sh`; both must pass. `FriendlyTests`, `SeededDrawTests`, `NeedsUpdateTests`, the T002 fingerprint and every sharing suite pass unchanged.
- [ ] T045 Run quickstart.md level 3 on simulators: steps 1–7 against contracts/screens.md, plus the two-phone `scripts/share.sh --keep` check, at the largest Dynamic Type size and with VoiceOver on. Fix what is found.
- [ ] T046 Run quickstart.md level 4 on real devices before release, and record the outcome in `specs/006-friendly-pairing-rules/validation.md`, as `specs/005-steady-sharing-nine-guests/validation.md` does.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup. **T002 comes before any change to
  `RekkertCore/Friendly/` or `RekkertCore/Tournament/`.** Blocks every story.
- **US1 (Phase 3)**: after Foundational. The MVP.
- **US2 (Phase 4)**: after US1. T023–T024 touch the files T015–T016 touch. The tests (T020–T022)
  can be written alongside US1.
- **US3 (Phase 5)**: after US1. Its engine behaviour comes from T004 and T016, and its UI extends
  T017–T018.
- **US4 (Phase 6)**: after US1, US2 and US3. T034 reuses `makeRound` (T016). T037's sheet uses the
  forecast (T024) and the keep-together and clash editor (T028).
- **US5 (Phase 7)**: after Foundational. Its form changes build on T018.
- **Polish (Phase 8)**: after the stories being shipped.

### User Story Dependencies

```text
Foundational ──► US1 ──► US2 ──┐
                  └────► US3 ──┴──► US4
Foundational ──► US5 (form changes after T018)
```

### Within Each User Story

- Tests are written first and must fail for the reason given.
- Engine (RekkertCore), then store (RekkertSync), then views.
- After every engine task, the T002 fingerprint stays green.

### Parallel Opportunities

- Phase 2: T003, T006, T008 and T011 are separate test files, so they can be written in
  parallel. T004 → T005 are sequential (T005 needs T004's types); T007 → T009 → T010 are
  sequential (same file); T012 follows T011.
- US1: T013 and T014 in parallel; T015 → T016 sequential; T017 → T018 sequential, alongside
  the engine work; T019 any time after T010.
- US2: T020, T021 and T022 in parallel, even while US1's implementation is under way.
- US3: T027 can be written alongside US2.
- US4: T030, T031, T032 and T033 in parallel; then T034 → T035 → T036 → T037.
- US5: T038 can be written any time after Foundational.
- Polish: T041, T042 and T043 in parallel.

---

## Parallel Example: Foundational and User Story 1

```bash
# Phase 2 test files, written together after T002 is green:
Task: "Write CoreTests/PairingRulesTests.swift (T003)"
Task: "Add aFriendlyWithRulesReadsAsOneWithoutOnAnOlderBuild to CoreTests/WireCompatibilityTests.swift (T006)"
Task: "Write SyncTests/PairingRulesAdmissionTests.swift and CourtHarness.startFriendly (T008)"
Task: "Write CoreTests/PairingTextTests.swift (T011)"

# User Story 1 tests together:
Task: "Write CoreTests/FriendlyPairingDrawTests.swift (T013)"
Task: "Write SyncTests/FriendlyPairingSyncTests.swift with phoneAndWatchDrawTheSameWithRules (T014)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: confirm the baseline (T001).
2. Phase 2: pin the fingerprint first (T002), then the types, the sentences and both gates.
   Even the MVP must keep older devices off a friendly with rules.
3. Phase 3: keep-apart pairs in setup and the draw.
4. **Stop and validate**: run the US1 independent test and quickstart level 3 steps 1–2. This
   already solves the request as asked: four players, two strong, never together.

### Incremental Delivery

1. Foundational + US1 → TestFlight (MVP).
2. US2: groups, the fair bench's tie-break, the notices and the forecast.
3. US3: keep-together and the clash checks.
4. US4: changing rules in play, with draws carrying their placement.
5. US5: presets.
6. Polish, then the real-device evening (T046) before the App Store.

Each step keeps the fingerprint green and `scripts/verify.sh` passing.

---

## Notes

- [P] tasks touch different files and depend on nothing unfinished.
- The fingerprint (T002) is the contract with every existing friendly. Never regenerate it to
  make a task pass.
- Commit after each task or logical group, in the conventional style the history uses, with no
  AI attribution trailers.
- Stop at any checkpoint to validate a story on its own.
