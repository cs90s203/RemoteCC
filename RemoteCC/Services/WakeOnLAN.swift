import Foundation
import Network

/// Sends Wake-on-LAN "magic packets" over UDP broadcast.
///
/// A magic packet is 6 bytes of 0xFF followed by the target MAC address repeated 16 times.
/// The target Mac must have "Wake for network access" enabled in
/// System Settings > Battery/Energy Saver, and must be connected to power
/// (Apple Silicon Macs generally do not respond to WoL on battery).
enum WakeOnLANError: LocalizedError {
    case invalidMACAddress
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMACAddress:
            return "MAC 位址格式錯誤，請使用 AA:BB:CC:DD:EE:FF 格式"
        case .sendFailed(let message):
            return "喚醒封包傳送失敗：\(message)"
        }
    }
}

enum WakeOnLAN {
    /// Broadcasts a magic packet for the given MAC address on the local subnet.
    /// - Parameters:
    ///   - macAddress: e.g. "AA:BB:CC:DD:EE:FF" (colon, dash, or no separator accepted).
    ///   - broadcastAddress: usually "255.255.255.255" works on the local subnet.
    ///   - port: WoL conventionally uses UDP port 9 (discard) or 7 (echo). 9 is most common.
    static func send(
        toMACAddress macAddress: String,
        broadcastAddress: String = "255.255.255.255",
        port: UInt16 = 9
    ) async throws {
        let payload = try magicPacket(for: macAddress)

        let connection = NWConnection(
            host: NWEndpoint.Host(broadcastAddress),
            port: NWEndpoint.Port(rawValue: port)!,
            using: {
                let params = NWParameters.udp
                params.allowLocalEndpointReuse = true
                return params
            }()
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            continuation.resume(throwing: WakeOnLANError.sendFailed(error.localizedDescription))
                        } else {
                            continuation.resume()
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    continuation.resume(throwing: WakeOnLANError.sendFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: .main)
        }
    }

    static func magicPacket(for macAddress: String) throws -> Data {
        let bytes = macAddress
            .split(whereSeparator: { $0 == ":" || $0 == "-" })
            .compactMap { UInt8($0, radix: 16) }

        guard bytes.count == 6 else {
            throw WakeOnLANError.invalidMACAddress
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: bytes)
        }
        return packet
    }
}
