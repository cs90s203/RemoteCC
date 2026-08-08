import SwiftUI

struct AddEditMacView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MacStore

    /// nil means "adding a new Mac".
    var editingMac: SavedMac?

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var macAddress: String = ""
    @State private var vncPort: String = "5900"
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("顯示名稱") {
                    TextField("例如：家裡的 MacBook Air", text: $name)
                }

                Section("網路位址") {
                    TextField("IP 或主機名稱，例如 192.168.1.23", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("VNC 連接埠（預設 5900）", text: $vncPort)
                }

                Section {
                    TextField("MAC 位址，例如 AA:BB:CC:DD:EE:FF", text: $macAddress)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Wake-on-LAN")
                } footer: {
                    Text("在目標 Mac 上：系統設定 > 網路 > Wi-Fi/乙太網路 > 詳細資訊，可以找到 MAC 位址。並確認已開啟「網路存取時喚醒」且已插電。")
                }

                Section {
                    TextField("使用者名稱（可留空）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密碼", text: $password)
                } header: {
                    Text("螢幕共享登入")
                } footer: {
                    Text("在目標 Mac 上：系統設定 > 一般 > 共享 > 打開「螢幕共享」。密碼只會存在這台裝置的 Keychain，不會上傳。")
                }
            }
            .navigationTitle(editingMac == nil ? "新增 Mac" : "編輯 Mac")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(name.isEmpty || host.isEmpty || macAddress.isEmpty)
                }
            }
            .onAppear(perform: populateIfEditing)
        }
    }

    private func populateIfEditing() {
        guard let editingMac else { return }
        name = editingMac.name
        host = editingMac.host
        macAddress = editingMac.macAddress
        vncPort = String(editingMac.vncPort)
        username = editingMac.username
        password = store.password(for: editingMac)
    }

    private func save() {
        let mac = SavedMac(
            id: editingMac?.id ?? UUID(),
            name: name,
            host: host,
            macAddress: macAddress,
            vncPort: Int(vncPort) ?? 5900,
            username: username
        )

        if editingMac != nil {
            store.update(mac, password: password.isEmpty ? nil : password)
        } else {
            store.add(mac, password: password)
        }
        dismiss()
    }
}

#Preview {
    AddEditMacView(store: MacStore())
}
