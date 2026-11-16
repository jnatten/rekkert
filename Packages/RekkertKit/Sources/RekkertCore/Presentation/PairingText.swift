import Foundation

public enum PairingText {
    public static let watchNeedsUpdate = "Update Rekkert on your Apple Watch to follow this friendly there."

    public static func rule(_ rule: PairingRule, in session: FriendlySession) -> String {
        "\(names(rule.players, in: session)) \(rule.kind == .apart ? "apart" : "together")"
    }

    public static func conflict(_ conflict: PairingConflict, in session: FriendlySession, rules: [PairingRule]) -> String {
        let named = conflict.rules.compactMap { id in rules.first { $0.id == id } }
        switch conflict.reason {
        case .sameTwoBothWays:
            return "\(names(named.first?.players ?? [], in: session)) can't be kept both apart and together."
        case .twoPartnersForOne:
            let shared = named.dropFirst().reduce(Set(named.first?.players ?? [])) { $0.intersection($1.players) }
            return "\(names(Array(shared), in: session)) can only be kept together with one player."
        case .togetherInsideApart:
            let together = named.first { $0.kind == .together }?.players ?? []
            return "\(names(together, in: session)) are kept together, so they can't be in a group kept apart."
        }
    }

    public static func forecast(_ forecast: PairingForecast, in session: FriendlySession) -> String? {
        guard forecast.breaking > 0 else { return nil }
        let when = forecast.breaking >= forecast.rounds
            ? "in any round with these players."
            : "in \(forecast.breaking) of every \(forecast.rounds) rounds — whoever sits out decides."
        let kinds = Set(forecast.unkept.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else { return "The pairing rules can't all be kept \(when)" }
        let players = forecast.unkept.flatMap(\.players)
        let who = names(players, in: session)
        switch kind {
        case .apart: return "\(who) can't \(Set(players).count > 2 ? "all " : "")be kept apart \(when)"
        case .together: return "\(who) can't be kept together \(when)"
        }
    }

    public static func unkept(_ unkept: UnkeptRule, in session: FriendlySession, offered: Bool) -> String {
        let who = names(unkept.players, in: session)
        switch (unkept.kind, offered) {
        case (.apart, true): return "\(who) are partners — the rules couldn't keep them apart this round."
        case (.apart, false): return "\(who) are partners this round — the rules couldn't keep them apart."
        case (.together, true): return "\(who) are on opposite sides — the rules couldn't keep them together this round."
        case (.together, false): return "\(who) are on opposite sides this round — the rules couldn't keep them together."
        }
    }

    public static func turnedAway(_ phones: Int) -> String? {
        switch phones {
        case 0: nil
        case 1: "1 phone on an older Rekkert will be taken off this match. It can join again once updated."
        default: "\(phones) phones on an older Rekkert will be taken off this match. They can join again once updated."
        }
    }

    static func names(_ ids: [PlayerID], in session: FriendlySession) -> String {
        let wanted = Set(ids)
        let listed = session.players.map(\.id).filter(wanted.contains)
        var seen = Set(listed)
        let missing = ids.filter { seen.insert($0).inserted }
        let words = (listed + missing).map(session.name)
        switch words.count {
        case 0: return ""
        case 1: return words[0]
        default: return words.dropLast().joined(separator: ", ") + " and " + words.last!
        }
    }
}
