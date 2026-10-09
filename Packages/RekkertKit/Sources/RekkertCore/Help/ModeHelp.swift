public struct ModeHelp: Hashable, Sendable {
    public let pickItWhen: String
    public let points: [String]
}

extension GameMode {
    public var help: ModeHelp {
        switch self {
        case .traditional:
            ModeHelp(
                pickItWhen: "For a proper match: 15, 30, 40, games and sets.",
                points: [
                    "At 40–40: advantage, a golden point or star point, chosen when you set it up.",
                    "The badge by the score shows who serves and from which half.",
                    "Sets to win, tiebreaks and a super tiebreak decider are all settings.",
                ]
            )
        case .pointCount:
            ModeHelp(
                pickItWhen: "For a game of a fixed length: points count 1, 2, 3 to a target.",
                points: [
                    "No games or sets, just the two counts and who serves.",
                    "It ends when the points played reach the target, or when one side does.",
                    "Level when the target is reached counts as a draw.",
                ]
            )
        case .winnerCourt:
            ModeHelp(
                pickItWhen: "For club nights where a whistle moves everyone up or down a court.",
                points: [
                    "Play games as usual. The whistle ends the round; the next starts at 0–0.",
                    "The game the whistle cuts off goes to whoever leads it. Level, it's dropped.",
                    "Only your court is tracked: the rounds, and the games each side won.",
                ]
            )
        case .friendly:
            ModeHelp(
                pickItWhen: "For a group swapping partners: real matches, a fresh draw each round.",
                points: [
                    "Four or more play doubles, two or three singles. Extras sit out in turn.",
                    "Nobody partners the same person twice while a new pairing is left.",
                    "When a round is won the board waits. Start round draws the next.",
                ]
            )
        case .americano:
            ModeHelp(
                pickItWhen: "For a tournament where everybody partners everybody, on one court or more.",
                points: [
                    "Rounds play to a points target: 16 unless you pick 21, 24 or 32.",
                    "Each round is drawn to avoid repeat partners and repeat opponents.",
                    "Sitting a round out still scores: half the target, unless you change it.",
                ]
            )
        case .mexicano:
            ModeHelp(
                pickItWhen: "For a tournament paired by the table, so the games stay close.",
                points: [
                    "After every round the top four go on court 1, paired 1+4 against 2+3.",
                    "Points to a target, as in Americano: 16 unless you pick another.",
                    "Someone late? Before the first point you can change who sits out.",
                ]
            )
        }
    }
}
