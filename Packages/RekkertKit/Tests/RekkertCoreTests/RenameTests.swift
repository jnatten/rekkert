import Foundation
import Testing

@testable import RekkertCore

@Suite("Renaming a finished session")
struct RenameTests {
    private func store() -> SessionStore {
        SessionStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
    }

    private func teams(_ a: String = "Us", _ b: String = "Them") -> BySide<TeamInfo> {
        BySide(
            a: TeamInfo(name: a, players: ["Jonas", "Ada"]),
            b: TeamInfo(name: b, players: ["Kim", "Sam"])
        )
    }

    /// A tournament with one round played out, so there are standings and round lines for a
    /// rename to have to reach.
    private func tournament() throws -> Tournament {
        var tournament = Tournament(
            name: "Thursday", format: .americano,
            players: ["Jonas", "Ada", "Kim", "Sam"].map { Player(name: $0) },
            config: TournamentConfig(pointRules: PointCountRules(target: 16))
        )
        tournament = try TournamentEngine.appendingRound(to: tournament)
        tournament.rounds[0].matches[0].state = PointCountEngine(rules: tournament.config.pointRules)
            .play(repeated([.a], 10) + repeated([.b], 6))
        return tournament
    }

    /// A friendly with one round played out, and five people so somebody is on the bench.
    private func friendly() throws -> FriendlySession {
        var session = FriendlySession(
            id: FriendlyID(UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!),
            name: "Fredagsmiks",
            rules: TraditionalRules(setsToWin: 1),
            players: ["Jonas", "Ola", "Kari", "Trond", "Siri"].map { Player(name: $0) }
        )
        session = try FriendlyScheduler.appendingRound(to: session)
        session.rounds[0].score = session.engine.winGames(6, for: .a, from: session.rounds[0].score)
        return session
    }

    private func renaming(_ session: FriendlySession, _ old: String, to new: String) -> SessionNames {
        .group(
            event: session.name,
            players: session.players.map { $0.name == old ? Player(id: $0.id, name: new) : $0 }
        )
    }

    // MARK: - People

    @Test func renamingAPlayerFollowsThroughToEveryRound() throws {
        let state = SessionState.tournament(try tournament())
        let corrected = state.players(renaming: "Ada", to: "Åse")
        let renamed = state.renamed(corrected)

        guard case .tournament(let before) = state, case .tournament(let after) = renamed else {
            Issue.record("still a tournament"); return
        }
        #expect(after.players.map(\.name).contains("Åse"))
        #expect(!after.players.map(\.name).contains("Ada"))
        #expect(after.rounds == before.rounds, "the rounds hold ids, so nothing in them moves")
        #expect(after.players.map(\.id) == before.players.map(\.id), "and the ids themselves are untouched")

        let placings = SessionResult.make(from: renamed).placings
        #expect(placings.map(\.name).contains("Åse"), "the table reads back through the players")
        #expect(Leaderboard.standings(for: after).map(\.player.name).contains("Åse"))
    }

    @Test func renamingAFriendlyReachesTheRoundLinesAndTheBench() throws {
        let session = try friendly()
        let benched = try #require(session.rounds[0].sitOuts.first)
        let sitting = session.name(benched)
        let playing = try #require(session.rounds[0].teams.a.first.map(session.name))

        // Both in the one go: each set of names is the whole list, so a second pass built
        // from the original would put the first one's name back.
        let renamed = SessionState.friendly(session).renamed(.group(
            event: session.name,
            players: session.players.map { player in
                switch player.name {
                case sitting: Player(id: player.id, name: "Benkeslitaren")
                case playing: Player(id: player.id, name: "Spelaren")
                default: player
                }
            }
        ))

        let result = SessionResult.make(from: renamed)
        let line = try #require(result.rounds.first)
        #expect(line.sitOuts == "Benkeslitaren", "the bench is named through the same list")
        #expect(line.teams.a.contains("Spelaren"), "and so is the partnership")
        #expect(result.placings.map(\.name).contains("Benkeslitaren"))
    }

    @Test func nobodyIsAddedOrRemoved() throws {
        let session = try friendly()
        let state = SessionState.friendly(session)
        let stranger = Player(name: "Somebody else")

        let renamed = state.renamed(.group(event: session.name, players: [stranger]))
        guard case .friendly(let after) = renamed else { Issue.record("still a friendly"); return }
        #expect(after.players == session.players, "an id that is not here means nobody")

        let short = state.renamed(.group(event: session.name, players: [session.players[0]]))
        guard case .friendly(let trimmed) = short else { Issue.record("still a friendly"); return }
        #expect(trimmed.players.count == session.players.count, "and a short list drops nobody")
    }

    // MARK: - Two-team modes

    @Test func renamingTheTeamsRewritesTheTitleAndTheHeadline() {
        var session = TraditionalSession(rules: TraditionalRules(setsToWin: 1), teams: teams())
        session.score = session.engine.winGames(6, for: .a, from: session.score)
        let state = SessionState.traditional(session)
        #expect(state.title == "Us vs Them")
        #expect(SessionResult.make(from: state).headline == "Us win")

        let renamed = state.renamed(.sides(teams("Blues", "Oranges")))
        #expect(renamed.title == "Blues vs Oranges")
        #expect(SessionResult.make(from: renamed).headline == "Blues win")
    }

    /// The serve badge picks the server out of the line-up by position, so a name typed into
    /// the second slot has to stay in the second slot.
    @Test func aLineUpKeepsItsPositions() {
        let state = SessionState.pointCount(PointCountSession(
            rules: PointCountRules(),
            teams: BySide(a: TeamInfo(name: "Us", players: []), b: TeamInfo(name: "Them"))
        ))
        let renamed = state.renamed(.sides(BySide(
            a: TeamInfo(name: "Us", players: ["", "Ada"]),
            b: TeamInfo(name: "Them")
        )))
        let after = try! #require(renamed.teamNames)
        #expect(after.a.players == ["", "Ada"], "the empty first slot is still the first slot")
    }

    // MARK: - Blank names

    @Test func aBlankNameIsIgnored() throws {
        let state = SessionState.winnerCourt(WinnerCourtSession(rules: WinnerCourtRules(), teams: teams()))
        let renamed = state.renamed(.sides(BySide(
            a: TeamInfo(name: "   ", players: ["", ""]),
            b: TeamInfo(name: "", players: ["Kim", ""])
        )))
        let after = try #require(renamed.teamNames)
        #expect(after.a.name == "Us", "clearing a name is not renaming anybody")
        #expect(after.a.players == ["Jonas", "Ada"])
        #expect(after.b.players == ["Kim", "Sam"], "and the second slot is left as it was")

        let session = try friendly()
        let blanked = SessionState.friendly(session)
            .renamed(renaming(session, "Ola", to: "  "))
        guard case .friendly(let people) = blanked else { Issue.record("still a friendly"); return }
        #expect(people.players.map(\.name).contains("Ola"))
    }

    @Test func clearingTheEventNameFallsBackToWhatTheModeIsCalled() throws {
        let tournament = SessionState.tournament(try tournament())
        #expect(tournament.renamed(.group(event: "", players: [])).title == "Americano")
        #expect(tournament.renamed(.group(event: "   ", players: [])).title == "Americano",
                "trimmed, since the fallback tests for empty rather than blank")

        let friendly = SessionState.friendly(try friendly())
        #expect(friendly.renamed(.group(event: " ", players: [])).title == "Friendly")
        #expect(friendly.renamed(.group(event: "Torsdag", players: [])).title == "Torsdag")
    }

    // MARK: - The shape

    @Test func namesOfTheWrongShapeAreIgnored() throws {
        let tournament = SessionState.tournament(try tournament())
        #expect(tournament.renamed(.sides(teams("Blues", "Oranges"))) == tournament)

        let match = SessionState.traditional(TraditionalSession(rules: TraditionalRules(), teams: teams()))
        #expect(match.renamed(.group(event: "Thursday", players: [])) == match)
    }

    @Test func onlyTheNamesChange() throws {
        let state = SessionState.tournament(try tournament())
        let renamed = state.renamed(state.players(renaming: "Kim", to: "Kim Andre"))

        #expect(renamed.hasResults == state.hasResults)
        #expect(renamed.canResume == state.canResume)
        #expect(SessionResult.make(from: renamed).score == SessionResult.make(from: state).score)
        #expect(SessionResult.make(from: renamed).placings.map(\.value)
                == SessionResult.make(from: state).placings.map(\.value))
    }

    // MARK: - The record

    @Test func theTitleFollowsTheStateItWasFiledUnder() throws {
        let filed = Date(timeIntervalSince1970: 768_000_000)
        let record = HistoryRecord(
            finishedAt: filed,
            title: "Us vs Them",
            state: .traditional(TraditionalSession(rules: TraditionalRules(), teams: teams())),
            startedAt: filed.addingTimeInterval(-3_600)
        )
        let renamed = record.renamed(.sides(teams("Blues", "Oranges")))

        #expect(renamed.title == "Blues vs Oranges")
        #expect(renamed.title == renamed.state.title, "title is only ever a copy of the state's")
        #expect(renamed.id == record.id, "so archiving it replaces rather than adds")
        #expect(renamed.finishedAt == record.finishedAt, "and it keeps its place in the list")
        #expect(renamed.startedAt == record.startedAt)
    }

    @Test func anEditedRecordReplacesTheOriginal() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let record = HistoryRecord(
            title: "Thursday",
            state: .tournament(try tournament())
        )
        try store.archive(record)
        try store.archive(record.renamed(.group(
            event: "Torsdagsamericano", players: record.state.namesOfPlayers(renaming: "Ada", to: "Åse")
        )))

        let shelf = try store.history()
        #expect(shelf.count == 1, "filed under the same id, so it is the same record")
        #expect(shelf[0].title == "Torsdagsamericano")
        #expect(Leaderboard.standings(for: try #require(shelf[0].state.asTournament))
            .map(\.player.name).contains("Åse"))
    }

    @Test func aRenamedRecordStillDecodes() throws {
        let record = HistoryRecord(title: "Fredagsmiks", state: .friendly(try friendly()))
            .renamed(.group(event: "Fredag", players: []))
        let decoded = try JSONCoding.decoder.decode(
            HistoryRecord.self, from: JSONCoding.encoder.encode(record)
        )
        #expect(decoded == record)
    }
}

// MARK: - Shorthands

private extension SessionState {
    /// Renaming one person by the name they go by now, which is how the sheet's edits arrive
    /// once the user has typed over a row.
    func players(renaming old: String, to new: String) -> SessionNames {
        .group(event: eventNameForTests, players: namesOfPlayers(renaming: old, to: new))
    }

    func namesOfPlayers(renaming old: String, to new: String) -> [Player] {
        guard case .group(_, let players) = names else { return [] }
        return players.map { $0.name == old ? Player(id: $0.id, name: new) : $0 }
    }

    var eventNameForTests: String {
        guard case .group(let event, _) = names else { return "" }
        return event
    }

    var teamNames: BySide<TeamInfo>? {
        guard case .sides(let teams) = names else { return nil }
        return teams
    }

    var asTournament: Tournament? {
        guard case .tournament(let tournament) = self else { return nil }
        return tournament
    }
}
