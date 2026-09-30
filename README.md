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
golden or star point rather than just alternating. When the players are named, the server's
name sits beside the badge, and the four take their turns in the usual order — one from each
side, so partners never serve back to back.

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
whoever has sat out least and, of those, whoever sat out longest ago, so nobody is benched
again sooner than the numbers force. Benched players score a configurable number of points
(half the target by default). Until the first point of a round, who sits it out can be
changed on the phone — for whoever is late — and the round is drawn again around the pick.
A picked sit-out counts like any other, so whoever it spared is next in line.

On the phone, the court list is the main tournament screen: every court with its score,
plus standings and round history. Scores can be tapped in point by point, typed, nudged
with a stepper, or picked from a list of results — in "total points played" mode both
halves always add up to the target, so one tap settles a court.

Players who have played before are remembered and offered back as one-tap chips and as
suggestions above the keyboard while typing; Return moves to the next name. Chevrons move
between rounds. Going back to an earlier round shows it as it was played;
reopening it allows corrections. Later rounds keep the pairings they were drawn with,
since they were seeded from the standings at the time. The round in play can be
cancelled — say, when time runs out part way through it — and then counts for nobody:
neither the points scored on court nor the compensation for sitting it out. Finishing a
tournament whose last round is unfinished offers to leave that round out. The watch shows one court at a
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
round to filling in is not there for good. A match, a Points round or a winner court can be
given a name of its own there too, to be listed under instead of the two teams; cleared, it
goes back to them. A corrected name follows through that match everywhere it appears: the
rounds, the table and the result. Only that one match changes; the names remembered for next
time, and every other match, are left alone. Nobody can be added or taken out — the rounds
were drawn around the people who played them.

The same sheet takes a note — where it was played, who was missing, how it went. It is
shown on the match and as a line under it in History, and stays with that one record: a
match picked up again from History takes its name along, but its note stays on the copy it
was written on.

## Players

**Players**, under History, adds up everything that has been filed. Each person gets a win
rate and a won–lost record — draws count as played and not won — split out mode by mode as
well; their partners, with the best of them picked out, which is the best win rate over at
least three games together; a head-to-head record against everybody they have played; and,
for Americano and Mexicano, the points they average a round and their share of the points
played. Every match they were in is listed underneath, a tap away from the match itself.

A game counts once, whatever mode it came from: a match somebody won, a Points round that
reached its target (level is a draw), every round on a winner court up to the last whistle,
every friendly round somebody won, and every americano court played out or confirmed. A match
called off without a winner, a friendly round stopped where it stood and a court left part-way
when a tournament was saved count for nobody. Rounds on the bench are left out of the points,
and so is what they were worth. Winner court counts for the record and the partners but not
head-to-head, since the other side of the net changed at every whistle. A session picked up
again from History is counted once, not once per copy.

The calendar button at the top picks which stretch of the history is added up, and the
choice is remembered. It offers all time; the last 7, 30 or 90 days, 12 months or 5 years;
this week, this month or the year to date; last week, last month or last year, meaning the
whole calendar week, month or year before this one; and any year that has something in it.
**Custom…** covers everything else: the last however many days, weeks, months or years;
everything since a given day; or everything between two days, both included. A match counts
in the period it finished in, and rolling periods count today as their last day, so "last 7
days" is today and the six before it. Merging and separating always work on the whole
history, whichever period is showing.

People are known by their name and nothing else, so the same name is the same person — case
and accents aside, though ø, æ and å are letters of their own. A name corrected in one match
and not the others therefore comes out as two people. **Merge with…** on a player's page puts
them back together, for the matches already played and for any still to come under either
name, and **Unmerge** takes it apart again.

Two people with the same name are the other way round. A session in which two seats came out
as one person is marked with a warning, and the games those two played against each other
count for neither until they are told apart. **Separate matches…** moves the matches you tick
to somebody else: a player already on the list, or a new one of the same name with a note
("from work") to tell them apart. Whatever is left unticked, and every match still to come
with that name in it, stays with the first — so for two Johns who both play often, setting
one of them up as "John B" saves separating them every time. None of it touches the matches
themselves: who is who is kept beside the history, and throwing it away would leave every
match as it was filed. A winner court picked up again before any of this existed can still
count twice; deleting the older copy puts it right.

## The clock

Beside the line above the score, the board says how long it has been going. In the modes
that play in rounds it times the round — the americano round, the friendly, the stretch
between two whistles on a winner court — and starts again at nil when the next one is
drawn. Match and Points have no rounds to time, so theirs runs the length of the session.
It only counts; there is no round length to set and nothing happens when it reaches a
number.

The moment a round started travels with the round, so the phone, the watch and a guest's
phone all count from the same one — a guest joining halfway through picks the round up
where it actually is rather than at nil. Two devices drawing a round at the same instant
settle on one of the two stamps, the same way they settle on one draw. Clocks that disagree
by a second or two show it, which is as close as two wristwatches ever get.

A board that is over is not timed: a match somebody has won, a friendly round that has been
played out or called off, a tournament round already confirmed, and any earlier round you
have gone back to look at. The full-screen board has no clock either — it is the two
numbers and nothing else, read from the far end of the court.

## Mid-match corrections

Both apps carry three fixes for when reality and the app disagree. **Swap serving team**
moves service to the other side and carries through the rest of the rotation, each pair
keeping its own first server; it is match state, so it travels between the devices.
**Swap serving player** hands the serve to the server's partner, for a pair that began with
the wrong one, and carries through that pair's later turns; it only appears when both
players on the serving side are named. **Swap sides** flips which half of the screen each
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
background. In bright sun the colours are the first thing to go, so the moon button blacks
both halves out — white digits on black, the names in the team colours — and the setting
stays on until you turn it off, from the board or from Settings.

## On a TV

Connect the phone to a TV — Screen Mirroring to an Apple TV from Control Center, or an HDMI
adapter — and the TV gets a board of its own instead of a copy of the phone. The phone carries
on as normal, scoring included, and every point shows on the TV wherever it was scored: on
this phone, its watch or anybody else's phone on the match. There is nothing to turn on:
whatever is connected gets the board. iOS lets only Control Center start Screen Mirroring,
so the AirPlay button explains how rather than doing it, and lights up while a TV has the
board. It sits beside the watch glyph, or in the options menu of a phone's match screen,
where the bar has no room for it.

A match, a points round, a winner court and a friendly are two halves in the team colours:
the team's name, everyone on it by name with the one to serve picked out, the score as large
as the half allows, and the games of each set underneath. A friendly adds its table down the
side and who is sitting out, and between rounds who plays next. An americano or mexicano
puts every court of the round up at once — both pairs, the score and who serves — with the
table beside them and the bench along the bottom. The table shows as many rows as fit. Above
it all is the round and its clock. With nothing on the TV says so, and a session that has
just finished leaves its result up.

The phone stays awake while a TV is connected, because locking it ends mirroring. On an
iPad, or any screen wide enough, a Board button puts the same board up on the device
itself. While mirroring, the score being called out comes from the TV's speakers.

## The Lock Screen

While a session is live the phone puts the score on the Lock Screen and in the Dynamic
Island, so a phone in a pocket can be looked at without being opened. A match is drawn as
two rows, the side on the left of the phone's own board on top: sets, games, the point and
the serve. The Dynamic Island has the two points either side of the camera, each in its
team's colour. A tournament gets the round, its clock, every court's score and the top
three of the table. It is there to be read and nothing else: there are no buttons on it, so
a phone in a pocket cannot score a point. Tapping it opens the app.

Nothing pushes it. The phone updates it itself, from the same place every other change to
the score passes through, and it is awake for every point that matters — over Bluetooth
from the other phones at the court, or from its own watch. Starting one is different:
iOS only lets an app start a Live Activity from the front. So a match started on the watch,
with the phone in a bag, shows up there the next time the phone is opened, and keeps itself
up to date from then on.

A match that finishes leaves its result up for a quarter of an hour. One that was thrown
away goes at once. A phone that was killed mid-match picks its activity back up when it
relaunches, rather than putting up a second one. It is on by default and can be turned off
in Settings, and iOS's own switch for the app overrules it.

The extension that draws it links `RekkertCore` and nothing else. What it is handed is a
`LiveScore`, built from the same `ScoreboardSnapshot` the boards use, and a test holds an
eight-court americano under ActivityKit's 4 KB limit.

## Presets

Name a setup when you start it and it is saved as a preset. Presets sync to the Apple
Watch, so the regular Thursday americano — players, courts, point target and all — starts
from the wrist without reaching for the phone. Starting from a preset mints a fresh
tournament each time, so standings never bleed from one evening into the next.

Presets are edited on the phone and read on both, so the whole library travels together
and the newer copy wins. That is what keeps a deletion from being resurrected by a stale
copy on the other device.

On Home, press and hold a preset to change its setup or rename it, or tap Edit to drag
them into order. The watch lists them in the same order, and a new one goes on top.

## Joining from the wrist

Most people at a shared match only ever join one. They host nothing, set nothing up, and
never touch the phone again once they are on it — so the six digits were the whole of
their phone, and the one moment the app made them dig it out. **Join a match** on the watch's
start screen takes them instead. The code is six digits, so the watch puts a number pad of its
own on the screen rather than the system's letter keyboard, and the sixth digit joins without
another tap. The phone's join sheet opens on the number pad for the same reason.

The watch does not do the joining. It cannot: the local network and Bluetooth are both built
on iOS alone, and the only thing a watch can talk to is the iPhone it is paired with. So it
hands the code over and that phone goes looking — which is why the phone can stay in a bag,
but cannot stay at home. The wrist is told how it is going, and the match arrives on it the
way any match on that phone already does.

A join is live or it is nothing. Queued, it would be handed over twenty minutes later and go
looking for a match that finished, so nothing is kept: a code that did not reach the phone
says so on the wrist rather than leaving it watching a search nobody is running.

Hosting stays on the phone. A host advertises over Bluetooth, and a watch has no way to
advertise anything — `CBPeripheralManager` does not exist on watchOS — so there is no version
of this where the code is read out from a wrist.

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

The live heart rate never goes on the wire: it stays on the wrist that read it. What does go,
once a workout has ended, is the summary, and after it — read back out of Health rather than
kept as it came in, so a relaunch mid-workout loses none of it — how the heart rate and the
energy went over the workout, in fifteen-second steps. It is its own message, so ending a
workout never waits on the query, and the phone files it under `workoutSeries/`, beside the
workout rather than inside it. Both reach that one phone and no other:
`FanOutTransport.Scope.sharedSession` drops them, in the same exhaustive switch that drops
your saved setups, so adding a `Wire` case carrying anything personal is a compile error
rather than a leak.

None of it is required. Never press the button and the app is what it was: no prompt, no
Workouts row, no Health access of any kind.

## The timeline

Every event carries the moment the device that recorded it did, and a match is filed with a
timeline of itself: what each event did to the score, and when. It is read off the board
rather than off the events — every event is folded, and an entry is written wherever a
court's score moved — so a whistle or a typed score leaves its mark as a point does, a point
the reducer turned away leaves none, and the last entry on every court is always the score
that was filed. Each point knows who served it and whether it was a golden or star point or a
tiebreak point, and what it won. It lives in `timelines/`, beside the history rather than
inside its records, because the list decodes every record on every redraw.

Taking a result back, or picking a filed session up again, starts a fresh log from a restored
score, so the phone keeps a carry of what came before and the continuation is filed as one
match. The restore names the session a result was taken back from, which is also how a
take-back on the watch, or by the host, drops the "won" record the phone had already filed.

Opening a filed match shows two charts on one clock: who was ahead — the running difference
in points, in the colour of whoever led it, with the games ticked and each set's score where
it ended — and, from the workout that was running, the heart rate. Dragging across either
reads both. Under them are points won, the longest run, the golden or star points won and
breaks of serve. A tournament gets the heart rate with its rounds marked on it instead, and a
workout lists what each match played during it cost.

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
Project.swift              Tuist project: iOS app + embedded watchOS app and widget extension
Packages/RekkertKit/       the brain, as a local Swift package
  RekkertCore              scoring, tournaments, event log, persistence (pure Foundation)
                           — HealthKit must never reach here, or the tests need a simulator
  RekkertSync              WatchConnectivity transport and the observable MatchStore
App/                       iPhone SwiftUI
WatchApp/                  Apple Watch SwiftUI
Shared/                    the scoreboard and app model, used by both apps
Widgets/                   the Live Activity: its extension, and the attributes the app shares
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

Undo takes back the last thing that moved the board, not merely the last thing recorded. Two
devices drawing the same round or blowing the same whistle leave two of it in the log, and
only the first counts — so the second changed nothing, and taking back the first alone would
only let the second count instead. Undo takes back both. On a tournament court's own screen,
on the phone or the watch, it takes back only what was scored on that court: with a phone on
every court, court 2's Undo is not court 1's to use.

The point that won a match can be taken back from the result screen by anybody on it, which
reopens the match where it stood. The host's own Finish or Discard can be taken back only on
the host's side. Reopened, the match takes a name worked out from the one it was taken back
from, so two devices taking it back at once reopen the same match rather than one each — and,
each name following from the last, a host that saw only the first ending still knows the match
when it was won and taken back again out of its reach. A guest that takes the point back just as
the host starts its next match goes onto the host's, and the match it took back is filed as it
ended.

A shared match ends only on the host's side. The reducer would apply a Finish from any device,
so a host takes back any that reaches it from a phone other than itself or its own watch — an
older build that let a guest end it, say — and a guest whose copy that Finish ended is put
back on the match by it. A guest's own watch ending its copy alone ends nothing of the host's.

An event of a kind this build cannot read — recorded by a newer one — changes nothing here,
is kept in its place in the log and passed on unchanged, so a newer phone on the match never
stalls an older one.

Live updates go over `sendMessage`, whose reply doubles as an acknowledgement carrying the
peer's version vector — one round trip that both confirms delivery and reconciles.
Durability is an outbox we persist ourselves rather than `transferUserInfo`, which is not
supported on the watchOS Simulator. `updateApplicationContext` carries a whole-log snapshot
as the cold-start backstop. WatchConnectivity refuses a message, a reply or a queued transfer
over 64 KB and a context over 256 KB, without telling anybody, and a whole log is past 64 KB
by the middle of an evening's americano; anything too big goes as a file instead.

If a phone and a watch each end up with a session of their own, the more recently started
one wins and the other is archived to History rather than dropped. The watch keeps no History,
so what it lets go of it hands to its phone, which files it.

Between phones the same conversation runs over two links at once. The local network —
Bonjour over Network.framework, with the six-digit code as a TLS pre-shared key — is the
quick one, and iOS takes it away the moment the app stops being in front of somebody. So
Bluetooth runs alongside it: it is the only link the system will let an app hold open with the
screen off, which is what keeps two watches agreeing while both phones are in bags. A peer on
both hears everything twice, which costs bytes and nothing else, because merging is a union.

Bluetooth cannot carry the code in its advertisement — a backgrounded peripheral drops its
name and service data and moves its service UUID into an overflow area — so the UUID is fixed
and app-wide, and the code is checked after connecting instead: the host publishes a share id
and a one-byte fingerprint, and every frame is then sealed with a key derived from the code —
one key each way, so nothing that merely echoes a guest's frames back can pass for the host.
Neither end counts the other as on the match until something it sealed has opened, so a host
that agreed on the one byte by accident is hung up on and the next one tried. The host proves
itself first and sends the match after: behind a long log, the proof came too late to count.
Deriving the service UUID from the code would be worse than saying nothing, since twenty bits
of code under a hash broadcast in the clear comes straight back out.

Twenty bits keeps out anybody passing who was not told the code. It does not keep out somebody
in range who sets out to get in: one frame caught over Bluetooth, or one handshake against a
listener made to look like the host's, is enough to try every code offline. Only a
password-authenticated key exchange would close that, and a padel score is not worth one.

A Bluetooth link can stay up with nothing on the other end, so it is not taken at its word: a
host whose service goes away is hung up on and dialled again, three unanswered questions in a
row and a peer stops counting as there, and the radio switched off and on starts everything
afresh. A host that went away is looked for as well as dialled where it was, since an iPhone's
Bluetooth address moves on.

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
three-line regression test for the whole watch-embedding story. It does the same for the
Live Activity extension at `Rekkert.app/PlugIns/`, and for the plist key without which iOS
refuses to start one.

`.github/workflows/test.yml` runs `scripts/verify.sh` on every push, on any branch, unless
the push only touches `docs/`, a Markdown file, the listing in `fastlane/` or the licence.

The Live Activity shows on an iPhone simulator with a Dynamic Island once the app is sent
to the background — `xcrun simctl launch <udid> com.apple.Preferences` does it. A screenshot
hides the island, so record a second of video instead. A late tap timed to land after the
app had gone to the background never landed, so score the point before sending it away:
`-rekkert-demo traditional -rekkert-demo-points 5 -rekkert-demo-late-tap 3`.

The TV's board needs an external display. `simctl` can plug one in, but a screenshot of it
comes back black, so `-rekkert-demo-tv-shot` has the app draw what the TV shows into its own
container every couple of seconds. Size the display before launching: changing the mode of a
connected display plugs it in again, and iOS 27 does not always hand it back.

```sh
xcrun simctl io <udid> screenConfig --display=external power on
xcrun simctl io <udid> screenConfig --display=external geometry 1920x1080
xcrun simctl launch <udid> dev.natten.rekkert -rekkert-demo americano -rekkert-demo-tv-shot
cp "$(xcrun simctl get_app_container <udid> dev.natten.rekkert data)/tmp/tv.png" .
```

To exercise sync on paired simulators:

```sh
xcrun simctl pair <watch udid> <phone udid>
xcrun simctl boot <pair udid>
```

Debug builds accept `-rekkert-demo traditional|winnercourt|friendly|americano|mexicano` (plus
`-rekkert-demo-points N`, `-rekkert-demo-deuce`, `-rekkert-demo-rounds`,
`-rekkert-demo-friendly-rounds N`, `-rekkert-demo-friendly-players N`,
`-rekkert-demo-rounds-sheet`,
`-rekkert-demo-undo-draw`, `-rekkert-demo-browse-round N`, `-rekkert-demo-sit-outs [name]`,
`-rekkert-demo-open-court R,C`, `-rekkert-demo-roster`, `-rekkert-demo-presets`,
`-rekkert-demo-watch-page menu|standings|controls`, `-rekkert-demo-watch-join CODE`,
`-rekkert-demo-fullscreen`, `-rekkert-demo-board`, `-rekkert-demo-courts N`, `-rekkert-demo-tv-shot`, `-rekkert-demo-tv-guide`,
`-rekkert-demo-blackout`, `-rekkert-demo-settings`, `-rekkert-demo-swap-player`,
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
      -rekkert-demo traditional -rekkert-demo-points 5 -rekkert-share-host 730264
    xcrun simctl launch $GUEST dev.natten.rekkert \
      -rekkert-share-join 730264 -rekkert-demo-late-tap 14

`-rekkert-share-host CODE` pins the code instead of drawing one, `-rekkert-share-join CODE`
opens the join sheet with it filled in and submits, and `-rekkert-demo-late-tap N` scores a
point after N seconds — which is how a *live* update gets verified between two simulators
that nothing can tap.

`-rekkert-demo-watch-join CODE` is the wrist's half of the same thing: it opens the watch's
join sheet with the code in it and submits once the phone is reachable. Pointed at a guest
phone launched with no code of its own, it is how the whole path gets exercised — the watch
types, its phone goes looking, and all three end up on the host's log:

    # the watch here belongs to the GUEST, which is the whole point of it
    xcrun simctl launch $HOST  dev.natten.rekkert \
      -rekkert-demo traditional -rekkert-demo-points 5 -rekkert-share-host 730264
    xcrun simctl launch $GUEST dev.natten.rekkert
    xcrun simctl launch $WATCH dev.natten.rekkert.watchkitapp -rekkert-demo-watch-join 730264

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

## Releasing

A build goes to TestFlight when you ask for one: **Run workflow** on the TestFlight
workflow in the Actions tab, from whichever branch you pick, runs
`.github/workflows/testflight.yml`. Each run is listed under the `testflight` environment
in the repository's Deployments. The job runs on GitHub's Xcode 27 image and does what
`scripts/release.sh` does here — the package tests, an archive, the checks that the watch
app and the Live Activity are inside it, export, validation, upload — and then waits until
App Store Connect lists the build.

The build number is App Store Connect's highest plus one, or `CURRENT_PROJECT_VERSION` in
`Project.swift` if that is higher, and nothing is committed back: the number in the project
is a floor, not a record of what was sent. Uploads run one at a time, so two runs close
together never ask for the same number.

Each build's **What to Test**, the text under it in TestFlight, lists the commits it has
that the last successful run did not, whichever branch that was from: `feat:` under New,
`fix:` under Fixed, the rest under Other, with the prefix taken off, and the commit it was
built from at the end. The run's summary shows the same text. `scripts/test-notes.sh <commit>` prints what a build of HEAD would say over one
of `<commit>`, and `swift scripts/build-number.swift notes <number> <file>` puts a file on a
build that is already listed, which is how to give a build from this Mac its notes.

It needs six repository secrets, set once:

| Secret | What goes in it |
|---|---|
| `TUIST_DEVELOPMENT_TEAM` | The paid team id, as in `mise.local.toml` |
| `APP_STORE_CONNECT_KEY_ID` | The API key's id |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer id above the list of keys |
| `APP_STORE_CONNECT_KEY` | The whole `.p8` file. The key must be **Admin**, for the reason in `release.sh` |
| `DEVELOPMENT_CERTIFICATE_P12` | An Apple Development certificate and its private key, as base64 |
| `DEVELOPMENT_CERTIFICATE_PASSWORD` | The password the `.p12` was exported with |

The certificate is there because the archive is signed for development before export
signs it for distribution, and a fresh runner has no development identity of its own —
without one, Xcode would make a new certificate every run until the team ran out. Export it
from Keychain Access (My Certificates, the "Apple Development" one, Export…, with a
password), then:

```sh
base64 -i Certificates.p12 | gh secret set DEVELOPMENT_CERTIFICATE_P12
gh secret set DEVELOPMENT_CERTIFICATE_PASSWORD
gh secret set APP_STORE_CONNECT_KEY < ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
```

Uploading from this Mac still works, as long as it asks App Store Connect for the number
too rather than trusting the project's:

```sh
./scripts/release.sh --build-number=$(swift scripts/build-number.swift next)
```

`swift scripts/build-number.swift next` prints the number the next upload should carry, with
the same key `release.sh` uses. The listing below is not part of any of this and is still
sent by hand.

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
