/// Whether this device can record a workout, and if not, the first reason why.
public enum HealthReach: Equatable, Sendable {
    case canRecord
    case unavailable
    case cannotPair
    case noWatch
    case watchAppMissing

    public init(healthAvailable: Bool, canPairWatch: Bool, isPaired: Bool, watchAppInstalled: Bool) {
        self =
            if !healthAvailable { .unavailable }
            else if !canPairWatch { .cannotPair }
            else if !isPaired { .noWatch }
            else if !watchAppInstalled { .watchAppMissing }
            else { .canRecord }
    }

    public var line: String? {
        switch self {
        case .canRecord: nil
        case .unavailable: "Apple Health isn't available on this device, so Rekkert never uses it here."
        case .cannotPair:
            "Workouts are recorded by an Apple Watch paired with an iPhone. Rekkert doesn't use Apple Health on iPad."
        case .noWatch: "Recording a workout needs an Apple Watch paired with this iPhone."
        case .watchAppMissing: "Install Rekkert on your Apple Watch to record workouts."
        }
    }
}
