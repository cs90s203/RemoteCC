import Foundation
import Observation

/// Persists the list of saved Macs (metadata only) in UserDefaults.
/// VNC passwords are stored separately in KeychainStore.
@Observable
final class MacStore {
    private static let defaultsKey = "com.cs90s203.RemoteCC.savedMacs"

    private(set) var macs: [SavedMac] = []

    init() {
        load()
    }

    func add(_ mac: SavedMac, password: String, sshPassword: String = "") {
        macs.append(mac)
        if !password.isEmpty {
            KeychainStore.savePassword(password, for: mac.id)
        }
        if !sshPassword.isEmpty {
            KeychainStore.saveSSHPassword(sshPassword, for: mac.id)
        }
        save()
    }

    func update(_ mac: SavedMac, password: String?, sshPassword: String? = nil) {
        guard let index = macs.firstIndex(where: { $0.id == mac.id }) else { return }
        macs[index] = mac
        if let password, !password.isEmpty {
            KeychainStore.savePassword(password, for: mac.id)
        }
        if let sshPassword, !sshPassword.isEmpty {
            KeychainStore.saveSSHPassword(sshPassword, for: mac.id)
        }
        save()
    }

    func delete(_ mac: SavedMac) {
        macs.removeAll { $0.id == mac.id }
        KeychainStore.deletePassword(for: mac.id)
        KeychainStore.deleteSSHPassword(for: mac.id)
        save()
    }

    func password(for mac: SavedMac) -> String {
        KeychainStore.password(for: mac.id) ?? ""
    }

    func sshPassword(for mac: SavedMac) -> String {
        KeychainStore.sshPassword(for: mac.id) ?? ""
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([SavedMac].self, from: data)
        else { return }
        macs = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(macs) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
