import Foundation

public enum HelpSample {
    public static func state(for mode: GameMode) -> SessionState? {
        folding(events(for: mode))
    }

    /// 40–40 on a golden point, so the receivers' call is on the board too.
    public static var goldenPoint: SessionState? {
        folding(
            [.configure(.traditional(rules: TraditionalRules(deuceRule: .goldenPoint), teams: pairs))]
                + points("aaaa bbbb aaaa aaaa aaabbb")
        )
    }

    private static let pairs = BySide(
        a: TeamInfo(name: "Us", players: ["Ada", "Jonas"]),
        b: TeamInfo(name: "Them", players: ["Kim", "Sam"])
    )

    private static let names = ["Ada", "Jonas", "Kim", "Sam", "Ola", "Mia", "Tor", "Eva"]

    private static func events(for mode: GameMode) -> [EventKind] {
        switch mode {
        case .traditional:
            [.configure(.traditional(rules: TraditionalRules(), teams: pairs))]
                + points("aaaa bbbb aaaa aaaa aab")
        case .pointCount:
            [.configure(.pointCount(rules: PointCountRules(), teams: pairs))]
                + points("abaab aabba ba")
        case .winnerCourt:
            [.configure(.winnerCourt(rules: WinnerCourtRules(), teams: pairs))]
                + points("aaaa bbbb aaaa")
                + [.endRound(round: 0)]
                + points("bbbb aa")
        case .friendly:
            [
                .configure(.friendly(FriendlySession(
                    id: FriendlyID(fixed(1)),
                    name: "Thursday",
                    players: players(5)
                ))),
                .nextRound(after: -1),
            ]
                + points("aaaa bbbb ab")
        case .americano:
            tournament(.americano)
        case .mexicano:
            tournament(.mexicano)
        }
    }

    private static func tournament(_ format: TournamentFormat) -> [EventKind] {
        [
            .configure(.tournament(Tournament(
                id: TournamentID(fixed(2)),
                name: "Club night",
                format: format,
                players: players(8),
                config: TournamentConfig(courtCount: 2)
            ))),
            .nextRound(after: -1),
        ]
            + points("abaab aabba ba")
            + points("bbaba abb", court: 1)
    }

    private static func folding(_ events: [EventKind]) -> SessionState? {
        var state: SessionState?
        for event in events {
            SessionReducer.apply(event, to: &state)
        }
        return state
    }

    private static func points(_ sides: String, court: Int = 0) -> [EventKind] {
        sides.compactMap { side in
            switch side {
            case "a": .point(round: 0, court: court, team: .a)
            case "b": .point(round: 0, court: court, team: .b)
            default: nil
            }
        }
    }

    private static func players(_ count: Int) -> [Player] {
        names.prefix(count).enumerated().map { index, name in
            Player(id: PlayerID(fixed(UInt8(10 + index))), name: name)
        }
    }

    private static func fixed(_ last: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, last))
    }
}
