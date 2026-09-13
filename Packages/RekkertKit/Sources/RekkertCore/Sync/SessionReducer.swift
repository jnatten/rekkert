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

        case .restore(let archived):
            state = archived

        case .point(let round, let court, let team):
            mutateCourt(round: round, court: court, in: &state) { engine, match in
                match.state = engine.scoringPoint(team, in: match.state)
            } traditional: { session in
                session.score = session.engine.scoringPoint(team, in: session.score)
            }

        case .setScore(let round, let court, let points):
            mutateCourt(round: round, court: court, in: &state) { engine, match in
                match.state = engine.settingScore(points, in: match.state)
            } traditional: { _ in }

        case .chooseServeSide(let court):
            switch state {
            case .traditional(var session):
                session.score.suddenDeathCourt = court
                state = .traditional(session)
            case .winnerCourt(var session):
                session.score.suddenDeathCourt = court
                state = .winnerCourt(session)
            case .tournament, .pointCount, .none:
                break
            }

        case .endRound(let round):
            guard case .winnerCourt(var session) = state, !session.isFinished else { return }
            guard session.score.completedSets.count == round else { return }
            session.score = session.engine.endingRound(session.score)
            state = .winnerCourt(session)

        case .setFirstServer(let round, let court, let index):
            mutateCourt(round: round, court: court, in: &state) { _, match in
                match.state.firstServerIndex = index
            } traditional: { session in
                session.score.firstServerIndex = index
            }

        case .setRoundConfirmed(let round, let isConfirmed):
            guard case .tournament(var tournament) = state,
                  tournament.rounds.indices.contains(round) else { return }
            for court in tournament.rounds[round].matches.indices {
                tournament.rounds[round].matches[court].isConfirmed = isConfirmed
            }
            state = .tournament(tournament)

        case .nextRound(let after):
            guard case .tournament(let tournament) = state,
                  tournament.rounds.count == after + 1,
                  let next = try? TournamentEngine.appendingRound(to: tournament) else { return }
            state = .tournament(next)

        case .finish:
            switch state {
            case .tournament(var tournament):
                tournament.isFinished = true
                state = .tournament(tournament)
            case .winnerCourt(var session):
                session.isFinished = true
                state = .winnerCourt(session)
            case .traditional(var session):
                session.isStopped = true
                state = .traditional(session)
            case .pointCount(var session):
                session.isStopped = true
                state = .pointCount(session)
            case .none:
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

        case (.winnerCourt(let rules, let teams), .winnerCourt(var session)):
            session.rules = rules
            session.teams = teams
            state = .winnerCourt(session)

        case (.winnerCourt(let rules, let teams), _):
            state = .winnerCourt(WinnerCourtSession(rules: rules, teams: teams))

        case (.pointCount(let rules, let teams), .pointCount(var session)):
            session.rules = rules
            session.teams = teams
            state = .pointCount(session)

        case (.pointCount(let rules, let teams), _):
            state = .pointCount(PointCountSession(rules: rules, teams: teams))
        }
    }

    private static func mutateCourt(
        round: Int,
        court: Int,
        in state: inout SessionState?,
        tournament change: (PointCountEngine, inout CourtMatch) -> Void,
        traditional: (inout TraditionalSession) -> Void
    ) {
        switch state {
        case .traditional(var session):
            traditional(&session)
            state = .traditional(session)

        case .winnerCourt(var session):
            guard !session.isFinished else { return }
            var asTraditional = TraditionalSession(
                rules: session.rules.scoring, teams: session.teams, score: session.score
            )
            traditional(&asTraditional)
            session.score = asTraditional.score
            state = .winnerCourt(session)

        case .pointCount(var session):
            guard !session.isFinished else { return }
            var asCourt = CourtMatch(courtIndex: 0, teams: BySide(both: []), state: session.score)
            change(session.engine, &asCourt)
            session.score = asCourt.state
            state = .pointCount(session)

        case .tournament(var current):
            guard current.rounds.indices.contains(round),
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
