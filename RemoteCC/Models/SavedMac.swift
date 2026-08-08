import Foundation

/// A Mac the user has registered for Wake-on-LAN + screen sharing (VNC).
/// The VNC password is NOT stored here — it lives in the Keychain, keyed by `id`.
struct SavedMac: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// IP address or hostname on the local network, e.g. "192.168.1.23" or "MacBook-Air.local"
    var host: String
    /// MAC address of the Mac's network interface, format "AA:BB:CC:DD:EE:FF" — used for Wake-on-LAN.
    var macAddress: String
    /// Screen Sharing (VNC) port. macOS default is 5900.
    var vncPort: Int = 5900
    /// Optional VNC username (macOS Screen Sharing supports username + password login).
    var username: String = ""
}
