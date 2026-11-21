/// Leaving an Americano or Mexicano early, and coming back (spec 008, D-3 and D-4).
extension TournamentEngine {
    /// What `setAway` folds to. Decided by the round in play as it stands here, so every device
    /// folding the same log lands on the same tournament: `after` and `placed` only say whether
    /// the redraw the marking device carried is for this round.
    public static func settingAway(
        _ player: PlayerID, isAway: Bool, after: Int, placed: RoundPlacement?, in tournament: Tournament
    ) -> Tournament {
        guard !tournament.isLadder, !tournament.isFinished, tournament.player(player) != nil else { return tournament }
        let last = tournament.currentRound
        let isSettled = last.map { $0.isCancelled || tournament.isDone($0) } ?? true
        let next = (last?.index ?? -1) + 1
        var marked = tournament

        if isAway {
            guard !tournament.isAway(player), isSettled else { return tournament }
            marked.absences.append(TournamentAbsence(player: player, from: next))
        } else {
            return tournament
        }
        return marked
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
