import SwiftUI

/// Full connection flow for one Mac: send Wake-on-LAN, wait for it to boot/wake,
/// then open a VNC session and render the remote screen.
struct RemoteScreenView: View {
    let mac: SavedMac
    let store: MacStore

    @State private var manager = VNCConnectionManager()
    @State private var phase: Phase = .wakingUp
    @State private var wakeError: String?
    @State private var typedText: String = ""
    @State private var cursorTracker = RemoteCursorTracker()
    @State private var isExtendingDisplay = false
    @State private var extendDisplayError: String?
    @FocusState private var keyboardFocused: Bool

    enum Phase {
        case wakingUp
        case connectingVNC
        case connected
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .wakingUp:
                statusView(title: "正在喚醒「\(mac.name)」…", subtitle: "已送出 Wake-on-LAN 封包，等待電腦開機/喚醒")
            case .connectingVNC:
                statusView(title: "正在連線螢幕共享…", subtitle: mac.host)
            case .connected:
                screenView
            case .failed(let message):
                statusView(title: "連線失敗", subtitle: message, showRetry: true)
            }
        }
        .navigationTitle(mac.name)
        .task { await startConnectFlow() }
        .onDisappear { cursorTracker.stop() }
        // Invisible text field used purely to summon the system keyboard and
        // forward typed characters to the remote Mac.
        .overlay(alignment: .bottom) {
            if case .connected = phase {
                TextField("輸入文字傳送到遠端", text: $typedText)
                    .focused($keyboardFocused)
                    .onChange(of: typedText) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        manager.type(newValue)
                        typedText = ""
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .frame(maxWidth: 400)
            }
        }
        // Keyboard trigger lives outside the window content entirely, so it never
        // overlaps the remote screen image regardless of its aspect ratio.
        .ornament(visibility: isConnected ? .visible : .hidden, attachmentAnchor: .scene(.trailing)) {
            Button {
                keyboardFocused = true
            } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        // Extend Display is independent of the VNC flow above — it only needs SSH
        // credentials, and shouldn't be gated behind screen sharing succeeding.
        .ornament(visibility: hasSSHCredentials ? .visible : .hidden, attachmentAnchor: .scene(.leading)) {
            Button {
                Task { await triggerExtendDisplay() }
            } label: {
                if isExtendingDisplay {
                    ProgressView()
                } else {
                    Image(systemName: "rectangle.on.rectangle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExtendingDisplay)
            .padding()
        }
        .alert("延伸螢幕", isPresented: extendDisplayErrorBinding, presenting: extendDisplayError) { _ in
            Button("好") { extendDisplayError = nil }
        } message: { message in
            Text(message)
        }
    }

    private var extendDisplayErrorBinding: Binding<Bool> {
        Binding(get: { extendDisplayError != nil }, set: { if !$0 { extendDisplayError = nil } })
    }

    private func triggerExtendDisplay() async {
        isExtendingDisplay = true
        defer { isExtendingDisplay = false }

        do {
            try await MacDisplayExtender.extendDisplay(
                to: mac,
                sshUsername: mac.sshUsername,
                sshPassword: store.sshPassword(for: mac)
            )
        } catch {
            extendDisplayError = error.localizedDescription
        }
    }

    private var isConnected: Bool {
        if case .connected = phase { true } else { false }
    }

    private var hasSSHCredentials: Bool {
        !mac.sshUsername.isEmpty
    }

    private var screenView: some View {
        GeometryReader { geo in
            if let image = manager.screenImage {
                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let point = remotePoint(for: value.location, in: geo.size, image: image)
                                    manager.drag(atX: point.x, y: point.y, buttonDown: true)
                                }
                                .onEnded { value in
                                    let point = remotePoint(for: value.location, in: geo.size, image: image)
                                    manager.drag(atX: point.x, y: point.y, buttonDown: false)
                                }
                        )
                        .onTapGesture { location in
                            let point = remotePoint(for: location, in: geo.size, image: image)
                            manager.click(atX: point.x, y: point.y)
                        }

                    // Live cursor position comes from polling the Mac directly over SSH — VNC's
                    // cursor updates only ever carry shape, never position, and visionOS doesn't
                    // expose continuous gaze position to apps. This reflects the real pointer
                    // regardless of what's moving it (this app, or a physical mouse on the Mac).
                    //
                    // The Mac reports the cursor in logical points, not pixels — a scaled/non-
                    // native display resolution means points don't relate to the VNC image's
                    // actual pixel size by any fixed constant, so that ratio is measured here
                    // from the two known sizes rather than assumed.
                    if let logicalPosition = cursorTracker.logicalPosition,
                       let logicalScreenSize = cursorTracker.logicalScreenSize,
                       logicalScreenSize.width > 0, logicalScreenSize.height > 0 {
                        let pixelScale = CGSize(
                            width: CGFloat(image.width) / logicalScreenSize.width,
                            height: CGFloat(image.height) / logicalScreenSize.height
                        )
                        let remotePixelPosition = CGPoint(
                            x: logicalPosition.x * pixelScale.width,
                            y: logicalPosition.y * pixelScale.height
                        )
                        let cursorViewLocation = viewPoint(for: remotePixelPosition, in: geo.size, image: image)
                        let scale = min(geo.size.width / CGFloat(image.width), geo.size.height / CGFloat(image.height))

                        if let cursorImage = manager.cursorImage {
                            let displaySize = CGSize(
                                width: manager.cursorSize.width * scale,
                                height: manager.cursorSize.height * scale
                            )
                            let hotspotOffset = CGSize(
                                width: manager.cursorHotspot.x * scale,
                                height: manager.cursorHotspot.y * scale
                            )
                            Image(decorative: cursorImage, scale: 1)
                                .resizable()
                                .frame(width: displaySize.width, height: displaySize.height)
                                .position(
                                    x: cursorViewLocation.x - hotspotOffset.width + displaySize.width / 2,
                                    y: cursorViewLocation.y - hotspotOffset.height + displaySize.height / 2
                                )
                                .allowsHitTesting(false)
                        } else {
                            // Fallback marker until the server sends its first cursor shape.
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .background(Circle().fill(.white.opacity(0.25)))
                                .frame(width: 24, height: 24)
                                .position(cursorViewLocation)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                statusView(title: "已連線，等待畫面…", subtitle: "")
            }
        }
    }

    /// Maps a tap/drag location inside the fitted image view back to framebuffer pixel coordinates.
    private func remotePoint(for location: CGPoint, in viewSize: CGSize, image: CGImage) -> (x: UInt16, y: UInt16) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (viewSize.width - displayedSize.width) / 2, y: (viewSize.height - displayedSize.height) / 2)

        let relativeX = (location.x - origin.x) / scale
        let relativeY = (location.y - origin.y) / scale

        let clampedX = min(max(relativeX, 0), imageSize.width - 1)
        let clampedY = min(max(relativeY, 0), imageSize.height - 1)

        return (UInt16(clampedX), UInt16(clampedY))
    }

    /// Inverse of `remotePoint`: maps a framebuffer pixel coordinate back into the fitted
    /// image view's local coordinate space, for positioning overlays like the live cursor.
    private func viewPoint(for remotePoint: CGPoint, in viewSize: CGSize, image: CGImage) -> CGPoint {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (viewSize.width - displayedSize.width) / 2, y: (viewSize.height - displayedSize.height) / 2)

        return CGPoint(x: origin.x + remotePoint.x * scale, y: origin.y + remotePoint.y * scale)
    }

    private func statusView(title: String, subtitle: String, showRetry: Bool = false) -> some View {
        VStack(spacing: 16) {
            if !showRetry {
                ProgressView()
            }
            Text(title)
                .font(.title3)
                .foregroundStyle(.white)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if showRetry {
                Button("重試") {
                    Task { await startConnectFlow() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func startConnectFlow() async {
        phase = .wakingUp

        do {
            try await WakeOnLAN.send(toMACAddress: mac.macAddress)
        } catch {
            // Non-fatal: the Mac might already be awake. Log and continue.
            wakeError = error.localizedDescription
        }

        // Give the Mac a few seconds to wake up / boot before we try VNC.
        try? await Task.sleep(for: .seconds(4))

        phase = .connectingVNC
        manager.connect(to: mac, password: store.password(for: mac))

        // Poll connection status since VNCConnectionDelegate updates manager.status asynchronously.
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(1))
            switch manager.status {
            case .connected:
                phase = .connected
                if hasSSHCredentials {
                    cursorTracker.start(
                        mac: mac,
                        sshUsername: mac.sshUsername,
                        sshPassword: store.sshPassword(for: mac)
                    )
                }
                return
            case .disconnected(let reason):
                phase = .failed(reason ?? "無法連線，請確認 Mac 已開機且螢幕共享已開啟")
                return
            default:
                continue
            }
        }
        phase = .failed("連線逾時，請確認 Mac 已喚醒並在同一個 Wi-Fi")
    }
}
