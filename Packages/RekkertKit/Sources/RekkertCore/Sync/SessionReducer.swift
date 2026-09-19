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
            case .friendly(var session):
                // The event names no round, so a late one lands on whichever is current.
                // Benign: the choice is wiped by the next point and only read at a
                // sudden-death point in the first place.
                guard let index = session.rounds.indices.last else { break }
                session.rounds[index].score.suddenDeathCourt = court
                state = .friendly(session)
            case .tournament, .pointCount, .none:
                break
            }

        case .endRound(let round):
            switch state {
            case .winnerCourt(var session):
                guard !session.isFinished, session.score.completedSets.count == round else { return }
                session.score = session.engine.endingRound(session.score)
                state = .winnerCourt(session)

            case .friendly(var session):
                // Stops the round where it stands rather than inventing a set. The games
                // played still count; nobody won it. A round nothing has happened in is left
                // alone — the same line winner court draws — so the only way past it is to
                // play it or to finish the session.
                guard !session.isFinished, session.rounds.indices.contains(round),
                      !session.rounds[round].isFinished,
                      session.rounds[round].wasPlayed else { return }
                session.rounds[round].isStopped = true
                state = .friendly(session)

            case .traditional, .tournament, .pointCount, .none:
                break
            }

        case .setFirstServer(let round, let court, let index):
            mutateCourt(round: round, court: court, in: &state) { _, match in
                match.state.firstServerIndex = index
            } traditional: { session in
                session.score.firstServerIndex = index
            }

        case .setServeOrder(let round, let court, let order):
            mutateCourt(round: round, court: court, in: &state) { _, match in
                match.state.serveOrder = order
            } traditional: { session in
                session.score.serveOrder = order
            }

        case .setRoundConfirmed(let round, let isConfirmed):
            guard case .tournament(var tournament) = state,
                  tournament.rounds.indices.contains(round) else { return }
            for court in tournament.rounds[round].matches.indices {
                tournament.rounds[round].matches[court].isConfirmed = isConfirmed
            }
            state = .tournament(tournament)

        case .nextRound(let after):
            switch state {
            case .tournament(let tournament):
                guard tournament.rounds.count == after + 1,
                      let next = try? TournamentEngine.appendingRound(to: tournament) else { return }
                state = .tournament(next)

            case .friendly(let session):
                guard !session.isFinished, session.rounds.count == after + 1,
                      let next = try? FriendlyScheduler.appendingRound(to: session) else { return }
                state = .friendly(next)

            case .traditional, .winnerCourt, .pointCount, .none:
                break
            }

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
            case .friendly(var session):
                session.isFinished = true
                state = .friendly(session)
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

        case (.friendly(let incoming), .friendly(var session)):
            // The rounds already played stay where they are; the rest is the setup being
            // corrected. The id is not adopted — it seeds the draw, and re-seeding it would
            // re-partner every round still to come.
            session.name = incoming.name
            session.rules = incoming.rules
            session.players = incoming.players
            state = .friendly(session)

        case (.friendly(let incoming), _):
            state = .friendly(incoming)
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

        case .friendly(var session):
            guard !session.isFinished, session.rounds.indices.contains(round),
                  !session.rounds[round].isFinished,
                  var asTraditional = session.match(at: round) else { return }
            traditional(&asTraditional)
            session.rounds[round].score = asTraditional.score
            state = .friendly(session)

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
