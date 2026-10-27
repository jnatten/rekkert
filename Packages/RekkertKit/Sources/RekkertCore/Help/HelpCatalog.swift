/// Everything the help screen says. `HelpTests` holds it to the screens: a symbol drawn on
/// either app that is in neither `explainedSymbols` nor `selfExplanatory` fails the tests, and
/// so does a README section about a feature that no page covers.
public enum HelpCatalog {
    public static let pages: [HelpPage] = watchPages + modePages + phonePages

    public static var explainedSymbols: Set<String> {
        Set(pages.flatMap(\.items).flatMap { [$0.symbol].compactMap(\.self) + $0.alsoSymbols })
            .union(GameMode.allCases.map(\.symbol))
    }

    /// Drawn on screen, but saying what they are would only say what they look like.
    public static let selfExplanatory: [String: String] = [
        "antenna.radiowaves.left.and.right.slash": "the picture on a join that found nothing",
        "camera": "the scanner asking for the camera",
        "checkmark": "the ticked row in a list",
        "checkmark.circle.fill": "a done tick on the TV's board and in its guide",
        "clock": "when a match was played, and an empty History",
        "delete.left": "the watch keypad's delete key",
        "doc.text.magnifyingglass": "the sharing record in Settings, beside its name",
        "exclamationmark.triangle": "a warning, beside what it warns about",
        "exclamationmark.triangle.fill": "a warning, beside what it warns about",
        "list.bullet": "the watch's presets page with nothing on it",
        "plus": "adds a player while setting up",
        "tennisball.fill": "who serves, on the TV's board",
        "xmark": "closes full screen and the iPad's board",
    ]

    /// README sections about something the help leaves out, and why.
    public static let notInHelp: [String: String] = [:]

    private static let modePages: [HelpPage] = GameMode.allCases.map { mode in
        HelpPage(
            id: "mode.\(mode.rawValue)",
            chapter: .modes,
            title: mode.title,
            symbol: mode.symbol,
            whereToFind: mode.subtitle,
            picture: .board(mode),
            readme: ["Modes"],
            items: []
        )
    }

    private static let watchPages: [HelpPage] = [
        HelpPage(
            id: "watch.score",
            chapter: .watch,
            title: "The score",
            symbol: "applewatch",
            whereToFind: "Open Rekkert on your watch",
            picture: .watchScore,
            readme: ["The clock"],
            items: [
                HelpItem(
                    "Tap a side",
                    what: "Gives that team the point.",
                    example: "You won the rally: tap your colour before the next serve.",
                    spot: HelpSpot(0.1, 0.27)
                ),
                HelpItem(
                    "Hold a side",
                    what: "Takes the last point back.",
                    example: "You tapped the wrong half mid-rally.",
                    spot: HelpSpot(0.9, 0.27)
                ),
                HelpItem(
                    "Undo",
                    symbol: "arrow.uturn.backward",
                    what: "Takes the last point back, the same as holding a side.",
                    example: "The point went to the wrong team. One tap puts it right.",
                    spot: HelpSpot(0.26, 0.79)
                ),
                HelpItem(
                    "Serve badge",
                    what: "The lit half is where the serve goes from, drawn as you see the court.",
                    example: "Lost track mid-game? It says who serves and from which side.",
                    spot: HelpSpot(0.1, 0.62)
                ),
                HelpItem(
                    "Workout heart",
                    symbol: "heart.fill",
                    also: ["pause.fill"],
                    what: "Your pulse while a workout runs; grey while it's held. Tap to open it.",
                    example: "Check your heart rate between points without leaving the score.",
                    spot: HelpSpot(0.1, 0.14)
                ),
                HelpItem(
                    "Top line",
                    what: "The set or round, and how long it's been going. Yellow: out of touch.",
                    example: "\"Reconnecting…\" in yellow: the host's phone is out of reach for now.",
                    spot: HelpSpot(0.5, 0.14)
                ),
                HelpItem(
                    "Games line",
                    what: "The games in each set, the one being played in bold.",
                    example: "Check it's 3–1 before you change ends.",
                    spot: HelpSpot(0.62, 0.84)
                ),
                HelpItem(
                    "Receivers pick",
                    what: "At a golden or star point, tap the half the receivers chose.",
                    example: "40–40 on golden point and they want it on the left.",
                    only: "Golden and star point",
                    spot: HelpSpot(0.06, 0.93)
                ),
                HelpItem(
                    "Swipe or turn",
                    what: "Up or the crown: fixes. Left: the menu. Right: the workout.",
                    example: "Started with the wrong server? Swipe up to Swap serve.",
                    spot: HelpSpot(0.9, 0.14)
                ),
            ]
        ),
        HelpPage(
            id: "watch.fixes",
            chapter: .watch,
            title: "Fix the match",
            symbol: "arrow.left.arrow.right",
            whereToFind: "Swipe up from the score, or turn the crown",
            picture: .watchButtons,
            readme: ["Mid-match corrections"],
            items: [
                HelpItem(
                    "Swap serve",
                    symbol: "arrow.left.arrow.right",
                    what: "Hands the serve to the other team, and the rotation after it.",
                    example: "You spun for serve after you'd already started scoring."
                ),
                HelpItem(
                    "Swap player",
                    symbol: "person.2.arrow.trianglehead.counterclockwise",
                    what: "Gives the serve to the server's partner.",
                    example: "Jonas served, but the board had Ada down.",
                    only: "When both servers are named"
                ),
                HelpItem(
                    "Swap colours",
                    symbol: "circle.lefthalf.filled",
                    what: "Swaps the two teams' colours, here and on the phone.",
                    example: "Your side wears orange, so you'd rather be the orange team."
                ),
                HelpItem(
                    "I'm the orange team",
                    symbol: "person.fill",
                    what: "Tells this watch which team is yours.",
                    example: "The serve badge is drawn from your end, and your buzz knows your points."
                ),
                HelpItem(
                    "Fix score",
                    what: "Sets a court's points directly, with + and − or the crown.",
                    example: "Three rallies went unscored. Step it to 11–9.",
                    only: "Americano and Mexicano"
                ),
            ]
        ),
        HelpPage(
            id: "watch.menu",
            chapter: .watch,
            title: "The menu",
            symbol: "list.bullet",
            whereToFind: "Swipe left past the score",
            picture: .watchButtons,
            items: [
                HelpItem(
                    "End round",
                    symbol: "flag.pattern.checkered",
                    what: "Winner court: the whistle. Friendly: stops the round where it is.",
                    example: "The organiser blew the whistle. Bank the games and start round 2.",
                    only: "Winner court and Friendly"
                ),
                HelpItem(
                    "Next round",
                    symbol: "arrow.right.circle.fill",
                    what: "Closes the round and draws the next. Past the planned rounds: Another round.",
                    example: "Every court is done. Draw round 3 from the wrist.",
                    only: "Americano, Mexicano and Friendly"
                ),
                HelpItem(
                    "Me: Ada",
                    symbol: "person.crop.circle",
                    what: "Says which player you are.",
                    example: "Only your court buzzes, and the watch opens on it each round.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "Undo",
                    symbol: "arrow.uturn.backward",
                    what: "Takes back the last thing that moved the score, on any court.",
                    example: "Somebody drew the next round too soon."
                ),
                HelpItem(
                    "Finish & save",
                    symbol: "stop.circle",
                    what: "Ends it and files it in History on the phone.",
                    example: "The court booking's up. Keep what you played."
                ),
                HelpItem(
                    "Discard",
                    symbol: "trash",
                    what: "Ends it without saving. It says Call it off if nothing's been played.",
                    example: "You started a match by mistake."
                ),
                HelpItem(
                    "Join again",
                    symbol: "arrow.right.circle",
                    what: "Takes a new code for a shared match the watch lost.",
                    example: "The host restarted Rekkert and reads out a new code.",
                    only: "On someone else's match"
                ),
                HelpItem(
                    "Leave",
                    symbol: "rectangle.portrait.and.arrow.right",
                    what: "Steps off someone else's match.",
                    example: "You're done playing, but the host carries on.",
                    only: "On someone else's match"
                ),
                HelpItem(
                    "iPhone connected",
                    symbol: "iphone.radiowaves.left.and.right",
                    also: ["iphone.slash", "applewatch.radiowaves.left.and.right"],
                    what: "Whether the watch can reach your iPhone, or the host's.",
                    example: "Grey: keep scoring. The phone catches up when they meet again."
                ),
            ]
        ),
        HelpPage(
            id: "watch.wrist",
            chapter: .watch,
            title: "Your wrist",
            symbol: "hand.tap",
            whereToFind: "Further down the menu",
            picture: .watchButtons,
            items: [
                HelpItem(
                    "Sides: Static",
                    symbol: "lock",
                    also: ["iphone.radiowaves.left.and.right", "hand.tap"],
                    what: "How the halves sit: fixed, following the phone, or as you swap them.",
                    example: "Follow phone: turn the phone at a change of ends and the watch turns too."
                ),
                HelpItem(
                    "Swap sides",
                    symbol: "rectangle.2.swap",
                    what: "Turns this watch's board round.",
                    example: "You changed ends and want your team on your side of the screen."
                ),
                HelpItem(
                    "Buzz: Every point",
                    symbol: "hand.tap",
                    what: "Off, a tap every point, or one tap for your point and two for theirs.",
                    example: "Know who won the rally without looking at your wrist."
                ),
                HelpItem(
                    "Swap phone sides",
                    symbol: "rectangle.2.swap",
                    what: "Turns the phone's board round, from your wrist.",
                    example: "The phone is propped up at the net, facing the wrong way."
                ),
                HelpItem(
                    "Tap anywhere to score",
                    symbol: "applewatch",
                    what: "One tap anywhere: your point. Two: theirs. Hold: undo.",
                    example: "Score without aiming at a half mid-match.",
                    only: "Turned on in the phone's Settings"
                ),
            ]
        ),
        HelpPage(
            id: "watch.workout",
            chapter: .watch,
            title: "Workout",
            symbol: "figure.tennis",
            whereToFind: "In the menu, and right of the score",
            picture: .watchButtons,
            readme: ["Workouts"],
            items: [
                HelpItem(
                    "Start workout",
                    symbol: "figure.tennis",
                    what: "Records a tennis workout in Health while you play.",
                    example: "Count the evening's padel towards your rings."
                ),
                HelpItem(
                    "Pause workout",
                    symbol: "pause.circle",
                    also: ["play.circle"],
                    what: "Holds the workout. Resume picks it back up.",
                    example: "Waiting twenty minutes for a court shouldn't count as exercise."
                ),
                HelpItem(
                    "Stop workout",
                    symbol: "stop.circle",
                    what: "Ends the workout and saves it to Health.",
                    example: "You're done for the night."
                ),
                HelpItem(
                    "Keep going",
                    symbol: "figure.tennis",
                    what: "Calls off the automatic stop after a match.",
                    example: "Another match starts in five minutes. Keep it one workout.",
                    only: "When it's set to stop with the match"
                ),
                HelpItem(
                    "Heart rate",
                    symbol: "heart.fill",
                    what: "Your pulse, and a bar of the time spent in each zone.",
                    example: "See how hard that tiebreak really was."
                ),
                HelpItem(
                    "Energy",
                    symbol: "flame.fill",
                    also: ["waveform.path.ecg", "arrow.up.heart.fill"],
                    what: "Energy burned, and your average and highest heart rate.",
                    example: "Compare tonight with last week's session."
                ),
            ]
        ),
        HelpPage(
            id: "watch.warmup",
            chapter: .watch,
            title: "Warm-up",
            symbol: "figure.run",
            whereToFind: "A game set up with Warm-up on",
            picture: .watchButtons,
            readme: ["Warm-up"],
            items: [
                HelpItem(
                    "Warm-up",
                    symbol: "figure.run",
                    what: "How long you've warmed up, and your heart rate while a workout runs.",
                    example: "See how warm you are before anyone keeps score."
                ),
                HelpItem(
                    "Start game",
                    symbol: "play.fill",
                    what: "Ends the warm-up on every device and opens the score.",
                    example: "Everyone's ready. Start from the wrist."
                ),
            ]
        ),
        HelpPage(
            id: "watch.start",
            chapter: .watch,
            title: "With nothing on",
            symbol: "bolt",
            whereToFind: "Rekkert's start screen on the watch",
            picture: .watchButtons,
            readme: ["Joining from the wrist", "Presets"],
            items: [
                HelpItem(
                    "Quick match",
                    symbol: "bolt",
                    what: "Starts a match, Us against Them, on the usual rules.",
                    example: "The knock-up turned into a set. Start scoring in one tap."
                ),
                HelpItem(
                    "Join a match",
                    symbol: "person.2",
                    what: "Type the host's six digits; the sixth one joins.",
                    example: "Your phone's in your bag and someone is sharing the score."
                ),
                HelpItem(
                    "Presets",
                    what: "Swipe left: the setups you saved on the phone, ready to start.",
                    example: "Start Thursday's americano, players and all, from the wrist."
                ),
                HelpItem(
                    "Draw round",
                    symbol: "sportscourt",
                    what: "Draws a tournament's first round.",
                    example: "Everyone's on court and the phone's still in the car.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "The result",
                    symbol: "trophy.fill",
                    also: ["equal.circle.fill", "flag.checkered"],
                    what: "Who won, and the score. Done puts it away.",
                    example: "Show the other team the score, then tap Done."
                ),
                HelpItem(
                    "Undo last point",
                    symbol: "arrow.uturn.backward",
                    what: "On the result: reopens the match where it stood. Or Back to it.",
                    example: "The winning point went to the wrong team."
                ),
            ]
        ),
    ]

    private static let phonePages: [HelpPage] = [
        HelpPage(
            id: "phone.home",
            chapter: .phone,
            title: "Home",
            symbol: "house",
            whereToFind: "Rekkert's start screen",
            picture: .phoneButtons,
            readme: ["Presets"],
            items: [
                HelpItem(
                    "A preset",
                    what: "Tap to start it again, players and all. It's on your watch too.",
                    example: "Thursday's americano, started in one tap."
                ),
                HelpItem(
                    "Edit…",
                    symbol: "slider.horizontal.3",
                    also: ["pencil"],
                    what: "Press and hold a preset to change or rename it. The pencil sorts them.",
                    example: "Mia joined the group. Add her to the preset."
                ),
                HelpItem(
                    "Join a match",
                    symbol: "person.2.wave.2",
                    also: ["person.2.fill"],
                    what: "Scan or type a shared match's code. The icon top left shows you're on one.",
                    example: "The other team is already scoring on their phone."
                ),
                HelpItem(
                    "Start a workout",
                    symbol: "figure.tennis",
                    also: ["pause.circle", "play.circle", "stop.circle"],
                    what: "Starts, holds or stops the workout on your watch.",
                    example: "You're setting the match up on the phone anyway.",
                    needsWatch: true
                ),
                HelpItem(
                    "Past matches",
                    symbol: "clock.arrow.circlepath",
                    what: "Every match you kept, with how it went.",
                    example: "Settle who actually won last week."
                ),
                HelpItem(
                    "Players",
                    symbol: "person.2",
                    what: "Win rates, partners and head-to-heads, added up from History.",
                    example: "Find out who you win most with."
                ),
                HelpItem(
                    "Workouts",
                    symbol: "figure.tennis",
                    what: "What your watch recorded, with the matches played during it.",
                    example: "See what the three-set match cost you.",
                    needsWatch: true
                ),
                HelpItem(
                    "Settings",
                    symbol: "gearshape",
                    what: "Calling the score, buzzing, and the workout following the match.",
                    example: "Have the phone read the score out."
                ),
                HelpItem(
                    "How Rekkert works",
                    symbol: "questionmark.circle",
                    what: "Opens this guide again. It's in every match's ••• menu too.",
                    example: "Forgot what a watch button does?"
                ),
            ]
        ),
        HelpPage(
            id: "phone.match",
            chapter: .phone,
            title: "The match screen",
            symbol: "sportscourt",
            whereToFind: "Any match on the phone",
            picture: .phoneScore,
            items: [
                HelpItem(
                    "Tap a side",
                    what: "Gives that team the point.",
                    example: "The phone's on the bench: whoever is nearest taps.",
                    spot: HelpSpot(0.27, 0.24)
                ),
                HelpItem(
                    "Undo",
                    symbol: "arrow.uturn.backward",
                    what: "Takes the last point back. So does holding a side.",
                    example: "Two of you tapped for the same rally.",
                    spot: HelpSpot(0.67, 0.1)
                ),
                HelpItem(
                    "Full screen",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    what: "Just the two numbers, big and bright, and the screen stays on.",
                    example: "Prop the phone by the net so both ends can read it.",
                    spot: HelpSpot(0.55, 0.1)
                ),
                HelpItem(
                    "Match options",
                    symbol: "ellipsis.circle",
                    what: "Fixes, sharing, a TV and more. See the next pages.",
                    example: "You need to swap who's serving.",
                    spot: HelpSpot(0.79, 0.1)
                ),
                HelpItem(
                    "End",
                    symbol: "flag.checkered",
                    also: ["stop.circle", "rectangle.portrait.and.arrow.right"],
                    what: "Ends it: save, discard, or keep playing. Finish or Leave in some modes.",
                    example: "The court booking's up.",
                    spot: HelpSpot(0.91, 0.1)
                ),
                HelpItem(
                    "Your watch",
                    symbol: "applewatch.radiowaves.left.and.right",
                    also: ["applewatch.slash"],
                    what: "Green: your watch is in step. Grey: out of reach. A heart: a workout is on.",
                    example: "Check the watch is connected before you walk on court.",
                    spot: HelpSpot(0.08, 0.1),
                    needsWatch: true
                ),
                HelpItem(
                    "Sharing",
                    symbol: "person.2.fill",
                    also: ["person.2.slash"],
                    what: "How many others are on the match. Tap it for the code.",
                    example: "Someone turns up late and asks for the code.",
                    spot: HelpSpot(0.19, 0.1)
                ),
                HelpItem(
                    "Serving",
                    symbol: "circle.fill",
                    what: "The dot is the serving team; the badge, the half the serve goes from.",
                    example: "Nobody remembers who served last game.",
                    spot: HelpSpot(0.12, 0.56)
                ),
                HelpItem(
                    "Serve to",
                    what: "At a golden or star point, pick the half the receivers chose.",
                    example: "40–40 on golden point and they take it on the right.",
                    only: "Golden and star point",
                    spot: HelpSpot(0.5, 0.94)
                ),
            ]
        ),
        HelpPage(
            id: "phone.warmup",
            chapter: .phone,
            title: "Warm-up",
            symbol: "figure.run",
            whereToFind: "Turn on Warm-up when you set up a game",
            picture: .phoneButtons,
            readme: ["Warm-up"],
            items: [
                HelpItem(
                    "Warm-up",
                    symbol: "figure.run",
                    what: "Opens on a clock with no score. Remembered, and kept in presets.",
                    example: "Ten minutes of knocking up before anyone counts."
                ),
                HelpItem(
                    "Start game",
                    symbol: "play.fill",
                    what: "Ends the warm-up on every device and starts the game's clock.",
                    example: "Everyone's loose. Tap it and the score takes over."
                ),
            ]
        ),
        HelpPage(
            id: "phone.fixes",
            chapter: .phone,
            title: "Fix the match",
            symbol: "arrow.left.arrow.right",
            whereToFind: "Match options (•••)",
            picture: .phoneButtons,
            readme: ["Mid-match corrections"],
            items: [
                HelpItem(
                    "Swap serving team",
                    symbol: "arrow.left.arrow.right",
                    what: "Hands the serve to the other team, and the rotation after it.",
                    example: "You spun for serve after you'd already started scoring."
                ),
                HelpItem(
                    "Swap serving player",
                    symbol: "person.2.arrow.trianglehead.counterclockwise",
                    what: "Gives the serve to the server's partner.",
                    example: "Kim served, but the board had Sam down.",
                    only: "When both servers are named"
                ),
                HelpItem(
                    "Swap sides",
                    symbol: "rectangle.2.swap",
                    what: "Turns the phone's board round.",
                    example: "You changed ends and the phone stayed where it was."
                ),
                HelpItem(
                    "Swap sides automatically",
                    symbol: "arrow.2.squarepath",
                    what: "Turns the board round at every change of ends.",
                    example: "The board follows you round after the odd games.",
                    only: "Match and Friendly"
                ),
                HelpItem(
                    "Swap colours",
                    symbol: "circle.lefthalf.filled",
                    what: "Swaps the two teams' colours, on every device.",
                    example: "Their shirts are blue, so they should be the blue team."
                ),
            ]
        ),
        HelpPage(
            id: "phone.rounds",
            chapter: .phone,
            title: "Rounds",
            symbol: "flag.pattern.checkered",
            whereToFind: "Winner court, Friendly and tournaments",
            picture: .phoneButtons,
            items: [
                HelpItem(
                    "Whistle",
                    symbol: "flag.pattern.checkered",
                    what: "Winner court: banks the games. Friendly: ends the round where it is.",
                    example: "The organiser blew the whistle mid-game.",
                    only: "Winner court and Friendly"
                ),
                HelpItem(
                    "Start round",
                    symbol: "play.fill",
                    what: "Starts the next friendly round, with the pairs named above it.",
                    example: "Round won: see who partners whom, then start.",
                    only: "Friendly"
                ),
                HelpItem(
                    "Rounds and standings",
                    symbol: "list.bullet.rectangle",
                    what: "Every round played, and the table so far.",
                    example: "Who's top after five rounds?",
                    only: "Friendly"
                ),
                HelpItem(
                    "Previous round",
                    symbol: "chevron.left",
                    also: ["chevron.right"],
                    what: "Steps back through the rounds already played.",
                    example: "Check what court 2 scored in round 1.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "Change who sits out",
                    symbol: "arrow.triangle.2.circlepath",
                    what: "Before the first point, pick who sits out and draw it again.",
                    example: "Sam's running late. Let him sit out round 1.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "Draw the next round",
                    symbol: "arrow.right.circle.fill",
                    also: ["dice"],
                    what: "Draws it once every court is done. Past the planned rounds: Play another round.",
                    example: "Last court's in. On to round 4.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "Reopen this round",
                    symbol: "lock.open",
                    also: ["arrow.uturn.backward.circle", "forward.end"],
                    what: "Unlocks an earlier round to put a score right.",
                    example: "Court 1 typed 16–8, but it was 8–16.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "Cancel this round",
                    symbol: "xmark.circle",
                    what: "Scraps the round in play. It counts for nobody.",
                    example: "The hall closes halfway through round 6.",
                    only: "Americano and Mexicano"
                ),
                HelpItem(
                    "Finish tournament",
                    symbol: "flag.checkered",
                    also: ["trash"],
                    what: "Ends it and files it, or throws it away if nothing was played.",
                    example: "All 7 planned rounds are in. It asks once: finish, or play one more.",
                    only: "Americano and Mexicano"
                ),
            ]
        ),
        HelpPage(
            id: "phone.courts",
            chapter: .phone,
            title: "A tournament",
            symbol: "list.number",
            whereToFind: "Americano, Mexicano, and Winner court on All courts",
            picture: .phoneButtons,
            items: [
                HelpItem(
                    "Courts",
                    symbol: "sportscourt",
                    also: ["lock.fill"],
                    what: "Every court in the round. A padlock means its score is in.",
                    example: "Tap court 2 to score it from the bench."
                ),
                HelpItem(
                    "Standings",
                    symbol: "list.number",
                    what: "The table so far.",
                    example: "See who's heading for court 1 next round."
                ),
                HelpItem(
                    "Rounds",
                    symbol: "clock.arrow.circlepath",
                    what: "Every round, as it was played.",
                    example: "Who did you partner in round 2?"
                ),
                HelpItem(
                    "Type the score",
                    what: "On a court: type its result, or nudge it with + and −.",
                    example: "The court tells you 9–7 once they're done."
                ),
                HelpItem(
                    "Pick a result",
                    what: "One tap for a result that adds up to the target.",
                    example: "16 points played: tap 10–6.",
                    only: "Total points played"
                ),
                HelpItem(
                    "I'm playing as",
                    symbol: "person.crop.circle",
                    what: "Which player you are, for your watch.",
                    example: "Your watch opens on your court every round.",
                    needsWatch: true
                ),
                HelpItem(
                    "Countdown",
                    symbol: "timer",
                    what: "A timed round counts down. Pause holds it on every device.",
                    example: "A ball over the fence: pause, fetch it, carry on.",
                    only: "Winner court"
                ),
                HelpItem(
                    "Add time",
                    symbol: "plus.circle",
                    what: "More minutes on the round, even once it has run out.",
                    example: "Court 3 started late: give everyone two more minutes.",
                    only: "Winner court"
                ),
                HelpItem(
                    "Up or down",
                    symbol: "arrow.up",
                    also: ["arrow.down"],
                    what: "Once a court is settled, which way each side goes next round.",
                    example: "An arrow up: next round you play a court higher.",
                    only: "Winner court"
                ),
            ]
        ),
        HelpPage(
            id: "phone.sharing",
            chapter: .phone,
            title: "Share a match",
            symbol: "person.2.wave.2",
            whereToFind: "Match options (•••), or Join a match on Home",
            picture: .phoneButtons,
            readme: ["Joining with the camera", "Joining from the wrist", "Who may do what"],
            items: [
                HelpItem(
                    "Share this match",
                    symbol: "person.2.wave.2",
                    what: "Shows a code and a QR code. Whoever joins scores the same match.",
                    example: "The other team wants the score on their phone too."
                ),
                HelpItem(
                    "Scan the host's code",
                    symbol: "qrcode.viewfinder",
                    what: "Joins from the host's QR code. The Camera app does it too.",
                    example: "Quicker than shouting six digits across the court."
                ),
                HelpItem(
                    "Join a match",
                    what: "Type the six digits the host reads out. Your watch can do it too.",
                    example: "Your phone's in your bag: join from the watch instead."
                ),
                HelpItem(
                    "Rejoin",
                    symbol: "arrow.right.circle",
                    what: "Gets you back on a shared match, or onto its new code.",
                    example: "The host's phone restarted and shows a new code."
                ),
                HelpItem(
                    "New phones join as",
                    what: "Full access, only score, or read-only, for phones that join.",
                    example: "Spectators can follow the score without touching it.",
                    only: "Host only"
                ),
                HelpItem(
                    "A phone's own access",
                    what: "Each phone on the share sheet can be given a level of its own.",
                    example: "The captain on court 2 runs the rounds; everybody else scores.",
                    only: "Host only"
                ),
                HelpItem(
                    "Who are you?",
                    symbol: "person.crop.circle",
                    what: "Tells the host which player's phone this is.",
                    example: "The host sees Ada rather than Phone 2."
                ),
                HelpItem(
                    "Use my score everywhere",
                    symbol: "checkmark.circle",
                    what: "The host's score goes on every phone on the match.",
                    example: "Two phones scored apart while out of reach and now disagree.",
                    only: "Host only"
                ),
                HelpItem(
                    "Stop sharing",
                    what: "Ends the sharing for everybody on the code.",
                    example: "The other court has gone home."
                ),
            ]
        ),
        HelpPage(
            id: "phone.screens",
            chapter: .phone,
            title: "Beyond the phone",
            symbol: "tv",
            whereToFind: "Full screen, a TV and the Lock Screen",
            picture: .phoneButtons,
            readme: ["Full screen", "On a TV", "The Lock Screen"],
            items: [
                HelpItem(
                    "Full screen",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    what: "Still takes taps. The controls dim, but never go.",
                    example: "Read the score from the far baseline."
                ),
                HelpItem(
                    "Black out",
                    symbol: "moon.fill",
                    also: ["moon"],
                    what: "White digits on black, in full screen. Also in Settings.",
                    example: "Midday sun washes the team colours out."
                ),
                HelpItem(
                    "Show on a TV",
                    symbol: "airplay.video",
                    also: ["appletv", "rectangle.on.rectangle", "switch.2"],
                    what: "Mirror the phone to a TV and the TV gets a scoreboard of its own.",
                    example: "Club night: every court and the table on the bar's TV."
                ),
                HelpItem(
                    "Board",
                    symbol: "tv",
                    what: "The TV's board, on the iPad itself.",
                    example: "Stand the iPad at the end of the courts.",
                    only: "iPad"
                ),
                HelpItem(
                    "Score on the Lock Screen",
                    symbol: "lock.iphone",
                    what: "The live score on the Lock Screen and in the Dynamic Island.",
                    example: "Check the score without unlocking the phone in your pocket."
                ),
            ]
        ),
        HelpPage(
            id: "phone.history",
            chapter: .phone,
            title: "History and players",
            symbol: "clock.arrow.circlepath",
            whereToFind: "Past matches and Players, on Home",
            picture: .phoneButtons,
            readme: ["Players", "The timeline"],
            items: [
                HelpItem(
                    "Edit",
                    what: "On a past match: put names right, name it, or add a note.",
                    example: "Nobody filled in \"Them\". Do it now."
                ),
                HelpItem(
                    "Timeline",
                    what: "Who led and when, with your heart rate. Drag across to read it.",
                    example: "Find where the second set got away."
                ),
                HelpItem(
                    "Resume this session",
                    symbol: "play.circle",
                    what: "Picks a kept match up again where it stopped.",
                    example: "Rain stopped play. Finish it next week."
                ),
                HelpItem(
                    "New tournament, same players",
                    symbol: "person.2.badge.plus",
                    what: "Sets up a fresh tournament with the same players.",
                    example: "Same crowd, next Thursday."
                ),
                HelpItem(
                    "Period",
                    symbol: "calendar",
                    also: ["slider.horizontal.3"],
                    what: "Which stretch of History the player stats add up.",
                    example: "Only this season: pick This year."
                ),
                HelpItem(
                    "Merge with…",
                    symbol: "arrow.triangle.merge",
                    what: "Makes two names one person. Unmerge takes it apart again.",
                    example: "\"Jon\" and \"Jonas\" are the same player."
                ),
                HelpItem(
                    "Separate matches…",
                    symbol: "arrow.triangle.branch",
                    what: "Moves some matches to another person with the same name.",
                    example: "Two Johns: give work-John's matches to \"John B\"."
                ),
                HelpItem(
                    "Note",
                    symbol: "note.text",
                    what: "A line about a player.",
                    example: "\"From work\", to tell the two Johns apart."
                ),
                HelpItem(
                    "Best partner",
                    symbol: "star.fill",
                    what: "The best win rate together, over three games or more.",
                    example: "Pick your partner for the club final."
                ),
            ]
        ),
        HelpPage(
            id: "phone.settings",
            chapter: .phone,
            title: "Settings",
            symbol: "gearshape",
            whereToFind: "The gear on Home",
            picture: .phoneButtons,
            readme: ["Workouts"],
            items: [
                HelpItem(
                    "Call the score",
                    symbol: "speaker.wave.2",
                    what: "Reads the score out after every point. Also in a match's options.",
                    example: "Nobody has to look: the phone says \"thirty–fifteen\"."
                ),
                HelpItem(
                    "Buzz on a point",
                    symbol: "hand.tap",
                    what: "How your watch buzzes, and whether only for others' taps.",
                    example: "Feel the point go on when your partner scores it.",
                    needsWatch: true
                ),
                HelpItem(
                    "When a match starts",
                    symbol: "figure.tennis",
                    what: "Start the watch's workout with each match: never, ask, or always.",
                    example: "You keep forgetting to start it.",
                    needsWatch: true
                ),
                HelpItem(
                    "When a match ends",
                    symbol: "flag.checkered",
                    what: "Stop the workout after a match: never, ask, or after a minute.",
                    example: "One match a night, and the workout should end with it.",
                    needsWatch: true
                ),
            ]
        ),
    ]
}
