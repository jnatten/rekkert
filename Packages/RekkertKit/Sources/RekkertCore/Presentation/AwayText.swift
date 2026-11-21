/// Every sentence about players leaving a tournament and coming back (spec 008,
/// contracts/screens.md). Views lay these out and never word them themselves.
public enum AwayText {
    public static let button = "Who's here…"
    public static let sheetTitle = "Who's here?"
    public static let watchNeedsUpdate = "Update Rekkert on your Apple Watch to follow this tournament there."

    public static func leaveTitle(_ name: String) -> String { "Has \(name) left?" }
    public static func leaveButton(_ name: String) -> String { "\(name) has left" }

    /// Under the courts while anybody is away.
    public static func awayFooter(_ names: [String]) -> String? {
        switch names.count {
        case 0: nil
        case 1: "\(names[0]) has left. The draw leaves \(names[0]) out."
        default: "\(joined(names)) have left. The draw leaves them out."
        }
    }

    /// The rounds somebody missed, as the table and the roster say it: "Left after round 4",
    /// "Away rounds 3–4 · left after round 7". Nil for somebody who never left.
    public static func stretches(_ away: [AwayStretch]) -> String? {
        guard !away.isEmpty else { return nil }
        let parts = away.map { stretch -> String in
            guard let back = stretch.backFor else {
                return stretch.firstMissed <= 1 ? "left before round 1" : "left after round \(stretch.firstMissed - 1)"
            }
            let last = back - 1
            return last == stretch.firstMissed ? "away round \(last)" : "away rounds \(stretch.firstMissed)–\(last)"
        }
        let sentence = parts.joined(separator: " · ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// The round in play has nothing on it yet, so it is drawn again.
    public static func redraws(round: Int, name: String, isAway: Bool) -> String {
        "Round \(round) hasn't started, so it's drawn again \(isAway ? "without" : "with") \(name)."
    }

    /// Their court stops where it stands.
    public static func stops(court: Int, at score: BySide<Int>) -> String {
        "Court \(court) stops at \(score.a)–\(score.b) and counts as it stands."
    }

    /// A draw that raced their leaving put them on a court of the round in play.
    public static func stillOnCourt(court: Int, round: Int) -> String {
        "Still drawn on court \(court) in round \(round)."
    }

    public static func takeOff(_ name: String, round: Int) -> String { "Take \(name) off round \(round)" }

    /// What the confirmation says the change does now: the round in play redrawn, or a court stopped.
    public static func inPlay(_ preview: AwayPreview, name: String, roundInPlay: Int) -> [String] {
        var lines: [String] = []
        if preview.redrawsRoundInPlay {
            lines.append(redraws(round: roundInPlay, name: name, isAway: preview.isAway))
        }
        if let stopping = preview.stoppingCourt {
            lines.append(stops(court: stopping.court, at: stopping.score))
        }
        return lines
    }

    /// On the host, for the phones a departure would take off the tournament.
    public static func turnedAway(_ phones: Int) -> String? {
        switch phones {
        case 0: nil
        case 1: "1 phone on an older Rekkert will be taken off this tournament. It can join again once updated."
        default: "\(phones) phones on an older Rekkert will be taken off this tournament. They can join again once updated."
        }
    }

    static func joined(_ words: [String]) -> String {
        switch words.count {
        case 0: ""
        case 1: words[0]
        default: words.dropLast().joined(separator: ", ") + " and " + words.last!
        }
    }
}
