# Quickstart: Proving Leaving Early Works

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

Fastest first. Each level assumes the one before it is green.

## Prerequisites

- The toolchain from `mise.toml` (`mise install`).
- For level 3: a Debug build on an iPhone simulator, and `axe` for tapping.
- For level 4: two iPhones and a watch on this build, and one iPhone on the latest TestFlight
  build before it.

## 1. Device-free tests (seconds; every push)

```bash
swift test --package-path Packages/RekkertKit
```

Write `TournamentNoAbsenceFingerprintTests` first and commit it green on today's code. It pins
every Americano and Mexicano round for 5–16 players on 1–4 courts over 20 rounds, with a bench
picked by hand in round 3. It must stay green through every change after it (D-13).

| Suite | What it proves |
|---|---|
| `TournamentNoAbsenceFingerprintTests` | Nobody leaves, nothing changes, Americano `placed` included. |
| `TournamentAbsenceTests` | `settingAway` covers each case of D-3 and D-4. A redraw when nothing is played. A court confirmed where it stands with points, and at 0–0 when only another court has points. Bench credit kept. Marking someone already away. An absence closed at its own start is removed. Ladder, finished and unknown players are no-ops. |
| `AbsenceDrawTests` | SC-002: over 5–16 players, 1–4 courts and both formats, a player who left is on no court and no bench in any later round, and courts and bench fit those present. Mexicano ranks only those present. SC-005: an Americano with one gone repeats no partner more often, over the rotation of those left, than one started with that many. |
| `ReturnBenchTests` | D-6: a returner plays their first round back. Over the next rotation their sit-outs end within one of everyone else's. A tournament with no absences builds today's history. |
| `AbsencePlacementTests` | D-5: Americano draws carry `placed`. A draw that raced a departure keeps its line-up, and away players it benched get no credit. A placement that leaves out someone present is refused. |
| `TournamentLengthTests` (additions) | A full rotation counts pairs among those present. A set number of rounds is unchanged. `isShortOfPlayers` below four. |
| `TournamentTests` (additions) | No compensation while away. `away` stretches. The ranking order is unchanged (FR-011). SC-003: points at the end equal points when they left. |
| `AwayTextTests` | Every sentence in contracts/screens.md, singular and plural. |
| `SessionResultTests` (additions) | `Placing.detail` for anyone who was away, nil for everyone else. |
| `WireCompatibilityTests` (additions) | `absences` is absent from a tournament nobody left. It decodes when present. `setAway` round-trips, and an older decoder reads it as `.unrecognised`. Americano `placed` round-trips. |
| `RekkertSyncTests/TournamentAbsenceSyncTests` | SC-004: two phones and a watch fold a departure, a mid-round departure and a return, and show identical rounds, benches and tables within 5 s. SC-006: a departure that raced a draw made out of contact re-partners nothing, and changes no score but the stopped court's. |
| `RekkertSyncTests/AbsenceAdmissionTests` | A guest speaking 3 is turned away when the first departure folds, and at hello after it. A watch at 3 is held back, and `pairNeedsUpdate` is true. A friendly with rules still admits a guest at 3. A guest offers the action only to a host at 4. |

## 2. The gate (minutes; every push)

```bash
scripts/verify.sh
scripts/cross-build.sh ca67ad0 b03026e            # the two latest TestFlight builds at planning time
scripts/cross-build.sh --players 13 ca67ad0
```

Expected: everything green. Cross-build folds every round the same both ways, in Americano and
Mexicano. That shows the Americano `placed` changes nothing an older build sees while nobody
has left. No Info.plist key, entitlement or background mode is involved.

## 3. Simulators: the screens, tapped

Launch a debug build with the Americano demo:

```bash
xcrun simctl launch <udid> dev.natten.rekkert -rekkert-demo americano
```

Reinstall before each launch, so no earlier session is restored. Tap through each step: a launch
flag can't show a sheet that closes the moment it's tapped open (bug
`pairing-rule-sheet-closes`). Check against [contracts/screens.md](contracts/screens.md):

1. **Between rounds.** Finish round 1, open **Who's here…**, mark a player as left.
   - The confirmation states the courts and bench from round 2.
   - Round 2 leaves them out.
   - Standings say "Left after round 1", and their points are unchanged.
2. **Before the first point.** Draw a round, then mark someone in it as left.
   - The confirmation says the round is drawn again.
   - The round changes, and nobody is credited for it yet.
3. **Mid-round.** Score a court to 9–7 and mark one of its players as left.
   - The confirmation says the court stops at 9–7.
   - Points can't be added to it.
   - The round closes when the other courts finish.
4. **Down to three.** Mark players as left until three remain.
   - The Draw button gives way to the line and **Finish tournament**.
5. **Coming back.** Bring a player back.
   - They are in the next round, not on its bench.
   - Their label reads "Away rounds a–b".
6. **Full rotation.** Set up nine players with a full rotation, and mark one as left after round 2.
   - The partnerships still to go drop to those among the eight.
7. **The finish.** Finish the tournament, then open it in History.
   - The table and History both say who left and when.
   - "Away: …" shows under each round they missed.

Check each screen at the largest Dynamic Type size and with VoiceOver on.

## 4. Real devices: one tournament evening (before release)

1. Host an Americano on one iPhone. Join it from the second iPhone with Full access, and from
   the TestFlight iPhone.
2. Mark someone as left on the second iPhone.
   - The host's confirmation (if made there) counts the older phone.
   - The older phone is told to update.
   - The host's watch, if on the older build, shows that it needs updating.
3. Play three rounds, and check every device shows the same rounds and table.
4. Put the second iPhone in flight mode. Draw a round on the host while marking a player as left
   on the second iPhone, then reconnect.
   - The drawn round is unchanged everywhere.
   - The away player shows the race note in **Who's here?**
5. Record the outcome in `specs/008-tournament-leave-early/validation.md`.
