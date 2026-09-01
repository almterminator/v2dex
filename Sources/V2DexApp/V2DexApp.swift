import SwiftUI

@main
struct V2DexApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .background(WindowButtonHider())
                .frame(minWidth: 460, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 900)
    }
}

private struct WindowButtonHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}
