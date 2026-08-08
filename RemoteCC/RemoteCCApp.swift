import SwiftUI

@main
struct RemoteCCApp: App {
    @State private var store = MacStore()

    var body: some Scene {
        WindowGroup {
            MacListView(store: store)
        }
        .windowStyle(.plain)
        .defaultSize(width: 900, height: 700)
    }
}
