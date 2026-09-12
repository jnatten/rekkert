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

Whoever is serving is marked with a dot, and beside it a small two-cell badge shows which
half the serve is struck from — drawn from behind the server, so the lit cell is on the
hand they will be standing on. It follows the receivers' choice on a golden or star point
rather than just alternating.

**Winner court** — you play games on a court until the organiser blows the whistle, then
move up or down. A round is a set with no end: games just accumulate. The whistle banks
them and the next round starts at nil-nil. Scoring is 15/30/40 with the same deuce options
as a match. The app tracks only your own side of it — the round number and the games each
side won — so there are no courts, partners or standings to keep up to date. The whistle
usually interrupts a game, so the one in progress goes to whoever is ahead in it; level and
it is discarded.

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
plus standings and round history. Scores can be tapped in point by point, typed, nudged
with a stepper, or picked from a list of results — in "total points played" mode both
halves always add up to the target, so one tap settles a court.

Players who have played before are remembered and offered back as one-tap chips and as
suggestions above the keyboard while typing; Return moves to the next name. Chevrons move
between rounds. Going back to an earlier round shows it as it was played;
reopening it allows corrections. Later rounds keep the pairings they were drawn with,
since they were seeded from the standings at the time. The watch shows one court at a
time — swipe between them — and can score or correct any of them. Swiping left past the
last page reaches a menu holding everything that ends something: end the round, draw the
next one, undo, finish and save. They are kept off the scoring page so a stray tap during a
rally cannot end a round.

## Full screen

Any scoreboard has a full-screen button. It fills the display with the two numbers, turns
the brightness up and stops the screen locking, so the phone can be propped at the side of
the court and read from the far end. Turn it landscape and the digits get about half again
as large. Tapping still scores; the controls dim after a few seconds but never vanish, so
the way out is always there without having to tap a half and score a point by accident.
Brightness and auto-lock are put back on the way out, and while the app is in the
background.

## Presets

Name a setup when you start it and it is saved as a preset. Presets sync to the Apple
Watch, so the regular Thursday americano — players, courts, point target and all — starts
from the wrist without reaching for the phone. Starting from a preset mints a fresh
tournament each time, so standings never bleed from one evening into the next.

Presets are edited on the phone and read on both, so the whole library travels together
and the newer copy wins. That is what keeps a deletion from being resurrected by a stale
copy on the other device.

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

Debug builds accept `-rekkert-demo traditional|winnercourt|americano|mexicano` (plus
`-rekkert-demo-points N`, `-rekkert-demo-deuce`, `-rekkert-demo-rounds`,
`-rekkert-demo-undo-draw`, `-rekkert-demo-browse-round N`,
`-rekkert-demo-open-court R,C`, `-rekkert-demo-roster`, `-rekkert-demo-presets`,
`-rekkert-demo-watch-page menu`, `-rekkert-demo-fullscreen` or
`-rekkert-demo-new <mode>`) as
launch arguments to put the app into a given state, since `simctl` cannot tap the screen.
