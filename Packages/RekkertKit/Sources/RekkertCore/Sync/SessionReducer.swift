import Foundation

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
        case .configure(let setup, let at, let warmup):
            configure(setup, at: at, warmupStartedAt: warmup == true ? at : nil, into: &state)

        case .endWarmup(let at):
            guard state?.warmingUpSince != nil else { return }
            state = state?.restarted(at: at)

        case .restore(let archived, _):
            state = archived

        case .point(let round, let court, let team):
            mutateCourt(round: round, court: court, in: &state) { engine, match in
                match.state = engine.scoringPoint(team, in: match.state)
            } traditional: { session in
                session.score = session.engine.scoringPoint(team, in: session.score)
            } ladder: { rules, status, isEnded, match in
                // After the whistle the only point left to play is the one that settles a
                // court still level.
                if isEnded {
                    if status.awaitsDecider { match.decider = team }
                } else {
                    match.games = TraditionalEngine(rules: rules.scoring).scoringPoint(team, in: match.games ?? TraditionalState())
                }
            }

        case .setScore(let round, let court, let points):
            mutateCourt(round: round, court: court, in: &state) { engine, match in
                match.state = engine.settingScore(points, in: match.state)
            } traditional: { _ in } ladder: { rules, status, isEnded, match in
                let typed = BySide(a: max(0, points.a), b: max(0, points.b))
                // After the whistle the games already shown, typed in again, keep the deciding
                // point that settled them.
                guard rules.isTimed, !(isEnded && status.line == typed) else { return }
                var games = match.games ?? TraditionalState()
                games.games = typed
                games.points = BySide(both: 0)
                games.deuceCount = 0
                games.suddenDeathCourt = nil
                match.games = games
                match.decider = nil
            }

        case .chooseServeSide(let court, let round, let index):
            switch state {
            case .traditional(var session):
                session.score.suddenDeathCourt = court
                state = .traditional(session)
            case .winnerCourt(var session):
                session.score.suddenDeathCourt = court
                state = .winnerCourt(session)
            case .friendly(var session):
                // An event from before rounds were named lands on whichever is current.
                // Benign: the choice is wiped by the next point and only read at a
                // sudden-death point in the first place.
                guard let at = round ?? session.rounds.indices.last, session.rounds.indices.contains(at) else { break }
                session.rounds[at].score.suddenDeathCourt = court
                state = .friendly(session)
            case .tournament(var tournament):
                guard tournament.isLadder, let at = round ?? tournament.rounds.indices.last,
                      tournament.rounds.indices.contains(at),
                      let match = tournament.rounds[at].matches.firstIndex(where: { $0.courtIndex == index ?? 0 }),
                      tournament.rounds[at].matches[match].games != nil else { break }
                tournament.rounds[at].matches[match].games?.suddenDeathCourt = court
                state = .tournament(tournament)
            case .pointCount, .none:
                break
            }

        case .endRound(let round, let at):
            switch state {
            case .winnerCourt(var session):
                guard !session.isFinished, session.score.completedSets.count == round else { return }
                session.score = session.engine.endingRound(session.score)
                // The whistle closes one round and opens the next in the same move, so it is
                // also where the clock starts again.
                session.roundStartedAt = at
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

            case .tournament(var tournament):
                // Every court stops where it stands; a court still level then plays one point.
                // Only the round in play, and only once, so two whistles close one round.
                guard tournament.isLadder, !tournament.isFinished, tournament.rounds.count == round + 1,
                      !tournament.rounds[round].isCancelled, !tournament.rounds[round].isEnded else { return }
                tournament.rounds[round].isEnded = true
                state = .tournament(tournament)

            case .traditional, .pointCount, .none:
                break
            }

        case .setFirstServer(let round, let court, let index):
            mutateCourt(round: round, court: court, in: &state) { _, match in
                match.state.firstServerIndex = index
            } traditional: { session in
                session.score.firstServerIndex = index
            } ladder: { _, _, _, match in
                match.games?.firstServerIndex = index
            }

        case .setServeOrder(let round, let court, let order):
            mutateCourt(round: round, court: court, in: &state) { _, match in
                match.state.serveOrder = order
            } traditional: { session in
                session.score.serveOrder = order
            } ladder: { _, _, _, match in
                match.serveOrder = order
            }

        case .setRoundConfirmed(let round, let isConfirmed):
            guard case .tournament(var tournament) = state, !tournament.isFinished,
                  tournament.rounds.indices.contains(round) else { return }
            for court in tournament.rounds[round].matches.indices {
                tournament.rounds[round].matches[court].isConfirmed = isConfirmed
            }
            state = .tournament(tournament)

        case .setRoundCancelled(let round, let isCancelled):
            guard case .tournament(var tournament) = state, !tournament.isFinished,
                  tournament.rounds.count == round + 1 else { return }
            tournament.rounds[round].isCancelled = isCancelled
            state = .tournament(tournament)

        case .nextRound(let after, let at, let sitOuts, let placed):
            switch state {
            case .tournament(let tournament):
                // A draw that crossed the finish would add a round nobody played to the
                // standings, and pay its bench for sitting it out.
                guard !tournament.isFinished else { return }
                let drawing: Tournament? = if tournament.rounds.count == after + 1 {
                    try? TournamentEngine.appendingRound(to: tournament, sitOuts: sitOuts, placed: placed)
                } else if let sitOuts, tournament.rounds.count == after + 2, tournament.canRedrawCurrentRound {
                    try? TournamentEngine.redrawingLastRound(of: tournament, sitOuts: sitOuts, placed: placed)
                } else {
                    nil
                }
                guard var next = drawing, let drawn = next.rounds.indices.last else { return }
                // Stamped here rather than read back off the log: a second device drawing at
                // the same moment is turned away by the guard above, and only this knows it.
                next.rounds[drawn].startedAt = at
                if let minutes = next.ladder?.roundMinutes {
                    next.rounds[drawn].clock = RoundClock(length: TimeInterval(minutes * 60), runningSince: at)
                }
                state = .tournament(next)

            case .friendly(let session):
                // Only over a round that is over. A draw that crossed the winning point being
                // taken back, or a late point turning it into deuce, would otherwise leave that
                // round open behind the next with no way back to it.
                guard !session.isFinished, session.rounds.count == after + 1,
                      session.currentRound?.isFinished ?? true,
                      var next = try? FriendlyScheduler.appendingRound(to: session),
                      let drawn = next.rounds.indices.last else { return }
                next.rounds[drawn].startedAt = at
                state = .friendly(next)

            case .traditional, .winnerCourt, .pointCount, .none:
                break
            }

        case .setRoundClock(let round, let clock):
            guard case .tournament(var tournament) = state, tournament.ladder?.isTimed == true,
                  !tournament.isFinished, tournament.rounds.count == round + 1,
                  !tournament.rounds[round].isCancelled, !tournament.rounds[round].isEnded else { return }
            tournament.rounds[round].clock = clock
            state = .tournament(tournament)

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

        case .undo, .unrecognised:
            break
        }
    }

    /// A configure that lands on a session of the same kind is the setup being corrected
    /// rather than a session starting, so only the fresh branches take the stamp — putting a
    /// name right must not restart the clock.
    private static func configure(
        _ setup: SessionSetup,
        at: Date?,
        warmupStartedAt: Date?,
        into state: inout SessionState?
    ) {
        switch (setup, state) {
        case (.traditional(let rules, let teams), .traditional(var session)):
            session.rules = rules
            session.teams = teams
            state = .traditional(session)

        case (.traditional(let rules, let teams), _):
            state = .traditional(TraditionalSession(
                rules: rules,
                teams: teams,
                score: TraditionalState(),
                startedAt: at,
                warmupStartedAt: warmupStartedAt
            ))

        case (.tournament(let incoming), .tournament(var tournament)):
            tournament.name = incoming.name
            tournament.players = incoming.players
            tournament.config = incoming.config
            state = .tournament(tournament)

        case (.tournament(let incoming), _):
            // The rounds come from the draw, which has not happened yet, so there is nothing
            // to stamp here — `nextRound` starts the first one's clock.
            var tournament = incoming
            tournament.warmupStartedAt = warmupStartedAt
            state = .tournament(tournament)

        case (.winnerCourt(let rules, let teams), .winnerCourt(var session)):
            session.rules = rules
            session.teams = teams
            state = .winnerCourt(session)

        case (.winnerCourt(let rules, let teams), _):
            state = .winnerCourt(WinnerCourtSession(
                rules: rules,
                teams: teams,
                roundStartedAt: at,
                warmupStartedAt: warmupStartedAt
            ))

        case (.pointCount(let rules, let teams), .pointCount(var session)):
            session.rules = rules
            session.teams = teams
            state = .pointCount(session)

        case (.pointCount(let rules, let teams), _):
            state = .pointCount(PointCountSession(
                rules: rules,
                teams: teams,
                startedAt: at,
                warmupStartedAt: warmupStartedAt
            ))

        case (.friendly(let incoming), .friendly(var session)):
            // The rounds already played stay where they are; the rest is the setup being
            // corrected. The id is not adopted — it seeds the draw, and re-seeding it would
            // re-partner every round still to come.
            session.name = incoming.name
            session.rules = incoming.rules
            session.players = incoming.players
            state = .friendly(session)

        case (.friendly(let incoming), _):
            var session = incoming
            session.warmupStartedAt = warmupStartedAt
            state = .friendly(session)
        }
    }

    private static func mutateCourt(
        round: Int,
        court: Int,
        in state: inout SessionState?,
        tournament change: (PointCountEngine, inout CourtMatch) -> Void,
        traditional: (inout TraditionalSession) -> Void,
        ladder: (LadderRules, CourtStatus, _ isEnded: Bool, inout CourtMatch) -> Void
    ) {
        // Nothing lands on a session somebody ended. A match played to its end already turns
        // points away by itself; one called off part way has to be told.
        switch state {
        case .traditional(var session):
            guard !session.isStopped else { return }
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
            guard !current.isFinished, current.rounds.indices.contains(round), !current.rounds[round].isCancelled,
                  let index = current.rounds[round].matches.firstIndex(where: { $0.courtIndex == court }),
                  !current.rounds[round].matches[index].isConfirmed
            else { return }
            if let rules = current.ladder {
                let played = current.rounds[round]
                let status = current.status(of: played.matches[index], in: played)
                ladder(rules, status, played.isEnded, &current.rounds[round].matches[index])
            } else {
                change(current.pointEngine, &current.rounds[round].matches[index])
            }
            state = .tournament(current)

        case .none:
            break
        }
    }
}
