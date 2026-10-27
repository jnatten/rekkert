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
side, so partners never serve back to back. Set up as singles, each side is one player and is
called by their name, so History lists the match as "Ada vs Bob" and the one player serves
every game their side does.

**Winner court** — you play games on a court until the organiser blows the whistle, then
move up or down. It comes two ways, picked when you set it up: **Our court** and **All
courts**.

On *Our court* a round is a set with no end: games just accumulate. The whistle banks
them and the next round starts at nil-nil. Scoring is 15/30/40 with the same deuce options
as a match. The app tracks only your own side of it — the round number and the games each
side won — so there are no courts, partners or standings to keep up to date. The whistle
usually interrupts a game, so the one in progress goes to whoever is ahead in it; level and
it is discarded.

*All courts* runs the whole evening. Every court is on the screen, court 1 at the top, and
when a round ends its winners go up a court and its losers down, court 1's winners and the
bottom court's losers staying where they are. Pairs can stay together all evening, taken
from the list two at a time, or be split after every round so that the two who just won
together face each other on the court above. The first round is placed as listed or
shuffled.

A round is timed or a match. Timed, it counts down from twelve minutes, or whatever you set,
while every court plays games on the 40–40 rule of your choice, golden point unless you
change it. The countdown can be paused, and more time added at any point, even once it has
run out. When it runs out every watch buzzes, the phone says "Time" if the announcer is on,
and a notification goes off on a phone in a pocket or a lowered wrist — but nothing ends
until the organiser blows the whistle. Then the game in progress on each court goes to
whoever leads it, and a court still level on games plays one deciding point, its receivers
picking the side. As a match, each court plays sets on the ordinary rules, and the next
round is drawn once every court is won. A timed court nobody kept can have its games typed
in, before the whistle or after it, until the next round is drawn; one still level after the
whistle is settled by tapping whoever won its deciding point.

Players over the courts sit out as in Americano, fewest sit-outs first, and come back in on
the bottom court; a fixed pair sits out together. Each round is drawn from how the one before
finished by the device that draws it, and the draw carries who it put where, so every other
device takes it as it is rather than working it out again. The next round is only offered
once every court is settled, but once it is drawn it stays: a point that arrives late — one
that raced the whistle, say — can change a score, never a round people have walked onto.
The table is the ladder — the last round's finishing order, court by court and
winners above losers, with rounds won and games beside it — and the evening is won by
whoever won court 1 last.

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
paired 1+4 vs 2+3. The device that draws a Mexicano round works it out from the table, and
the draw carries who it put where, so a point or a correction that turns up late — two
devices taking a court's last point at once, say — can change the table but never a round
people have walked onto. Player counts that are not a multiple of four rotate sit-outs by
whoever has sat out least and, of those, whoever sat out longest ago, so nobody is benched
again sooner than the numbers force. Benched players score a configurable number of points
(half the target by default). Until the first point of a round, who sits it out can be
changed on the phone — for whoever is late — and the round is drawn again around the pick.
A picked sit-out counts like any other, so whoever it spared is next in line.

A tournament plays on until it is finished, unless setup gives it a **Length**: a number of
rounds, or — in Americano — a full rotation, which runs until everybody has partnered
everybody. A cancelled round does not count towards either. The courts screen says how far
along it is, and once the last planned round is played out the phone that may finish asks,
once, whether to finish or play another round. Nothing finishes by itself and there is always
another round; past the plan, Finish tournament moves to the top. A full rotation takes at
least as many rounds as the partnerships allow — 7 for 8 players on 2 courts — and the draw,
picking one round at a time, sometimes needs one more; with players sitting out it can take
several more.

On the phone, the court list is the main tournament screen: every court with its score,
plus standings and round history. Scores can be tapped in point by point, typed, nudged
with a stepper, or picked from a list of results — in "total points played" mode both
halves always add up to the target, so one tap settles a court. Each court has a pair of
team colours of its own — court 1 blue and orange, court 2 purple and green, and so on —
the same on the phone, the watch, the TV and the Lock Screen.

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
reached its target (level is a draw), every round on a winner court up to the last whistle, every settled court on a ladder,
every friendly round somebody won, and every americano court played out or confirmed. A match
called off without a winner, a friendly round stopped where it stood and a court left part-way
when a tournament was saved count for nobody. Rounds on the bench are left out of the points,
and so is what they were worth. Winner court on Our court counts for the record and the
partners but not head-to-head, since the other side of the net changed at every whistle; on
All courts the app knows who was across the net, so it counts for all three, though in games
rather than points. A session picked up
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
It only counts, except on a winner-court ladder played in timed rounds: there it counts the
round down instead, and past the end counts the time over, in orange. Pausing, resuming and
adding time travel like a point does, as the whole clock rather than the change to it, so
two people adding two minutes at the same moment add two minutes.

The moment a round started travels with the round, so the phone, the watch and a guest's
phone all count from the same one — a guest joining halfway through picks the round up
where it actually is rather than at nil. Two devices drawing a round at the same instant
settle on one of the two stamps, the same way they settle on one draw. Clocks that disagree
by a second or two show it, which is as close as two wristwatches ever get.

A board that is over is not timed: a match somebody has won, a friendly round that has been
played out or called off, a tournament round already confirmed, and any earlier round you
have gone back to look at. The full-screen board has no clock either — it is the two
numbers and nothing else, read from the far end of the court.

## Warm-up

Turn on **Warm-up** while setting up a game, in any mode, and it opens on a warm-up instead
of the score: a clock counting up from nil, your heart rate on the watch while a workout
runs, and **Start game**. Nothing is scored during it. Start game, on any phone or watch
that may run rounds, ends it for everybody and starts the game's clock from that moment. A
tournament's first round is still drawn as the session starts, and its clock, a timed
ladder's countdown included, starts again with the game. The phone shows that a workout is
running but not the number, which stays on the wrist as it always has. The form remembers
the switch from one game to the next, and a preset keeps its own. An older build on the
other end does not know about warm-ups and goes straight to the score.

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
side and who is sitting out, and between rounds who plays next. An americano, a mexicano or
a winner-court ladder puts every court of the round up at once — both pairs, the score and
who serves, and a ladder's games and countdown — with the table beside them and the bench
along the bottom. The table shows as many rows as fit. Above
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

On Home, press and hold a preset to change its setup or rename it, or tap the pencil to
drag them into order. The watch lists them in the same order, and a new one goes on top.

## Joining with the camera

The share sheet shows the code twice: as six digits to read out, and as a QR code holding
`https://rekkert.natten.dev/join#482915`. The Camera, the Code Scanner in Control Center and
**Scan the host's code** on the join sheet all open Rekkert on it and join without typing. A
host opening their own link gets the share sheet back instead, since joining would end the
sharing. Any other link on a phone that is hosting, or following a match still in reach, fills
the join sheet in but does not send it: joining would stop the sharing for everyone on it, or
leave the match being followed, and a link is too easy to tap for that to happen unasked. The
sheet says what it costs and the button says what it does, and typing a code there asks the
same question.

It is a universal link. `docs/.well-known/apple-app-site-association` gives `/join` to the app,
and `docs/.nojekyll` stops GitHub Pages leaving the `.well-known` folder out. Apple fetches that
file through its own CDN, so a change to it takes hours to reach phones. A phone without Rekkert
opens `docs/join/index.html` instead, which shows the code and what to do with it. The code is in
the fragment, which a browser never sends, so the website never sees it and there is still no
server that knows a match exists.

The camera is asked for only once the scan button is tapped, and only a Rekkert join link in front
of it does anything. The watch has no camera, and a wrist joins by typing as before.

## Joining from the wrist

Most people at a shared match only ever join one. They host nothing, set nothing up, and
never touch the phone again once they are on it — so the six digits were the whole of
their phone, and the one moment the app made them dig it out. **Join a match** on the watch's
start screen, or in the menu of a match already on it, takes them instead. The code is six
digits, so the watch puts a number pad of its own on the screen rather than the system's letter
keyboard, and the sixth digit joins without another tap. The phone's join sheet opens on the
number pad for the same reason.

The watch asks its phone, which has the local network as well as Bluetooth and keeps its link
with the screen off, and dials the host's phone itself over Bluetooth at the same time, since a
phone in a bag may not see a host that a watch held up can. Whichever gets there first puts the
match on the wrist, and the phone is left to get there too. When neither does, the watch says
why within fifteen seconds — nothing on that code nearby, Bluetooth off, or no room on the
match — giving the host's refusal whoever heard it, and otherwise the phone's reason. Without
the app in front or a workout the watch may not dial, so it gives the phone twelve seconds
before looking itself. So the phone can stay in a bag, or at home.

Once on, the watch follows through its phone for as long as that phone is through to the host.
A phone out of touch for fifteen seconds is stood in for: the watch keeps a link of its own to
the host, and hands the match back once the phone is through again. The host counts the two as
one person. watchOS lets an app hold a link of its own only while it is in front or running a
workout, so that is when the wrist stands in; otherwise, with the phone's app ended too, it
says the phone needs opening.

A join is live or it is nothing: it is never queued for a phone to find twenty minutes later,
when the match it was for has finished. What is kept is the code of a match the wrist got onto,
for twelve hours, so **Join again** — on the start screen and in the menu — puts it back on
without typing, and a watch whose app was ended goes back on by itself. Join again on a match
nobody shares any more says there is nothing on that code nearby, and forgets it. **Leave**
asks first, because the phone leaves with it.

A guest's phone that joins takes its watch along: the shared match replaces anything of the
watch's own, which goes to History. A watch that cannot be reached just then gets a
notification on the wrist to tap, and one with a match of its own while its phone is on a
shared one says so, with **Get on it**.

The host's watch shares too. A watch cannot advertise — `CBPeripheralManager` does not exist
on watchOS — so the phone still does the hosting, but it can be run from the wrist with the
phone in a bag. **Share match**, in the menu of a match of the watch's own, asks the phone to
share it, and shows the code as six digits to read out and as a picture of the join link for an
iPhone's Camera. The phone draws the picture, since watchOS has no Core Image, and sends it
over. **Who's on** lists everybody on the match — in step, catching up, or out of reach since
when — and **Stop sharing** ends it for all of them, each keeping their copy in History.
Joining another match from a watch whose phone is sharing asks first, since it stops the
sharing for everyone on it. None of this shows on a guest's watch.

## Who may do what

Whoever joins can score, correct and run the rounds, as they always could. The host can
narrow that from the share sheet. **New phones join as** sets what a phone gets on arrival —
*Full access*, *Only score* or *Read-only* — and is remembered for the next time you share.
Every phone that has joined is listed under it, by the player its owner said they were, and
each can be given a level of its own or put back on the default.

*Only score* is everything on a court: points, a typed or stepped score, the serve and the
deciding point's side, and taking those back. Not the whistle, drawing or confirming a round,
the round clock, who sits out or the change-ends rule; and an Undo that would take back one of
those is not offered. *Read-only* follows the match and changes nothing. Finishing it stays
the host's whatever the level, as before, and so does the question a tournament asks when its
planned rounds are played. A guest's watch goes by its phone's level.

Joining asks **Who are you?** once the match is on the phone, offering its players and *Just
watching*; the match menu changes the answer later, and in a tournament it is the same choice
as who you are playing as. The name is kept for the host's next match on the same code. A
phone that has not said is listed as Phone 1, Phone 2 and so on. The host can answer it too,
from the match menu, and the guests then call the match by it — "Ada's match" on their phones
and watches, "Ada stopped sharing" at the end — where it would otherwise be a shared match and
the host.

It is a convention rather than a lock, like the host's sole right to finish: each phone hides
what it has been told it may not do, and nothing stops a modified one. A phone on an older
Rekkert never hears the levels, is not listed, and can do what it always could.

## Workouts

The watch can record a workout while you play. It is a button — on the watch's menu page,
on its idle screen, and in the iPhone's main menu — and unless Settings says otherwise it
has nothing to do with matches: it never starts itself, it survives a match ending, and you
can play none, one or six of them while it runs.

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

It can follow the match instead, for somebody who asks. Settings has two pickers under
*Workout on your watch*, one for when a match starts and one for when it ends, each with Do
nothing, Ask me, or the thing itself. Both are off until changed, and they travel to the
watch with the buzz settings.

- **A start** is acted on by the device the match was started, resumed or joined on. The
  phone goes through `startWatchApp`, as its own Start button does. A join typed on the wrist
  belongs to the wrist even when the phone carries it out. The host's next match on a code
  kept all evening is a start for its guest. Rounds, the watch following its phone's match,
  and a result taken back are not starts.
- **An ending** is the watch's alone. It holds the workout, and the workout keeps it running,
  so it hears the match end wherever the last point went on. Won, finished, called off, ended
  by the host and stepped off all count; a match replaced by a newer one does not.
- **An automatic stop waits a minute**, with a countdown and Keep going on the watch's result
  screen. Another match starting, or the final point taken back, calls it off, so three
  matches back to back stay one workout.
- **Health is asked up front.** Choosing a start asks for access on the phone, and the watch
  asks the next time it is opened: a start sent from the phone reaches a watch in a pocket,
  where no prompt can be shown.

The moments come out of `MatchStore.onMatch`, and the whole decision is `WorkoutFollow`, a
value with the clock passed in, so every turn of it is tested rather than tried.

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

When a workout ends, the watch asks how hard it was, on the same 1–10 scale the Workout app
uses: Easy, Moderate, Hard, All Out. Turn the crown or tap the bar. The phone asks as well if
the app is open when the workout ends. Answering or skipping on one device puts the question
away on the other, and the workout's page on the phone has an Effort row for rating it later
or changing the answer. Health only takes the rating as a sample related to the workout, so
the watch, which holds the workout and the Health access, is the one that writes it. A rating
given on the phone is filed there at once and sent to the watch on the durable queue, and
reaches Health whenever the watch app next hears it — or, if the watch was locked then or had
not yet been asked for access to the score, the next time the app is opened on it. The watch
keeps only the last week or so of Health, and a workout it no longer has cannot take a
rating, so the phone offers the row for five days after a workout and shows any rating
read-only after that. Health makes no estimate of its own for another app's workout, so
there is no suggested value to start from.

The live heart rate never goes on the wire: it stays on the wrist that read it. What does go,
once a workout has ended, is the summary, and after it — read back out of Health rather than
kept as it came in, so a relaunch mid-workout loses none of it — how the heart rate and the
energy went over the workout, in fifteen-second steps. It is its own message, so ending a
workout never waits on the query, and the phone files it under `workoutSeries/`, beside the
workout rather than inside it. Both reach that one phone and no other:
`FanOutTransport.Scope.sharedSession` drops them, in the same exhaustive switch that drops
your saved setups, so adding a `Wire` case carrying anything personal is a compile error
rather than a leak.

None of it is required. Never press the button, leave both pickers on Do nothing, and the
app is what it was: no prompt, no Workouts row, no Health access of any kind.

## Apple Health

Settings has an Apple Health section on every iPhone and iPad, watch or no watch, under
Apple's own icon. App Review turned down a build for using Health without saying so on any
screen it could reach, and every other mention needs a paired watch. The section says what
Rekkert does with Apple Health and, where a workout cannot be recorded, why not; a row opens
the whole list of what is saved and read, and where in the system's settings to change it.

All of it is read from `HealthDisclosure`, which is also what both apps build their Health
requests from, so the words cannot drift from what is collected and the tests pin both. The
first time either device would put up Health's permission sheet, it explains itself first,
and only while Health says the sheet would actually appear. Every control that starts a
workout names Apple Health beside it, never "Health" alone, and a test holds the wording.

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

## The help screen

**How Rekkert works**, behind the ? on Home and at the foot of a match's options menu, explains
every mode and every button on the watch and the phone. It never opens by itself: it is there for
whoever goes looking, a topic at a time, with each control a line long until it is tapped.

What it says lives in `RekkertCore/Help/HelpCatalog.swift`, as data the tests can read; the app
only draws it. Three things keep it from falling behind the app:

- A new `GameMode` does not compile until it has its `help` and a `HelpSample` to draw its board.
- `HelpTests` reads every SF Symbol named in `App/`, `WatchApp/` and `Shared/`, and fails on one
  the help neither explains nor lists in `selfExplanatory` with a reason. A new button is a
  failing test until it is explained; a symbol the help explains that neither app shows any
  more fails too.
- It fails as well on a `##` section of this README, from Modes up to Getting started, that no
  page names in its `readme`. CI skips a push that only touches Markdown, so a new section is
  caught by the next push with code in it, or by `swift test` here.

The tests hold each line short — eighty characters for what a control does, a hundred for the
example — because nobody at the side of a court reads a paragraph.

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

Between the host's matches a guest stays on the code, and the host's next match opens on it by
itself. Home shows the sharing glyph in its corner as a match screen does, so that is never a
surprise, and tapping it there is the way off.

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
Each connection is proved afresh: the guest opens with a nonce, the host answers with it and one
of its own, and the guest confirms with the host's, so a frame caught on one connection proves
nothing on the next. Every frame after that is bound to both nonces and numbered, so it opens
once, and only there. Neither end counts the other as on the match until it has proved itself,
so a host that agreed on the one byte by accident is hung up on and the next one tried. The
snapshot the phone publishes on every point is not carried on this link, which manages a few
kilobytes a second: once it is up, each end says hello and is sent only what it is missing. A
whole log still crosses it when nothing less will do — the first copy to a phone arriving with
nothing on, and the farewell when a match ends.
Deriving the service UUID from the code would be worse than saying nothing, since twenty bits
of code under a hash broadcast in the clear comes straight back out.

Twenty bits keeps out anybody passing who was not told the code. It does not keep out somebody
in range who sets out to get in: one frame caught over Bluetooth, or one handshake against a
listener made to look like the host's, is enough to try every code offline. Only a
password-authenticated key exchange would close that, and a padel score is not worth one.

A Bluetooth link can stay up with nothing on the other end, so it is not taken at its word: a
host whose service goes away is hung up on and dialled again, three unanswered questions in a
row with nothing arriving meanwhile and a peer stops counting as there, and the radio switched
off and on starts everything afresh. Liveness runs both ways, because a guest that is only
following has nothing of its own to say. It says hello whenever ten seconds pass with nothing
sent, and hangs up and dials again when three of those go unanswered. A host keeps the link to
a guest it has stopped counting, and goes on asking after it every fifteen seconds rather than
falling silent on it. A host that went away, or was hung up on for not answering, is looked for
as well as dialled where it was, since an iPhone's Bluetooth address moves on; one that proved
itself once is never written off for being slow to do it again, and a connection that comes
back before the host's service does is let go of and found again.

What is waiting to go out goes a piece for each guest in turn, and the turn carries over from
one moment the radio has room to the next, so the guest after the last one served goes first:
however few pieces iOS takes at a time, every guest gets its share. Each guest's own queue goes
handshake first, then the latest points, then catching up, and catching up is cut small enough
for everybody else's points to go in between. Each guest is sent only what it is missing,
worked out from what its last hello said it had, and nothing goes back on the link it came in
on. The outbox lets an event go once everybody still on has it; a guest out of reach for a
minute does not hold it up, and is caught up from its hello when it comes back.

The host knows who is on by the device that proved itself rather than by the link, so a phone
and the watch standing in for it count once, and **Who's on** can name them. It takes seven: the
eighth is told there is no room, rather than let in to starve the others.

iOS wakes a suspended app for traffic on the link. The phone's two Bluetooth managers are also
set up for state restoration, so for an app iOS has ended to free memory it goes on advertising,
keeps the service published and keeps pending connections, and launches the app again in the
background when a guest connects or the host turns up. An app swiped away by hand is the
exception: iOS takes that as meant, and nothing moves on the radio until the phone is opened
again.

A drop is not a refusal. `ReconnectPolicy` decides what losing a connection means, and the
only thing that tells a wrong code from a host who walked off is whether anything ever worked.
Nor is every failed dial one: only the handshake refusing the key counts against the code, and
even that is held until the search runs out, since one byte of fingerprint agrees with another
court's now and again — the right match, found after it over either link, still counts.
Guests keep dialling on a timer rather than waiting for a Bonjour change that never comes, and
a reconnect merges rather than replaces — both sides keep whatever they scored while apart. If
the merged score is one nobody recognises, the host can settle it from the match menu. A guest
whose host has been gone for fifteen seconds says so, and since when — on the phone's sharing
badge and on the watch — and goes on scoring meanwhile. One with Bluetooth off, or not allowed,
and nothing else reaching the host says that instead, since it is the thing to put right. The
watch says it too while it still hears its phone; with Wi-Fi off, Bluetooth switched off in
Settings takes the watch's link to its phone with it, and the watch can only say the phone is
out of reach.

The code is kept in the Keychain of every device that has been on the match: the host's phone,
with the share id its keys are derived from, and each guest's phone and watch. It is kept for
this device only, so it is never synced or backed up, and readable after the first unlock, so
an app launched in the background with the phone locked still finds it. It lasts twelve hours,
checked whenever it is read, since a Keychain item can outlive the app. Every launch looks for
it. A host comes back on the same code, between matches too, and its guests
find it again by themselves; a guest that was on the match when its app was ended goes back on.
Stop sharing clears the host's. A guest forgets its copy when told sharing has stopped, replaces
it on joining another match, and keeps it after Leave, for Join again.

## The sharing record

Something that goes wrong at a court is gone by the time anyone at a desk hears about it, so
every phone and watch keeps a record of what happened to its links: launched and how, sharing
started, restored or stopped, a guest proven, joined, out of reach or back in step, a link
dropped and why — timed out, radio off, closed by the other end, hung up on — a join refused
for a wrong code or no room, a wrist standing in or down, and the notification that brought a
watch round. An app that was ended cannot write
that it was, so a launch that finds a kept code writes "app had been ended" instead, which
is what tells a host's phone killed in a bag apart from a watch that lost its phone.

It is a file a day, in Application Support and left out of backups, and a week of it is kept.
The watch writes its own and sends it to the phone with `transferFile`, durable, whenever the
phone can be reached; the phone puts the two together by time. **Settings → Sharing record**
shows it, and **Share** exports it as plain text, one line an entry, in the format
[`specs/001-fix-session-sharing/contracts/sharing-record.md`](specs/001-fix-session-sharing/contracts/sharing-record.md)
sets out and `LinkRecordTests` reads back. There are no names, scores or codes in it, and
devices go by four hex digits of their random id. Debug builds also note how long each point
took to arrive.

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

Debug builds accept `-rekkert-demo traditional|winnercourt|friendly|americano|mexicano|ladder` (plus
`-rekkert-demo-minutes N`, `-rekkert-demo-split`, `-rekkert-demo-warmup`, `-rekkert-demo-points N`, `-rekkert-demo-deuce`, `-rekkert-demo-rounds`,
`-rekkert-demo-friendly-rounds N`, `-rekkert-demo-friendly-players N`,
`-rekkert-demo-rounds-sheet`,
`-rekkert-demo-undo-draw`, `-rekkert-demo-browse-round N`, `-rekkert-demo-sit-outs [name]`,
`-rekkert-demo-open-court R,C`, `-rekkert-demo-roster`, `-rekkert-demo-presets`,
`-rekkert-demo-watch-page menu|standings|controls|workout|presets|code|follow-phone`, `-rekkert-demo-watch-join CODE`,
`-rekkert-demo-fullscreen`, `-rekkert-demo-board`, `-rekkert-demo-courts N`, `-rekkert-demo-tv-shot`, `-rekkert-demo-tv-guide`,
`-rekkert-demo-blackout`, `-rekkert-demo-settings`, `-rekkert-demo-swap-player`,
`-rekkert-demo-workouts`, `-rekkert-demo-workout`, `-rekkert-demo-workout-paused`, `-rekkert-demo-effort`,
`-rekkert-demo-apple-health`, `-rekkert-demo-settings-apple-health`, `-rekkert-demo-health-explainer` (phone or watch),
`-rekkert-demo-voices`, `-rekkert-demo-help [page id]` or
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
opens the code's join link as a scanned QR code would, which fills in the join sheet and submits, and `-rekkert-demo-late-tap N` scores a
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
scores and brought back to catch up from the log, and then the host's app ended and launched
with no code at all, to come back on the one it kept and reach a guest nobody touched.
`--no-build` reuses the last build, `--keep` leaves the simulators up.

On the watch paired with the host, `-rekkert-demo-watch-page code` opens the menu with the
code over it, as **Code** does. `-rekkert-demo-watch-page follow-phone` puts up the banner a
guest's watch shows when its phone is on a shared match and the wrist is not.

`-rekkert-share-access readOnly|score|full` sets what phones joining the host get,
`-rekkert-demo-share-sheet` opens the host's share sheet, and `-rekkert-share-as NAME` answers
the guest's "Who are you?" with that name.

Four things the Simulator cannot show you. The peer-to-peer radio path — there is no AWDL
interface, so `includePeerToPeer` is quietly a no-op — and the iOS local-network permission
prompt. And `BluetoothTransport`, which is inert there: the simulator runs no `bluetoothd`, so
CoreBluetooth's XPC connection is refused and everything above goes over the local network.
And a phone in a pocket, because a backgrounded simulator app is not suspended — its listener
and its sockets stay up, which is the one condition the Bluetooth link exists for. All of them
need two real iPhones.

Bluetooth state restoration needs one more thing on them: an app ended the way iOS ends it, not
swiped away, since iOS restores nothing for an app its user closed. Debug builds have **End app
as the system would** at the foot of Settings for that.

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

The listing text lives in `fastlane/metadata/`, one plain file per field, and is the source
of truth rather than the web form:

    fastlane/metadata/copyright.txt          # not localised, so these sit at the top
    fastlane/metadata/primary_category.txt
    fastlane/metadata/secondary_category.txt
    fastlane/metadata/en-US/name.txt
    fastlane/metadata/en-US/subtitle.txt
    fastlane/metadata/en-US/description.txt
    fastlane/metadata/en-US/keywords.txt
    fastlane/metadata/en-US/promotional_text.txt
    fastlane/metadata/en-US/privacy_url.txt
    fastlane/metadata/en-US/support_url.txt
    fastlane/metadata/en-US/marketing_url.txt
    fastlane/metadata/review_information/notes.txt   # what App Review reads first

`deliver` reads a fixed set of names, and the one not here yet is `release_notes.txt`
(What's New, per version, which the first version does not have). Add a file and it starts
being uploaded. The review contact is left to the web form, so the phone number stays out
of a public repository.

A video or file for App Review goes in `fastlane/review_attachment.<ext>`, which is
gitignored. `deliver` removes the attachment on every metadata upload it is not handed one
for, so without that file a `--metadata` run takes away one attached in the web form. The
one for the Apple Health review is two iPhone screenshots side by side, taken with
`-rekkert-demo-settings-apple-health` and `-rekkert-demo-health-explainer` on a simulator
with no watch paired.

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

The shots come from an iPhone 17 Pro Max, an iPad Pro 13-inch and an Apple Watch Ultra 3;
set `REKKERT_SHOTS_PHONE`, `REKKERT_SHOTS_IPAD` or `REKKERT_SHOTS_WATCH` to shoot a listing
slot of another size. The iPad's set has no workouts in it: an iPad cannot pair a watch, so
the app never shows one there.
App Store Connect is the only thing that knows which pixel sizes it accepts this month, so
the script prints what it made rather than claiming the sizes are right.

Some of what a submission needs is set once in App Store Connect and has no file here:
price and availability, the App Privacy answers (Data Not Collected, as the privacy
manifests say), the content rights question, the age rating and the review contact.
