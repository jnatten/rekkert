/// The names in a session that are still the user's to change once it has been filed away.
/// A finished session keeps the names it was set up with, so a typo, a nickname you would
/// rather not keep, or a "Them" nobody got round to filling in would otherwise be permanent.
///
/// An enum rather than a struct of optionals, because a session comes in one of two shapes
/// and the other one has nothing to say: a tournament cannot be handed team names, and a
/// match cannot be handed an event name.
public enum SessionNames: Sendable, Hashable {
    /// Tournament and friendly: an event name, and the people who played it.
    case group(event: String, players: [Player])
    /// Match, Points and Winner court: two fixed sides, each with a name and a line-up.
    case sides(BySide<TeamInfo>)
}

extension SessionState {
    /// The names as they stand.
    public var names: SessionNames {
        switch self {
        case .tournament(let tournament):
            .group(event: tournament.name, players: tournament.players)
        case .friendly(let session):
            .group(event: session.name, players: session.players)
        case .traditional(let session): .sides(session.teams)
        case .winnerCourt(let session): .sides(session.teams)
        case .pointCount(let session): .sides(session.teams)
        }
    }

    /// The same session under new names, and nothing else changed.
    ///
    /// People are matched by id and only their `name` moves, so every round, standing,
    /// sit-out and result line that refers to them follows along — the rounds hold ids and
    /// never need touching. Nobody is added, removed or reordered: dropping somebody would
    /// turn their rounds into "—" and vanish them from the table.
    ///
    /// A blank replacement is ignored, since clearing a name is not renaming anybody. The
    /// event name is the exception — it is optional, and `title` already falls back to the
    /// format or to "Friendly" — so it is trimmed and may be cleared. Names of the wrong
    /// shape for this session are ignored.
    public func renamed(_ names: SessionNames) -> SessionState {
        switch (self, names) {
        case (.tournament(var tournament), .group(let event, let players)):
            tournament.name = event.trimmingCharacters(in: .whitespacesAndNewlines)
            tournament.players = SessionNames.renaming(tournament.players, to: players)
            return .tournament(tournament)

        case (.friendly(var session), .group(let event, let players)):
            session.name = event.trimmingCharacters(in: .whitespacesAndNewlines)
            session.players = SessionNames.renaming(session.players, to: players)
            return .friendly(session)

        case (.traditional(var session), .sides(let teams)):
            session.teams = SessionNames.renaming(session.teams, to: teams)
            return .traditional(session)

        case (.winnerCourt(var session), .sides(let teams)):
            session.teams = SessionNames.renaming(session.teams, to: teams)
            return .winnerCourt(session)

        case (.pointCount(var session), .sides(let teams)):
            session.teams = SessionNames.renaming(session.teams, to: teams)
            return .pointCount(session)

        case (.tournament, .sides), (.friendly, .sides),
             (.traditional, .group), (.winnerCourt, .group), (.pointCount, .group):
            return self
        }
    }
}

extension SessionNames {
    /// Whether a typed name says anything. Trimmed, so a field holding only spaces counts
    /// as having been left alone.
    fileprivate static func isBlank(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    fileprivate static func renaming(_ existing: [Player], to edited: [Player]) -> [Player] {
        let names = Dictionary(
            edited.filter { !isBlank($0.name) }.map { ($0.id, $0.name) },
            uniquingKeysWith: { _, last in last }
        )
        return existing.map { player in
            guard let name = names[player.id] else { return player }
            return Player(id: player.id, name: name)
        }
    }

    fileprivate static func renaming(_ existing: BySide<TeamInfo>, to edited: BySide<TeamInfo>) -> BySide<TeamInfo> {
        BySide(
            a: renaming(existing.a, to: edited.a),
            b: renaming(existing.b, to: edited.b)
        )
    }

    /// A side's line-up is addressed by position — the serve badge picks the server out of it
    /// by index — so names are replaced where they stand rather than compacted, and a side
    /// that was set up with nobody named can still have names put to it. Only slots past the
    /// last named player are dropped, since a trailing blank names nobody and no serve can
    /// land on it.
    fileprivate static func renaming(_ existing: TeamInfo, to edited: TeamInfo) -> TeamInfo {
        var team = existing
        if !isBlank(edited.name) { team.name = edited.name }
        for (index, name) in edited.players.enumerated() where !isBlank(name) {
            while team.players.count <= index { team.players.append("") }
            team.players[index] = name
        }
        while team.players.last?.isEmpty == true { team.players.removeLast() }
        return team
    }
}

extension HistoryRecord {
    /// The same record under new names. `title` is only ever the copy of `state.title` taken
    /// when the record was filed, so it is recomputed rather than kept — which also means a
    /// record picked up again later carries the corrected names into the new session.
    public func renamed(_ names: SessionNames) -> HistoryRecord {
        let edited = state.renamed(names)
        var record = self
        record.state = edited
        record.title = edited.title
        return record
    }
}
