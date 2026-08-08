import SwiftUI

struct MacListView: View {
    @Bindable var store: MacStore

    @State private var showingAddSheet = false
    @State private var editingMac: SavedMac?

    var body: some View {
        NavigationStack {
            Group {
                if store.macs.isEmpty {
                    ContentUnavailableView(
                        "還沒有已儲存的 Mac",
                        systemImage: "laptopcomputer",
                        description: Text("點右上角「+」新增一台要遠端連線的 Mac")
                    )
                } else {
                    List {
                        ForEach(store.macs) { mac in
                            NavigationLink(value: mac) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mac.name)
                                        .font(.headline)
                                    Text("\(mac.host) · \(mac.macAddress)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("刪除", role: .destructive) {
                                    store.delete(mac)
                                }
                                Button("編輯") {
                                    editingMac = mac
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("RemoteCC")
            .navigationDestination(for: SavedMac.self) { mac in
                RemoteScreenView(mac: mac, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("新增 Mac", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditMacView(store: store)
            }
            .sheet(item: $editingMac) { mac in
                AddEditMacView(store: store, editingMac: mac)
            }
        }
    }
}

#Preview {
    MacListView(store: MacStore())
}
