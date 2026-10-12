import Foundation

/// The bands of Apple's 1–10 effort rating, as the Workout app names them.
public enum WorkoutEffort: Sendable, Hashable {
    case easy, moderate, hard, allOut

    public static let range = 1 ... 10

    public init(score: Int) {
        switch score {
        case ...3: self = .easy
        case 4 ... 6: self = .moderate
        case 7 ... 8: self = .hard
        default: self = .allOut
        }
    }

    public var title: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        case .allOut: "All Out"
        }
    }
}
