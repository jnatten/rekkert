import HealthKit
import RekkertCore

extension HealthData {
    var objectType: HKObjectType? {
        switch self {
        case .workout: HKQuantityType.workoutType()
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .restingEnergy: HKQuantityType(.basalEnergyBurned)
        case .effort:
            if #available(watchOS 11, *) { HKQuantityType(.workoutEffortScore) } else { nil }
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .dateOfBirth: HKCharacteristicType(.dateOfBirth)
        }
    }

    var sampleType: HKSampleType? { objectType as? HKSampleType }
}

extension HealthDisclosure {
    private static var effortInAppleHealth: Bool { HealthData.effort.objectType != nil }

    static func toShare(on device: HealthDevice) -> Set<HKSampleType> {
        Set(saved(on: device, effortInAppleHealth: effortInAppleHealth).compactMap(\.sampleType))
    }

    static func toRead(on device: HealthDevice) -> Set<HKObjectType> {
        Set(read(on: device, effortInAppleHealth: effortInAppleHealth).compactMap(\.objectType))
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
