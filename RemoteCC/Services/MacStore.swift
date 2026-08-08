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

    func add(_ mac: SavedMac, password: String) {
        macs.append(mac)
        if !password.isEmpty {
            KeychainStore.savePassword(password, for: mac.id)
        }
        save()
    }

    func update(_ mac: SavedMac, password: String?) {
        guard let index = macs.firstIndex(where: { $0.id == mac.id }) else { return }
        macs[index] = mac
        if let password, !password.isEmpty {
            KeychainStore.savePassword(password, for: mac.id)
        }
        save()
    }

    func delete(_ mac: SavedMac) {
        macs.removeAll { $0.id == mac.id }
        KeychainStore.deletePassword(for: mac.id)
        save()
    }

    func password(for mac: SavedMac) -> String {
        KeychainStore.password(for: mac.id) ?? ""
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
