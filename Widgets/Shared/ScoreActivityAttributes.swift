import ActivityKit
import Foundation
import RekkertCore

nonisolated struct ScoreActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveScore

    var sessionID: UUID
}
