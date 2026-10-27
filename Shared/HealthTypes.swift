import HealthKit
import RekkertCore

extension HealthData {
    var objectType: HKObjectType {
        switch self {
        case .workout: HKQuantityType.workoutType()
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .restingEnergy: HKQuantityType(.basalEnergyBurned)
        case .effort: HKQuantityType(.workoutEffortScore)
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .dateOfBirth: HKCharacteristicType(.dateOfBirth)
        }
    }

    var sampleType: HKSampleType? { objectType as? HKSampleType }
}

extension HealthDisclosure {
    static func toShare(on device: HealthDevice) -> Set<HKSampleType> {
        Set(saved(on: device).compactMap(\.sampleType))
    }

    static func toRead(on device: HealthDevice) -> Set<HKObjectType> {
        Set(read(on: device).map(\.objectType))
    }
}

extension HealthAsk.Status {
    init(_ status: HKAuthorizationRequestStatus) {
        self =
            switch status {
            case .shouldRequest: .wouldAsk
            case .unnecessary: .alreadyAsked
            default: .unknown
            }
    }
}

extension HKHealthStore {
    func askStatus(on device: HealthDevice) async -> HealthAsk.Status {
        guard let status = try? await statusForAuthorizationRequest(
            toShare: HealthDisclosure.toShare(on: device),
            read: HealthDisclosure.toRead(on: device)
        ) else { return .unknown }
        return HealthAsk.Status(status)
    }
}
