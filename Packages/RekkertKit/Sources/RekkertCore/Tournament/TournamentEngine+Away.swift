extension TournamentEngine {
    /// Decided by the round in play as it stands here, so every device folding the same log lands
    /// on the same tournament; `after` only says whether the carried `placed` is for this round.
    public static func settingAway(
        _ player: PlayerID, isAway: Bool, after: Int, placed: RoundPlacement?, in tournament: Tournament
    ) -> Tournament {
        guard !tournament.isLadder, !tournament.isFinished, tournament.player(player) != nil else { return tournament }
        guard isAway else { return comingBack(player, after: after, placed: placed, in: tournament) }
        var marked = tournament
        guard let last = tournament.currentRound, !last.isCancelled, !tournament.isDone(last) else {
            guard !tournament.isAway(player) else { return tournament }
            marked.absences.append(TournamentAbsence(player: player, from: tournament.rounds.count))
            return marked
        }

        if tournament.canRedrawCurrentRound {
            let isIn = last.matches.contains { $0.side(of: player) != nil } || last.sitOuts.contains(player)
            if !tournament.isAway(player) {
                marked.absences.append(TournamentAbsence(player: player, from: last.index))
            } else if !isIn {
                return tournament
            }
            return redrawingRoundInPlay(of: marked, keeping: last.sitOuts, after: after, placed: placed)
        }

        if !tournament.isAway(player) {
            marked.absences.append(TournamentAbsence(player: player, from: last.index + 1))
        }
        if let court = last.matches.firstIndex(where: { $0.side(of: player) != nil }),
           !last.matches[court].isConfirmed, !tournament.status(of: last.matches[court], in: last).isFinished {
            marked.rounds[last.index].matches[court].isConfirmed = true
        }
        return marked
    }

    private static func comingBack(
        _ player: PlayerID, after: Int, placed: RoundPlacement?, in tournament: Tournament
    ) -> Tournament {
        guard let open = tournament.absences.lastIndex(where: { $0.player == player && $0.until == nil }) else {
            return tournament
        }
        var back = tournament
        let last = tournament.currentRound
        let redraws = last.map { !$0.isCancelled && !tournament.isDone($0) && tournament.canRedrawCurrentRound } ?? false
        let until = redraws ? last!.index : (last.map { $0.index + 1 } ?? 0)
        if until <= back.absences[open].from {
            back.absences.remove(at: open)
        } else {
            back.absences[open].until = until
        }
        guard redraws, let last else { return back }
        return redrawingRoundInPlay(of: back, keeping: last.sitOuts, after: after, placed: placed)
    }

    /// The bench is kept as picks as far as the new one allows, since a round records only its
    /// bench, not which of it was picked by hand. With too few left for a court the round is
    /// called off, which costs nobody anything since nothing was played in it.
    private static func redrawingRoundInPlay(
        of tournament: Tournament, keeping bench: [PlayerID], after: Int, placed: RoundPlacement?
    ) -> Tournament {
        guard let last = tournament.currentRound else { return tournament }
        var base = tournament
        _ = base.rounds.popLast()
        let picks = Array(bench.filter { tournament.isPresent($0, inRound: last.index) }.prefix(base.benchSize))
        let carried = after == last.index ? placed : nil
        let sitOuts = TournamentEngine.sitOuts(for: tournament, picked: picks, redrawing: true) ?? picks
        guard var redrawn = try? redrawingLastRound(of: tournament, sitOuts: sitOuts, placed: carried) else {
            var calledOff = tournament
            calledOff.rounds[last.index].isCancelled = true
            return calledOff
        }
        redrawn.rounds[last.index].startedAt = last.startedAt
        redrawn.rounds[last.index].clock = last.clock
        return redrawn
    }

    public static func awayPreview(_ player: PlayerID, isAway: Bool, in tournament: Tournament) -> AwayPreview? {
        let after = settingAway(player, isAway: isAway, after: tournament.rounds.count - 1, placed: nil, in: tournament)
        guard after != tournament else { return nil }

        let from: Int
        if isAway {
            from = after.absences.last { $0.player == player && $0.until == nil }?.from ?? tournament.rounds.count
        } else {
            from = tournament.absences.last { $0.player == player && $0.until == nil }
                .flatMap { open in after.absences.first { $0.player == player && $0.from == open.from }?.until } ?? tournament.rounds.count
        }
        func shape(_ tournament: Tournament) -> (courts: Int, bench: Int, here: Int) {
            let here = tournament.present(inRound: from).count
            let courts = min(tournament.config.courtCount, here / 4)
            return (courts, here - courts * 4, here)
        }
        let before = shape(tournament)
        let changed = shape(after)

        let redraws = after.rounds.count == tournament.rounds.count && after.currentRound != tournament.currentRound
            && after.currentRound?.matches.map(\.teams) != tournament.currentRound?.matches.map(\.teams)
        var stopping: AwayPreview.StoppingCourt?
        if let was = tournament.currentRound, let now = after.currentRound, was.index == now.index, !redraws {
            for match in now.matches where match.isConfirmed {
                if let earlier = was.matches.first(where: { $0.courtIndex == match.courtIndex }), !earlier.isConfirmed {
                    stopping = AwayPreview.StoppingCourt(court: match.courtIndex + 1, score: match.state.points)
                }
            }
        }

        return AwayPreview(
            player: player, isAway: isAway, fromRound: from + 1,
            courtsBefore: before.courts, courtsAfter: changed.courts,
            benchBefore: before.bench, benchAfter: changed.bench,
            redrawsRoundInPlay: redraws, stoppingCourt: stopping,
            isShortOfPlayers: changed.here < 4
        )
    }
}
