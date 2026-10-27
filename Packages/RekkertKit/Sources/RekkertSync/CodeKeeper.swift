import Foundation
import RekkertCore
import Security

/// Where a `KeptCode` lives between launches.
public protocol CodeKeeping: Sendable {
    /// The kept code while it lasts. One that has run out is let go of here.
    func read(now: Date) -> KeptCode?
    func keep(_ code: KeptCode)
    func forget()
}

/// This device's Keychain, and nowhere else: not synchronised, not in a backup, and readable
/// once the phone has been unlocked since it started, so a background relaunch can read it.
nonisolated public struct KeychainCodeKeeper: CodeKeeping {
    private static let service = "dev.natten.rekkert.kept-code"
    private static let account = "kept"

    public init() {}

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public func read(now: Date) -> KeptCode? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let kept = try? JSONCoding.decoder.decode(KeptCode.self, from: data)
        else { return nil }
        guard let current = kept.current(now: now) else {
            forget()
            return nil
        }
        return current
    }

    public func keep(_ code: KeptCode) {
        guard let data = try? JSONCoding.encoder.encode(code) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    public func forget() {
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated public final class MemoryCodeKeeper: CodeKeeping, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: KeptCode?

    public init(_ kept: KeptCode? = nil) {
        self.kept = kept
    }

    public func read(now: Date) -> KeptCode? {
        lock.withLock {
            guard let current = kept?.current(now: now) else {
                kept = nil
                return nil
            }
            return current
        }
    }

    public func keep(_ code: KeptCode) {
        lock.withLock { kept = code }
    }

    public func forget() {
        lock.withLock { kept = nil }
    }
}
