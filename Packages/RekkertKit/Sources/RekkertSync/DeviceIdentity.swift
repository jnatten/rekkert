import Foundation
import RekkertCore

public enum DeviceIdentity {
    private static let key = "dev.natten.rekkert.deviceID"

    /// Stable for the life of the install, which is what event ids are namespaced by — and this
    /// install's alone. Kept out of backups: a backup restored onto a second phone brought the id
    /// with it, and two phones on one match with one id gave two different events the same name,
    /// each keeping whichever it heard first.
    public static func current(defaults: UserDefaults = .standard, file: URL? = defaultFile) -> DeviceID {
        if let file, let raw = try? String(contentsOf: file, encoding: .utf8),
           let uuid = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return DeviceID(uuid)
        }
        // An install from before this kept it in the defaults, which go into a backup. Moved out of
        // them, the next backup leaves it behind.
        let device = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)).map(DeviceID.init) ?? DeviceID()
        guard let file, keep(device, in: file) else {
            defaults.set(device.raw.uuidString, forKey: key)
            return device
        }
        defaults.removeObject(forKey: key)
        return device
    }

    public static var defaultFile: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Rekkert/device-id")
    }

    private static func keep(_ device: DeviceID, in file: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try device.raw.uuidString.write(to: file, atomically: true, encoding: .utf8)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = file
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }
}
