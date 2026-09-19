# Rekkert

Padel and tennis score tracking for iPhone and Apple Watch. The score syncs both ways
between the two, so it does not matter which one you tap. The watch will record the session
as an Apple Health workout, if you ask it to.

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
hand you will see it on. Your own serve is drawn as you stand; theirs is drawn from your
side of the net, so their deuce court — their right — shows on your left, which is where
you will actually see them. It sits below your own score and above theirs, matching the
court in front of you where their end is the far one. It follows the receivers' choice on a
golden or star point rather than just alternating.

**Winner court** — you play games on a court until the organiser blows the whistle, then
move up or down. A round is a set with no end: games just accumulate. The whistle banks
them and the next round starts at nil-nil. Scoring is 15/30/40 with the same deuce options
as a match. The app tracks only your own side of it — the round number and the games each
side won — so there are no courts, partners or standings to keep up to date. The whistle
usually interrupts a game, so the one in progress goes to whoever is ahead in it; level and
it is discarded.

**Friendly** — you put in the names and play real matches, redrawing the partnerships after
every one of them. A round is a match on the ordinary rules — sets to win, games per set,
tiebreak and the 40–40 rule are the ones Match uses — and when somebody wins it the board
locks on the final score and offers the next round, naming the pair about to play it. Tapping
starts it; until then the point that ended the last one is still there to be taken back. A
round can also be stopped where it stands, and the games played still count.

Four or more play doubles; two or three play singles. Anyone over the four seats sits the
round out, and the bench goes to whoever has sat out least, so it comes round evenly. The
draw puts nobody with the same partner twice while a fresh pairing is available and, after
that, avoids repeating match-ups — Americano's own cost function, on one court. With exactly
four there are only three ways to pair up and the first three rounds use them all; after that
they come round again in the order they were first drawn, so round four is round one again,
same pairs on the same sides. It is seeded on the session id and the round number and reads
only who has played with and against whom, never the scores, so the phone and the watch draw
the same round without negotiating it, and correcting a point can never re-partner a round
already drawn.

Rounds go on until somebody finishes the session. The rounds list, in the match menu, holds
every round played and the table so far — ranked on rounds won, ties broken on games won —
and both turn up again on the result screen and in History.

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

A match can be played out or called off part way. Ending it offers to keep it in history
or to discard it, and that decision travels with the event so the other device does not
file something you threw away. A match played to its end is kept without being asked.

Opening a filed match has an **Edit** button on it, for the names. Whatever the mode is
called by — the tournament's name, the friendly's, or the two team names a match is listed
under — and everybody in it can be put right afterwards, so a typo or a "Them" nobody got
round to filling in is not there for good. A corrected name follows through that match
everywhere it appears: the rounds, the table and the result. Only that one match changes;
the names remembered for next time, and every other match, are left alone. Nobody can be
added or taken out — the rounds were drawn around the people who played them.

## Mid-match corrections

Both apps carry two fixes for when reality and the app disagree. **Swap serving team**
moves service to the other side and carries through the rest of the rotation; it is match
state, so it travels between the devices. **Swap sides** flips which half of the screen each
team occupies, for when you have changed ends. Only the phone mirrors — it is the one
propped up with a side of the court in front of it — but the button is on both, so the
watch flips the phone from the wrist without anyone walking over to it. Flipping also turns
the games line round, so it reads the same direction as the numbers above it.

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

## Workouts

The watch can record a workout while you play. It is a button — on the watch's menu page,
on its idle screen, and in the iPhone's main menu — and it has nothing to do with matches:
it never starts itself, it survives a match ending, and you can play none, one or six of
them while it runs.

It is saved to Health as tennis, indoors. Health has no padel, and tennis is the nearest
thing in the list with an energy model calibrated for it. Indoors is chosen rather than
offered: an outdoor workout turns on GPS, and not asking for location at all is worth more
than a route map of a padel court.

Starting it holds the watch app frontmost, which is the other half of why it exists — a
lowered wrist comes back to the score rather than to the clock.

It can be held part way through. Padel is played in blocks — you walk off for a coffee,
wait for a court, sit out a round — and a workout left counting through that reads as an
hour of tennis with the heart rate of a queue. Pause and resume sit beside the start and
stop button, on the watch's menu page and its idle screen, and in the iPhone's menu, and
the watch is the one that holds the session either way: the phone asks and the wrist
answers. Health leaves a held stretch out of the duration it saves, so the clock on the
watch and the workout in Health are the same number and always were. While it is held the
heart on the scoreboard becomes a still grey pause mark, because a pause you have
forgotten about quietly eats a match.

The watch keeps no history of its own, so when the workout ends the summary travels to the
phone on the same durable queue the outbox uses, and the phone files it under `workouts/`.
If the phone is away it arrives whenever the phone next turns up. If it never arrives at
all, the workout is still in Health, which is where the real copy lives.

The phone lists them under History. Opening one shows how long you played, the energy and
the heart rate, and the matches you scored while it was running. Matches are lined up by the
clock rather than by a stored link — a workout has no id until Health saves it, which is
after the match it covers has already been filed — so starting the workout halfway through
the first game still gathers that game up, and a match spanning two workouts shows under
both.

Heart rate never goes on the wire. The live reading stays on the wrist that read it, and the
summary reaches that one phone and no other: `FanOutTransport.Scope.sharedSession` drops it,
in the same exhaustive switch that drops your saved setups, so adding a `Wire` case carrying
anything personal is a compile error rather than a leak.

None of it is required. Never press the button and the app is what it was: no prompt, no
Workouts row, no Health access of any kind.

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
                           — HealthKit must never reach here, or the tests need a simulator
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

Between phones the same conversation runs over two links at once. The local network —
Bonjour over Network.framework, with the six-character code as a TLS pre-shared key — is the
quick one, and iOS takes it away the moment the app stops being in front of somebody. So
Bluetooth runs alongside it: it is the only link the system will let an app hold open with the
screen off, which is what keeps two watches agreeing while both phones are in bags. A peer on
both hears everything twice, which costs bytes and nothing else, because merging is a union.

Bluetooth cannot carry the code in its advertisement — a backgrounded peripheral drops its
name and service data and moves its service UUID into an overflow area — so the UUID is fixed
and app-wide, and the code is checked after connecting instead: the host publishes a share id
and a two-byte fingerprint, and every frame is then sealed with a key derived from the code.
Deriving the service UUID from the code would be worse than saying nothing, since thirty bits
of code under a hash broadcast in the clear comes straight back out.

A drop is not a refusal. `ReconnectPolicy` decides what losing a connection means, and the
only thing that tells a wrong code from a host who walked off is whether anything ever worked.
Guests keep dialling on a timer rather than waiting for a Bonjour change that never comes, and
a reconnect merges rather than replaces — both sides keep whatever they scored while apart. If
the merged score is one nobody recognises, the host can settle it from the match menu.

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

Debug builds accept `-rekkert-demo traditional|winnercourt|friendly|americano|mexicano` (plus
`-rekkert-demo-points N`, `-rekkert-demo-deuce`, `-rekkert-demo-rounds`,
`-rekkert-demo-friendly-rounds N`, `-rekkert-demo-friendly-players N`,
`-rekkert-demo-rounds-sheet`,
`-rekkert-demo-undo-draw`, `-rekkert-demo-browse-round N`,
`-rekkert-demo-open-court R,C`, `-rekkert-demo-roster`, `-rekkert-demo-presets`,
`-rekkert-demo-watch-page menu|standings|controls`, `-rekkert-demo-fullscreen`,
`-rekkert-demo-settings`,
`-rekkert-demo-workouts`, `-rekkert-demo-workout`, `-rekkert-demo-workout-paused`,
`-rekkert-demo-voices` or
`-rekkert-demo-new <mode>`) as
launch arguments to put the app into a given state, since `simctl` cannot tap the screen.

### Sharing a match between two phones

Two booted iPhone simulators share the Mac's network stack, so Bonjour between them works:

    HOST=<udid>; GUEST=<udid>
    APP=.build/dd/Build/Products/Debug-iphonesimulator/Rekkert.app
    xcrun simctl install $HOST $APP; xcrun simctl install $GUEST $APP

    xcrun simctl launch $HOST  dev.natten.rekkert \
      -rekkert-demo traditional -rekkert-demo-points 5 -rekkert-share-host K9M4PT
    xcrun simctl launch $GUEST dev.natten.rekkert \
      -rekkert-share-join K9M4PT -rekkert-demo-late-tap 14

`-rekkert-share-host CODE` pins the code instead of drawing one, `-rekkert-share-join CODE`
opens the join sheet with it filled in and submits, and `-rekkert-demo-late-tap N` scores a
point after N seconds — which is how a *live* update gets verified between two simulators
that nothing can tap.

`./scripts/share.sh` does all of that and asserts it: two phones and the paired watch on one
match, everybody's `active.json` holding the same events, then the guest killed while the host
scores and brought back to catch up from the log. `--no-build` reuses the last build, `--keep`
leaves the simulators up.

Four things the Simulator cannot show you. The peer-to-peer radio path — there is no AWDL
interface, so `includePeerToPeer` is quietly a no-op — and the iOS local-network permission
prompt. And `BluetoothTransport`, which is inert there: the simulator runs no `bluetoothd`, so
CoreBluetooth's XPC connection is refused and everything above goes over the local network.
And a phone in a pocket, because a backgrounded simulator app is not suspended — its listener
and its sockets stay up, which is the one condition the Bluetooth link exists for. All of them
need two real iPhones.

`swift scripts/psk-spike.swift` checks, in a couple of seconds and with no devices at all,
that a session code still works as a TLS pre-shared key.

## Screenshots

```sh
./scripts/shots.sh             # every shot the landing page and the App Store use
./scripts/shots.sh --docs      # only docs/images/
./scripts/shots.sh --no-build  # reuse the last build
```

Docs images are written straight into `docs/images/` at the sizes `docs/index.html`
declares, and the script fails if the two ever disagree — a wrong size is a crooked page
that nothing else would catch. App Store images land in `fastlane/screenshots/en-US/`, at
the simulator's own resolution.

## The App Store listing

The description, promotional text, keywords, copyright and privacy URL live in
`fastlane/metadata/`, one plain file per field, and are the source of truth rather than the
web form:

    fastlane/metadata/copyright.txt          # not localised, so it sits at the top
    fastlane/metadata/en-US/description.txt
    fastlane/metadata/en-US/keywords.txt
    fastlane/metadata/en-US/promotional_text.txt
    fastlane/metadata/en-US/privacy_url.txt

`deliver` reads a fixed set of names, and the ones not here yet are `release_notes.txt`
(What's New, per version), `name.txt`, `subtitle.txt`, `support_url.txt` and
`marketing_url.txt`. Add a file and it starts being uploaded.

```sh
./scripts/release.sh --metadata                  # text only
./scripts/release.sh --screenshots               # images only
./scripts/release.sh --screenshots --metadata    # the whole listing
```

None of these build anything. Both belong to a version rather than to the app, so they
need a version in an editable state — the one you are preparing.

Screenshots replace the set for each device size instead of adding to it, because App
Store Connect caps a set at ten and then refuses. Metadata only touches fields that exist
as files: a missing one is skipped, and so is an empty one, so a field is cleared in the
web UI and never by emptying a file here. Anything over Apple's character limit is caught
before the upload rather than after the round trip.

The shots come from an iPhone 17 Pro Max and an Apple Watch Ultra 3; set
`REKKERT_SHOTS_PHONE` or `REKKERT_SHOTS_WATCH` to shoot a listing slot of another size.
App Store Connect is the only thing that knows which pixel sizes it accepts this month, so
the script prints what it made rather than claiming the sizes are right.
