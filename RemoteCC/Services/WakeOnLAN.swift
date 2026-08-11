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
            let resumeLock = NSLock()
            var hasResumed = false
            func resumeOnce(_ result: Result<Void, Error>) {
                resumeLock.lock()
                let alreadyResumed = hasResumed
                hasResumed = true
                resumeLock.unlock()
                guard !alreadyResumed else { return }
                connection.cancel()
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            resumeOnce(.failure(WakeOnLANError.sendFailed(error.localizedDescription)))
                        } else {
                            resumeOnce(.success(()))
                        }
                    })
                case .failed(let error):
                    resumeOnce(.failure(WakeOnLANError.sendFailed(error.localizedDescription)))
                default:
                    // .waiting can persist indefinitely on some network paths (e.g. broadcast
                    // restricted by the active interface), so this never blocks forever.
                    break
                }
            }
            connection.start(queue: .main)

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                resumeOnce(.failure(WakeOnLANError.sendFailed("連線逾時")))
            }
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
