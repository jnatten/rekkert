# Rekkert

Padel and tennis score tracking for iPhone and Apple Watch. The score syncs both ways
between the two, so it does not matter which one you tap. No Health integration.

## Modes

**Match** — real padel/tennis scoring: points, games, sets, match. Configurable sets to
win, games per set, tiebreak, super-tiebreak deciding set, and what happens at 40–40:

| Rule | At 40–40 |
|---|---|
| Deuce | Advantage, repeating until someone wins two in a row |
| Golden point | The first 40–40 is a single deciding point; the receivers pick the side |
| Star point | Two deuces are played out, the third 40–40 decides (current WPT rule) |

**Americano / Mexicano** — club tournaments over one or more courts. Points count
1, 2, 3, … to a configurable target (16 by default; 21, 24 and 32 are a tap away). A round
either ends when both scores together reach the target — so every court finishes at the
same time — or when one team reaches it on its own; that is a setting.

Americano builds each round so everyone partners everyone, avoiding repeat partners and
repeat opponents. Mexicano re-ranks after every round and puts the top four on court 1,
paired 1+4 vs 2+3. Player counts that are not a multiple of four rotate sit-outs by
whoever has sat out least, and benched players score a configurable number of points
(half the target by default).

On the phone, the court list is the main tournament screen: every court with its score,
plus standings and round history. The watch shows one court at a time — swipe between
them — and can score or correct any of them.

## Getting started

Requires Xcode 26 and [mise](https://mise.jdx.dev) (which pins Tuist via `mise.toml`).

```sh
mise install                 # installs the pinned Tuist
tuist generate               # writes Rekkert.xcworkspace
open Rekkert.xcworkspace
```

Re-run `tuist generate` after adding a file — Tuist globs sources at generation time.

## Running on a real iPhone and Watch

Simulator builds need no signing. For hardware you need an Apple ID added to Xcode
(Settings → Accounts); a free personal team works, with profiles that expire after 7 days.

Find your team id and make it stick across `tuist generate`:

```sh
# Xcode → Settings → Accounts → your team → the 10-character ID in the Team column
cat > mise.local.toml <<'TOML'
[env]
TUIST_DEVELOPMENT_TEAM = "ABCDE12345"
TOML

tuist generate
```

`mise.local.toml` is gitignored. Then plug the iPhone in, pick it as the run destination
and run the `Rekkert` scheme — the watch app is embedded, so it installs onto the paired
Apple Watch by itself (give it a minute, or push it manually from the Watch app on the
iPhone). To iterate on the watch alone, run the `RekkertWatch` scheme with the watch as
the destination.

## Layout

```
Project.swift              Tuist project: iOS app + embedded watchOS app
Packages/RekkertKit/       the brain, as a local Swift package
  RekkertCore              scoring, tournaments, event log, persistence (pure Foundation)
  RekkertSync              WatchConnectivity transport and the observable MatchStore
App/                       iPhone SwiftUI
WatchApp/                  Apple Watch SwiftUI
Shared/                    the scoreboard and app model, used by both apps
```

Everything with interesting logic lives in `RekkertCore`, which depends on nothing but
Foundation and therefore runs under `swift test` on macOS in about a second — no simulator.
That matters because WatchConnectivity is only partly usable on the Simulator, so
convergence has to be provable without it.

## How syncing works

Every score change is an append-only event stamped with `(deviceID, sequence)` and a
Lamport clock; state is a pure fold over the ordered log. Merging is a union keyed by
event id, so it is commutative, associative and idempotent — duplicated, reordered or
replayed delivery is harmless. Two simultaneous taps on both devices are distinct events
and both count. Undo is a tombstone event rather than a deletion, so an undo on the watch
and a point on the phone both survive.

Live updates go over `sendMessage`, whose reply doubles as an acknowledgement carrying the
peer's version vector — one round trip that both confirms delivery and reconciles.
Durability is an outbox we persist ourselves rather than `transferUserInfo`, which is not
supported on the watchOS Simulator. `updateApplicationContext` carries a whole-log snapshot
as the cold-start backstop.

If a phone and a watch each end up with a session of their own, the more recently started
one wins and the other is archived to History rather than dropped.

## Verifying

```sh
swift test --package-path Packages/RekkertKit   # the fast loop, no simulator
./scripts/verify.sh                             # tests, build both apps, assert embedding
```

`scripts/verify.sh` also asserts that the watch app really is embedded at
`Rekkert.app/Watch/` with the right `WKApplication` and companion bundle identifier — a
three-line regression test for the whole watch-embedding story.

To exercise sync on paired simulators:

```sh
xcrun simctl pair <watch udid> <phone udid>
xcrun simctl boot <pair udid>
```

Debug builds accept `-rekkert-demo traditional|americano|mexicano` (plus
`-rekkert-demo-points N` or `-rekkert-demo-deuce`) as launch arguments to seed a session,
since `simctl` cannot tap the screen.
