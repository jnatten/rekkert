import Foundation
import RekkertCore
import Testing

@Suite("Telling the wrist the match went, and came back")
struct ReachCueTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func outOfReachForFifteenSecondsTapsOnceAndBackTapsAgain() {
        var cue = ReachCue()
        var heard: [ReachCue.Cue?] = []
        for second in [0.0, 14, 15, 30] { heard.append(cue.observe(isInReach: false, at: at(second))) }
        heard.append(cue.observe(isInReach: true, at: at(31)))
        heard.append(cue.observe(isInReach: true, at: at(32)))
        #expect(heard == [nil, nil, .outOfReach, nil, .backInStep, nil])
    }

    @Test func aDropShorterThanTheWaitSaysNothingEitherWay() {
        var cue = ReachCue()
        #expect(cue.observe(isInReach: false, at: at(0)) == nil)
        #expect(cue.observe(isInReach: false, at: at(10)) == nil)
        #expect(cue.observe(isInReach: true, at: at(11)) == nil)
        #expect(cue.observe(isInReach: false, at: at(20)) == nil)
        #expect(cue.observe(isInReach: false, at: at(34)) == nil, "counted again from the second drop")
    }
}
