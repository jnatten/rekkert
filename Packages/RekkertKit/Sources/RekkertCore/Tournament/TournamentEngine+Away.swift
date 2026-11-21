/// Leaving an Americano or Mexicano early, and coming back (spec 008, D-3 and D-4).
extension TournamentEngine {
    /// What `setAway` folds to. Decided by the round in play as it stands here, so every device
    /// folding the same log lands on the same tournament: `after` and `placed` only say whether
    /// the redraw the marking device carried is for this round.
    public static func settingAway(
        _ player: PlayerID, isAway: Bool, after: Int, placed: RoundPlacement?, in tournament: Tournament
    ) -> Tournament {
        guard !tournament.isLadder, !tournament.isFinished, tournament.player(player) != nil else { return tournament }
        guard isAway else { return comingBack(player, after: after, placed: placed, in: tournament) }
        var marked = tournament
        guard let last = tournament.currentRound, !last.isCancelled, !tournament.isDone(last) else {
            // Between rounds: from the next one drawn.
            guard !tournament.isAway(player) else { return tournament }
            marked.absences.append(TournamentAbsence(player: player, from: tournament.rounds.count))
            return marked
        }

        if tournament.canRedrawCurrentRound {
            // Nothing played yet, so nobody has walked onto it: drawn again without them, as
            // picking the bench by hand does.
            let isIn = last.matches.contains { $0.side(of: player) != nil } || last.sitOuts.contains(player)
            if !tournament.isAway(player) {
                marked.absences.append(TournamentAbsence(player: player, from: last.index))
            } else if !isIn {
                return tournament
            }
            return redrawingRoundInPlay(of: marked, keeping: last.sitOuts, after: after, placed: placed)
        }

        // Points on the board: their court stops where it stands and counts for all four.
        if !tournament.isAway(player) {
            marked.absences.append(TournamentAbsence(player: player, from: last.index + 1))
        }
        if let court = last.matches.firstIndex(where: { $0.side(of: player) != nil }),
           !last.matches[court].isConfirmed, !tournament.status(of: last.matches[court], in: last).isFinished {
            marked.rounds[last.index].matches[court].isConfirmed = true
        }
        return marked
    }

    /// Back from the next round, or for the round in play when nothing has been played in it.
    /// Brought back before missing anything, the absence goes, and they are drawn as if never
    /// marked.
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

    /// The round in play drawn again for whoever is here for it, its bench kept as picks as far
    /// as the new bench allows. The marking device's own redraw is taken when it is for this
    /// round; otherwise it is drawn here, as `MatchStore.redrawRound` draws one. With too few
    /// left for a court it is called off, which costs nobody anything since nothing was played.
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

    /// What `settingAway` would do now, for the confirmation; nil when it would do nothing.
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
