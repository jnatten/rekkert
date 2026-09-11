import Foundation
import RekkertCore

public enum DeviceIdentity {
    private static let key = "dev.natten.rekkert.deviceID"

    /// Stable for the life of the install, which is what event ids are namespaced by.
    public static func current(defaults: UserDefaults = .standard) -> DeviceID {
        if let raw = defaults.string(forKey: key), let uuid = UUID(uuidString: raw) {
            return DeviceID(uuid)
        }
        let device = DeviceID()
        defaults.set(device.raw.uuidString, forKey: key)
        return device
    }
}
