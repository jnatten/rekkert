public enum SessionReducer {
    public static func state(of log: MatchLog) -> SessionState? {
        var state: SessionState?
        for event in log.effectiveEvents {
            apply(event.kind, to: &state)
        }
        return state
    }

    static func apply(_ kind: EventKind, to state: inout SessionState?) {
        switch kind {
        case .configure(let setup):
            configure(setup, into: &state)

        case .point(let court, let team):
            mutateCourt(court, in: &state) { engine, match in
                match.state = engine.scoringPoint(team, in: match.state)
            } traditional: { session in
                session.score = session.engine.scoringPoint(team, in: session.score)
            }

        case .setScore(let court, let points):
            mutateCourt(court, in: &state) { engine, match in
                match.state = engine.settingScore(points, in: match.state)
            } traditional: { _ in }

        case .chooseServeSide(let court):
            guard case .traditional(var session) = state else { return }
            session.score.suddenDeathCourt = court
            state = .traditional(session)

        case .confirmRound:
            guard case .tournament(var tournament) = state,
                  let index = tournament.rounds.indices.last else { return }
            for court in tournament.rounds[index].matches.indices {
                tournament.rounds[index].matches[court].isConfirmed = true
            }
            state = .tournament(tournament)

        case .nextRound:
            guard case .tournament(let tournament) = state,
                  let next = try? TournamentEngine.appendingRound(to: tournament) else { return }
            state = .tournament(next)

        case .finish:
            switch state {
            case .tournament(var tournament):
                tournament.isFinished = true
                state = .tournament(tournament)
            case .traditional, .none:
                break
            }

        case .undo:
            break
        }
    }

    private static func configure(_ setup: SessionSetup, into state: inout SessionState?) {
        switch (setup, state) {
        case (.traditional(let rules, let teams), .traditional(var session)):
            session.rules = rules
            session.teams = teams
            state = .traditional(session)

        case (.traditional(let rules, let teams), _):
            state = .traditional(
                TraditionalSession(rules: rules, teams: teams, score: TraditionalState())
            )

        case (.tournament(let incoming), .tournament(var tournament)):
            tournament.name = incoming.name
            tournament.players = incoming.players
            tournament.config = incoming.config
            state = .tournament(tournament)

        case (.tournament(let incoming), _):
            state = .tournament(incoming)
        }
    }

    private static func mutateCourt(
        _ court: Int,
        in state: inout SessionState?,
        tournament change: (PointCountEngine, inout CourtMatch) -> Void,
        traditional: (inout TraditionalSession) -> Void
    ) {
        switch state {
        case .traditional(var session):
            traditional(&session)
            state = .traditional(session)

        case .tournament(var current):
            guard let round = current.rounds.indices.last,
                  let index = current.rounds[round].matches.firstIndex(where: { $0.courtIndex == court }),
                  !current.rounds[round].matches[index].isConfirmed
            else { return }
            let engine = PointCountEngine(rules: current.config.pointRules)
            change(engine, &current.rounds[round].matches[index])
            state = .tournament(current)

        case .none:
            break
        }
    }
}
