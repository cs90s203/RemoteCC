import Foundation
import CoreGraphics
import Observation
import RoyalVNCKit

/// Wraps a RoyalVNCKit `VNCConnection` and exposes what SwiftUI needs:
/// connection status, the latest remote-screen image, and simple input helpers.
///
/// NOTE FOR FIRST BUILD: RoyalVNCKit's public API can shift slightly between
/// versions. If Xcode reports an error on a specific line below, place the
/// cursor on the symbol and use Xcode's autocomplete / "Jump to Definition"
/// (⌘-click) on `VNCConnection` to see the exact current method/property
/// names, then adjust that one line — the rest of the app does not need to
/// change. This is the single file most likely to need a small touch-up.
@Observable
final class VNCConnectionManager: NSObject {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(reason: String?)
    }

    private(set) var status: Status = .idle
    private(set) var screenImage: CGImage?
    private(set) var screenSize: CGSize = .zero
    private(set) var cursorImage: CGImage?
    private(set) var cursorSize: CGSize = .zero
    private(set) var cursorHotspot: CGPoint = .zero

    private var connection: VNCConnection?
    private var mac: SavedMac?
    private var password: String = ""

    func connect(to mac: SavedMac, password: String) {
        self.mac = mac
        self.password = password
        status = .connecting

        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: mac.host,
            port: UInt16(mac.vncPort),
            isShared: true,
            isScalingEnabled: true,
            useDisplayLink: true,
            inputMode: .forwardKeyboardShortcutsEvenIfInUseLocally,
            isClipboardRedirectionEnabled: true,
            colorDepth: .depth24Bit,
            frameEncodings: .default
        )

        let newConnection = VNCConnection(settings: settings)
        newConnection.delegate = self
        connection = newConnection
        newConnection.connect()
    }

    func disconnect() {
        connection?.disconnect()
        connection = nil
        status = .idle
        screenImage = nil
    }

    // MARK: - Input

    /// Sends a left click at a point in framebuffer coordinates.
    func click(atX x: UInt16, y: UInt16) {
        connection?.mouseButtonDown(.left, x: x, y: y)
        connection?.mouseButtonUp(.left, x: x, y: y)
    }

    /// Moves the pointer without changing button state, for continuous gaze tracking.
    func move(atX x: UInt16, y: UInt16) {
        connection?.mouseMove(x: x, y: y)
    }

    /// Moves the pointer (and optionally holds the left button, for dragging) to a point.
    func drag(atX x: UInt16, y: UInt16, buttonDown: Bool) {
        if buttonDown {
            connection?.mouseButtonDown(.left, x: x, y: y)
        } else {
            connection?.mouseButtonUp(.left, x: x, y: y)
        }
    }

    /// Types a string of characters using the remote keyboard.
    func type(_ text: String) {
        for keyCode in VNCKeyCode.keyCodesFrom(characters: text) {
            connection?.keyDown(keyCode)
            connection?.keyUp(keyCode)
        }
    }
}

// MARK: - VNCConnectionDelegate

extension VNCConnectionManager: VNCConnectionDelegate {
    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        Task { @MainActor in
            switch connectionState.status {
            case .connecting:
                status = .connecting
            case .connected:
                status = .connected
            case .disconnecting:
                break
            case .disconnected:
                status = .disconnected(reason: connectionState.error?.localizedDescription)
            @unknown default:
                break
            }
        }
    }

    func connection(_ connection: VNCConnection, credentialFor authenticationType: VNCAuthenticationType, completion: @escaping (VNCCredential?) -> Void) {
        if !mac!.username.isEmpty {
            completion(VNCUsernamePasswordCredential(username: mac!.username, password: password))
        } else {
            completion(VNCPasswordCredential(password: password))
        }
    }

    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor in
            screenSize = CGSize(width: Int(framebuffer.size.width), height: Int(framebuffer.size.height))
            screenImage = framebuffer.cgImage
        }
    }

    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor in
            screenSize = CGSize(width: Int(framebuffer.size.width), height: Int(framebuffer.size.height))
            screenImage = framebuffer.cgImage
        }
    }

    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer, x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        Task { @MainActor in
            screenImage = framebuffer.cgImage
        }
    }

    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        Task { @MainActor in
            if cursor.isEmpty {
                cursorImage = nil
            } else {
                cursorImage = cursor.cgImage
                cursorSize = cursor.cgSize
                cursorHotspot = cursor.cgHotspot
            }
        }
    }
}
