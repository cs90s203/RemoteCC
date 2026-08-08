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
    }

    private var screenView: some View {
        GeometryReader { geo in
            if let image = manager.screenImage {
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
                    .overlay(alignment: .topTrailing) {
                        Button {
                            keyboardFocused = true
                        } label: {
                            Image(systemName: "keyboard")
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
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
