import Foundation
import Testing
@testable import RekkertCore

/// Pinned before players could leave (spec 008, D-13). Fix the draw, never these values.
@Suite("A tournament nobody leaves draws as it always has")
struct TournamentNoAbsenceFingerprintTests {
    @Test(arguments: [TournamentFormat.americano, .mexicano], 5 ... 16)
    func twentyRoundsAsBefore(format: TournamentFormat, players: Int) throws {
        for courts in 1 ... 4 {
            let key = "\(format == .americano ? "americano" : "mexicano")-\(players)-\(courts)"
            let drawn = try Self.draw(format, players: players, courts: courts)
            let value = TournamentFixture.fingerprint(drawn.rounds.map { TournamentFixture.rendered($0, in: drawn) })
            #expect(Self.pinned[key] == value, "\"\(key)\": \(value),")
        }
    }

    /// Twenty rounds as the store draws them, with round 3 drawn again around a sit-out picked by
    /// hand wherever there is a bench to pick.
    static func draw(_ format: TournamentFormat, players: Int, courts: Int) throws -> Tournament {
        var tournament = TournamentFixture.make(format, players: players, courts: courts)
        for index in 0 ..< 20 {
            tournament = try TournamentFixture.draw(tournament)
            if index == 2, tournament.benchSize > 0, let first = tournament.rounds[index].matches.first?.teams.a.first {
                tournament = try TournamentFixture.redraw(tournament, picking: [first])
            }
            tournament = TournamentFixture.score(tournament, round: index)
        }
        return tournament
    }

    private static let pinned: [String: UInt64] = [
        "americano-5-1": 7066714343664973513,
        "americano-5-2": 7066714343664973513,
        "americano-5-3": 7066714343664973513,
        "americano-5-4": 7066714343664973513,
        "americano-6-1": 3757129988288136397,
        "americano-6-2": 3757129988288136397,
        "americano-6-3": 3757129988288136397,
        "americano-6-4": 3757129988288136397,
        "americano-7-1": 7174322741876650069,
        "americano-7-2": 7174322741876650069,
        "americano-7-3": 7174322741876650069,
        "americano-7-4": 7174322741876650069,
        "americano-8-1": 11540978003094703083,
        "americano-8-2": 13468067281868471069,
        "americano-8-3": 13468067281868471069,
        "americano-8-4": 13468067281868471069,
        "americano-9-1": 1753781498999735173,
        "americano-9-2": 6003416670484407619,
        "americano-9-3": 6003416670484407619,
        "americano-9-4": 6003416670484407619,
        "americano-10-1": 17178005159410966433,
        "americano-10-2": 10166530685423196649,
        "americano-10-3": 10166530685423196649,
        "americano-10-4": 10166530685423196649,
        "americano-11-1": 3488836937924650515,
        "americano-11-2": 11557938513977517785,
        "americano-11-3": 11557938513977517785,
        "americano-11-4": 11557938513977517785,
        "americano-12-1": 17043542599677364959,
        "americano-12-2": 9233013327518738869,
        "americano-12-3": 3598590620406810961,
        "americano-12-4": 3598590620406810961,
        "americano-13-1": 5822422554944145949,
        "americano-13-2": 16590835192249920343,
        "americano-13-3": 2404286816026086045,
        "americano-13-4": 2404286816026086045,
        "americano-14-1": 13062671138905409007,
        "americano-14-2": 12144622726975125745,
        "americano-14-3": 2620438503965682223,
        "americano-14-4": 2620438503965682223,
        "americano-15-1": 8980793164025383287,
        "americano-15-2": 3091328070991337791,
        "americano-15-3": 10590798226717015715,
        "americano-15-4": 10590798226717015715,
        "americano-16-1": 15130038816748434689,
        "americano-16-2": 10691596244187470461,
        "americano-16-3": 10829775721481760273,
        "americano-16-4": 14431764530265286099,
        "mexicano-5-1": 16933920774010242777,
        "mexicano-5-2": 16933920774010242777,
        "mexicano-5-3": 16933920774010242777,
        "mexicano-5-4": 16933920774010242777,
        "mexicano-6-1": 16859984673587728135,
        "mexicano-6-2": 16859984673587728135,
        "mexicano-6-3": 16859984673587728135,
        "mexicano-6-4": 16859984673587728135,
        "mexicano-7-1": 15291808738038649753,
        "mexicano-7-2": 15291808738038649753,
        "mexicano-7-3": 15291808738038649753,
        "mexicano-7-4": 15291808738038649753,
        "mexicano-8-1": 1347004165915793187,
        "mexicano-8-2": 17591399291281988499,
        "mexicano-8-3": 17591399291281988499,
        "mexicano-8-4": 17591399291281988499,
        "mexicano-9-1": 3366112318989838653,
        "mexicano-9-2": 7627866541527031241,
        "mexicano-9-3": 7627866541527031241,
        "mexicano-9-4": 7627866541527031241,
        "mexicano-10-1": 9690697568622640997,
        "mexicano-10-2": 17557602302302980417,
        "mexicano-10-3": 17557602302302980417,
        "mexicano-10-4": 17557602302302980417,
        "mexicano-11-1": 16136853095518569383,
        "mexicano-11-2": 5851571702091059547,
        "mexicano-11-3": 5851571702091059547,
        "mexicano-11-4": 5851571702091059547,
        "mexicano-12-1": 14027480938768451559,
        "mexicano-12-2": 6674165817494819607,
        "mexicano-12-3": 3657481414147661735,
        "mexicano-12-4": 3657481414147661735,
        "mexicano-13-1": 9007799063222297305,
        "mexicano-13-2": 4424672679789549179,
        "mexicano-13-3": 9260485613743713423,
        "mexicano-13-4": 9260485613743713423,
        "mexicano-14-1": 6158558290363710779,
        "mexicano-14-2": 3378948224619536719,
        "mexicano-14-3": 17938759783711172437,
        "mexicano-14-4": 17938759783711172437,
        "mexicano-15-1": 14003335138021045203,
        "mexicano-15-2": 15990246088057702273,
        "mexicano-15-3": 16738523984806492687,
        "mexicano-15-4": 16738523984806492687,
        "mexicano-16-1": 13523911539028987767,
        "mexicano-16-2": 10445470747339564621,
        "mexicano-16-3": 13093582942258935153,
        "mexicano-16-4": 1159027271833756263,
    ]
}
