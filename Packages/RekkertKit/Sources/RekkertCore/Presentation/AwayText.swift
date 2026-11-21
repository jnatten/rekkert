public enum AwayText {
    public static let button = "Who's here…"
    public static let sheetTitle = "Who's here?"
    public static let watchNeedsUpdate = "Update Rekkert on your Apple Watch to follow this tournament there."
    public static let shortOfPlayers = "Fewer than four players are here, so no more rounds can be drawn."

    public static func leaveTitle(_ name: String) -> String { "Has \(name) left?" }
    public static func leaveButton(_ name: String) -> String { "\(name) has left" }
    public static func backTitle(_ name: String) -> String { "Is \(name) back?" }
    public static func backButton(_ name: String) -> String { "\(name) is back" }
    public static func playsAgain(_ name: String, from round: Int) -> String { "\(name) plays again from round \(round)." }

    public static func awayFooter(_ names: [String]) -> String? {
        switch names.count {
        case 0: nil
        case 1: "\(names[0]) has left. The draw leaves \(names[0]) out."
        default: "\(joined(names)) have left. The draw leaves them out."
        }
    }

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

    public static func awayInRound(_ names: [String]) -> String? {
        names.isEmpty ? nil : "Away: \(names.joined(separator: ", "))"
    }

    public static func redraws(round: Int, name: String, isAway: Bool) -> String {
        "Round \(round) hasn't started, so it's drawn again \(isAway ? "without" : "with") \(name)."
    }

    public static func stops(court: Int, at score: BySide<Int>) -> String {
        "Court \(court) stops at \(score.a)–\(score.b) and counts as it stands."
    }

    public static func stillOnCourt(court: Int, round: Int) -> String {
        "Still drawn on court \(court) in round \(round)."
    }

    public static func takeOff(_ name: String, round: Int) -> String { "Take \(name) off round \(round)" }

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

    public static func shape(_ preview: AwayPreview) -> String? {
        if preview.isShortOfPlayers { return "Fewer than four are left, so no more rounds can be drawn." }
        guard preview.courtsAfter != preview.courtsBefore || preview.benchAfter != preview.benchBefore else { return nil }
        let round = preview.fromRound
        if preview.courtsAfter == preview.courtsBefore, preview.benchAfter == 0 { return "Nobody sits out from round \(round)." }
        let courts = preview.courtsAfter == 1 ? "1 court" : "\(preview.courtsAfter) courts"
        let bench = switch preview.benchAfter {
        case 0: "nobody sits out"
        case 1: "1 sits out each round"
        default: "\(preview.benchAfter) sit out each round"
        }
        return "From round \(round): \(courts), \(bench)."
    }

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
