import SwiftUI

@main
struct V2DexApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .frame(minWidth: 1220, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
    }
}
