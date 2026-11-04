public enum HealthData: CaseIterable, Sendable {
    case workout
    case activeEnergy
    case restingEnergy
    case effort
    case heartRate
    case restingHeartRate
    case dateOfBirth

    public var title: String {
        switch self {
        case .workout: "Workouts"
        case .activeEnergy: "Active energy"
        case .restingEnergy: "Resting energy"
        case .effort: "Effort"
        case .heartRate: "Heart rate"
        case .restingHeartRate: "Resting heart rate"
        case .dateOfBirth: "Date of birth"
        }
    }

    public var reason: String {
        switch self {
        case .workout: "The session you played, saved as indoor tennis"
        case .activeEnergy: "What the session burned, saved with the workout and shown on it"
        case .restingEnergy: "Added to active energy for the total, as the Workout app does"
        case .effort:
            "How hard you rated it, on the 1–10 scale. From a watch on watchOS 10 it stays in Rekkert and is not saved to Apple Health."
        case .heartRate: "Shown on your wrist while you play, and on the match afterwards"
        case .restingHeartRate: "To place your heart rate in zones"
        case .dateOfBirth: "Your age, to estimate the top of your zones"
        }
    }
}

public enum HealthDevice: Sendable {
    case phone
    case watch
}

/// The one statement of what Rekkert does with Apple Health. Both apps build their requests
/// from it, so what Settings says is what they ask for.
public enum HealthDisclosure {
    /// `effortInAppleHealth` is false on a watch whose Apple Health has no place for an effort
    /// rating (before watchOS 11); the rating then stays in Rekkert.
    public static func saved(on device: HealthDevice, effortInAppleHealth: Bool = true) -> [HealthData] {
        let kinds: [HealthData] =
            switch device {
            case .phone: [.workout]
            case .watch: [.workout, .activeEnergy, .restingEnergy, .effort]
            }
        return effortInAppleHealth ? kinds : kinds.filter { $0 != .effort }
    }

    public static func read(on device: HealthDevice, effortInAppleHealth: Bool = true) -> [HealthData] {
        let kinds: [HealthData] =
            switch device {
            case .phone: []
            case .watch: [.heartRate, .activeEnergy, .restingEnergy, .restingHeartRate, .dateOfBirth, .workout, .effort]
            }
        return effortInAppleHealth ? kinds : kinds.filter { $0 != .effort }
    }

    public static let summary =
        "Rekkert can save the workouts your Apple Watch records to Apple Health, and reads your heart rate and energy while one is running. Nothing it reads leaves your iPhone and Apple Watch."

    public static let when = "Only while a workout you started is running, and once more when it ends."

    public static let whereItGoes =
        "It stays on your iPhone and Apple Watch, and is never sent to other phones or anywhere else."

    public static let changeAccess = [
        "Settings › Privacy & Security › Health › Rekkert",
        "Or in the Apple Health app: your picture › Apps › Rekkert",
    ]
}
