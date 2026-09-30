import Foundation
import RekkertCore
import Testing
@testable import RekkertSync

@Suite("Which device this is")
struct DeviceIdentityTests {
    private func scratch() -> (UserDefaults, URL, () -> Void) {
        let suite = "rekkert-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: suite)
        return (defaults, directory.appending(path: "device-id"), {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test func theSameDeviceEveryTime() {
        let (defaults, file, cleanUp) = scratch()
        defer { cleanUp() }
        #expect(DeviceIdentity.current(defaults: defaults, file: file) == DeviceIdentity.current(defaults: defaults, file: file))
    }

    /// Restored onto a second phone, a backup brought the id with it, and two phones at one match
    /// named two different events the same.
    @Test func itStaysOutOfBackups() throws {
        let (defaults, file, cleanUp) = scratch()
        defer { cleanUp() }
        _ = DeviceIdentity.current(defaults: defaults, file: file)
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        #expect(defaults.string(forKey: "dev.natten.rekkert.deviceID") == nil, "nor in the defaults, which a backup carries")
    }

    @Test func anInstallFromBeforeKeepsItsId() {
        let (defaults, file, cleanUp) = scratch()
        defer { cleanUp() }
        let earlier = UUID()
        defaults.set(earlier.uuidString, forKey: "dev.natten.rekkert.deviceID")

        #expect(DeviceIdentity.current(defaults: defaults, file: file).raw == earlier)
        #expect(DeviceIdentity.current(defaults: defaults, file: file).raw == earlier, "still, once moved out of the defaults")
        #expect(defaults.string(forKey: "dev.natten.rekkert.deviceID") == nil)
    }
}
