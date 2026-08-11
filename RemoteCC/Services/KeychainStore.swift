import Foundation
import Security

/// Minimal Keychain wrapper for storing per-Mac VNC and SSH passwords.
/// Passwords never touch UserDefaults or get synced anywhere except the device Keychain.
enum KeychainStore {
    private static let vncService = "com.cs90s203.RemoteCC.vncPassword"
    private static let sshService = "com.cs90s203.RemoteCC.sshPassword"

    static func savePassword(_ password: String, for macID: UUID) {
        save(password, service: vncService, account: macID.uuidString)
    }

    static func password(for macID: UUID) -> String? {
        password(service: vncService, account: macID.uuidString)
    }

    static func deletePassword(for macID: UUID) {
        delete(service: vncService, account: macID.uuidString)
    }

    static func saveSSHPassword(_ password: String, for macID: UUID) {
        save(password, service: sshService, account: macID.uuidString)
    }

    static func sshPassword(for macID: UUID) -> String? {
        password(service: sshService, account: macID.uuidString)
    }

    static func deleteSSHPassword(for macID: UUID) {
        delete(service: sshService, account: macID.uuidString)
    }

    // MARK: - Private helpers

    private static func save(_ password: String, service: String, account: String) {
        let data = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemAdd(newItem as CFDictionary, nil)
    }

    private static func password(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
