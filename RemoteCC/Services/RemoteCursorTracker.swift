import Foundation
import Citadel
import CoreGraphics
import Observation

/// Polls the Mac's actual system cursor position over SSH and republishes it, so the app can
/// show where the pointer really is — including when it's being moved by a physical mouse
/// directly on the Mac, not just when driven through this app's own tap/drag gestures.
///
/// VNC's cursor pseudo-encoding only carries shape, never position, and the Mac's screen
/// sharing server doesn't bake the cursor into ordinary framebuffer updates either — so this
/// is a second, independent SSH-based channel purely for "where is the pointer right now."
///
/// The Mac reports the cursor in logical points (`CGEvent`'s native space) along with the
/// screen's logical point size — not a pixel position — because the VNC framebuffer's pixel
/// dimensions don't reliably relate to logical points by a clean factor (e.g. a scaled/
/// non-native display resolution). The caller, which already knows the VNC image's actual
/// pixel size, computes the real scale factor itself instead of trusting a guessed constant.
@Observable
final class RemoteCursorTracker {
    private(set) var logicalPosition: CGPoint?
    private(set) var logicalScreenSize: CGSize?

    private var pollTask: Task<Void, Never>?

    private static let helperPath = "/tmp/.remotecc_cursorpos_v2"
    private static let helperSource = """
    import AppKit
    import CoreGraphics
    let p = CGEvent(source: nil)?.location ?? .zero
    let frame = NSScreen.main?.frame ?? .zero
    print("\\(Int(p.x)),\\(Int(p.y)),\\(Int(frame.width)),\\(Int(frame.height))")
    """

    func start(mac: SavedMac, sshUsername: String, sshPassword: String) {
        stop()

        pollTask = Task { [weak self] in
            guard let self else { return }

            let settings = SSHClientSettings(
                host: mac.host,
                authenticationMethod: { .passwordBased(username: sshUsername, password: sshPassword) },
                hostKeyValidator: .acceptAnything()
            )

            guard let client = try? await SSHClient.connect(to: settings) else { return }
            defer { Task { try? await client.close() } }

            guard (try? await self.bootstrapHelper(client: client)) != nil else { return }

            while !Task.isCancelled {
                if let reading = try? await self.pollOnce(client: client) {
                    await MainActor.run {
                        self.logicalPosition = reading.position
                        self.logicalScreenSize = reading.screenSize
                    }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        logicalPosition = nil
        logicalScreenSize = nil
    }

    private func bootstrapHelper(client: SSHClient) async throws {
        let command = """
        cat > \(Self.helperPath).swift <<'SWIFT_EOF'
        \(Self.helperSource)
        SWIFT_EOF
        test -x \(Self.helperPath) || swiftc -O \(Self.helperPath).swift -o \(Self.helperPath)
        """
        let stream = try await client.executeCommandStream(command)
        for try await _ in stream {
            // Drain to completion so we know the helper is compiled before polling starts.
        }
    }

    private func pollOnce(client: SSHClient) async throws -> (position: CGPoint, screenSize: CGSize)? {
        let stream = try await client.executeCommandStream(Self.helperPath)
        var output = ""
        for try await chunk in stream {
            if case .stdout(let buffer) = chunk {
                output += String(buffer: buffer)
            }
        }

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count == 4,
              let x = Double(parts[0]), let y = Double(parts[1]),
              let screenWidth = Double(parts[2]), let screenHeight = Double(parts[3]),
              screenWidth > 0, screenHeight > 0
        else {
            return nil
        }
        return (CGPoint(x: x, y: y), CGSize(width: screenWidth, height: screenHeight))
    }
}
