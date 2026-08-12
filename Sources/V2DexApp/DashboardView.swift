import SwiftUI
import V2DexCore

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var importText = ""
    @State private var showingImportPopup = false
    @State private var showingProxyPopup = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        profilesSection
                        subscriptionsSection
                    }
                    .padding(.bottom, 160)
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 28)

            controlDock
        }
        .sheet(isPresented: $showingImportPopup) {
            importSheet
                .frame(width: 440)
                .presentationBackground(Theme.panel)
        }
        .popover(isPresented: $showingProxyPopup, arrowEdge: .top) {
            proxyPopover
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.activeProfile?.title ?? "No config selected")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(store.statusLine)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showingProxyPopup = true
            } label: {
                Image(systemName: "network")
                    .font(.system(size: 18, weight: .black))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(IconButtonStyle(accent: Theme.currentAccent(store)))
            .help("Connection")

            Button {
                showingImportPopup = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .black))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(IconButtonStyle(accent: Theme.currentAccent(store)))
            .help("Import config")
        }
    }

    private var profilesSection: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(title: "Saved Configs", count: store.profiles.count, showsPingAll: true)

                if store.profiles.isEmpty {
                    emptyProfiles
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.profiles) { profile in
                            profileRow(profile, allowsEditing: true)
                        }
                    }
                }
            }
        }
    }

    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(store.subscriptions) { subscription in
                subscriptionCard(subscription)
            }
        }
    }

    private var emptyProfiles: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.currentAccent(store))
            Text("No imported config yet.")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func profileRow(_ profile: ProfileSummary, allowsEditing: Bool) -> some View {
        Button {
            store.selectProfile(profile)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(profile.id == store.activeProfile?.id ? Theme.currentAccent(store).opacity(0.22) : Color.white.opacity(0.07))
                    Image(systemName: profile.id == store.activeProfile?.id ? "checkmark" : "server.rack")
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(profile.id == store.activeProfile?.id ? Theme.currentAccent(store) : .white.opacity(0.62))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(profile.nodes.first.map { "\($0.server):\($0.port)" } ?? profile.source)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                pingBadge(for: profile)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(profile.id == store.activeProfile?.id ? Theme.currentAccent(store).opacity(0.12) : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(profile.id == store.activeProfile?.id ? Theme.currentAccent(store).opacity(0.52) : Color.white.opacity(0.11), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if allowsEditing {
                Button {
                    store.renameProfile(profile)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.deleteProfile(profile)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func subscriptionCard(_ subscription: SubscriptionSummary) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button {
                        store.toggleSubscriptionCollapsed(subscription)
                    } label: {
                        Image(systemName: store.collapsedSubscriptionIDs.contains(subscription.id) ? "chevron.down" : "chevron.up")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help(store.collapsedSubscriptionIDs.contains(subscription.id) ? "Expand subscription" : "Collapse subscription")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.title)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(subscription.profileIDs.count) configs")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer()

                    subscriptionIconButton(
                        icon: "speedometer",
                        loading: store.pingingSubscriptionIDs.contains(subscription.id),
                        help: "Ping subscription"
                    ) {
                        store.pingSubscription(subscription)
                    }

                    subscriptionIconButton(
                        icon: "arrow.clockwise",
                        loading: store.pingingSubscriptionIDs.contains(subscription.id),
                        help: "Update subscription"
                    ) {
                        store.updateSubscription(subscription)
                    }
                }
                .contextMenu {
                    Button {
                        store.renameSubscription(subscription)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        store.deleteSubscription(subscription)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if !store.collapsedSubscriptionIDs.contains(subscription.id) {
                    let profiles = store.profiles.filter { subscription.profileIDs.contains($0.id) }
                    VStack(spacing: 12) {
                        ForEach(profiles) { profile in
                            profileRow(profile, allowsEditing: true)
                        }
                    }
                }
            }
        }
    }

    private func subscriptionIconButton(icon: String, loading: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .black))
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(IconButtonStyle(accent: Theme.currentAccent(store), compact: true))
        .help(help)
    }

    private func sectionHeader(title: String, count: Int? = nil, showsPingAll: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            if let count {
                Text("\(count)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            Spacer()
            if showsPingAll {
                Button {
                    store.pingAllProfiles()
                } label: {
                    ZStack {
                        if store.pingingAll {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "speedometer")
                                .font(.system(size: 16, weight: .black))
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(IconButtonStyle(accent: Theme.currentAccent(store), compact: true))
                .help("Ping all configs")
            }
        }
    }

    private func pingBadge(for profile: ProfileSummary) -> some View {
        let state = store.profilePingStates[profile.id] ?? .idle
        return HStack(spacing: 6) {
            switch state {
            case .pinging:
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.currentAccent(store))
            case let .latency(ms):
                Text("\(ms) ms")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(pingColor(ms))
            case .timeout:
                Text("TIMEOUT")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.red)
            case .idle:
                Text("--")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(minWidth: 84, alignment: .trailing)
    }

    private var controlDock: some View {
        ZStack {
            dockTray
            HStack {
                flagControl
                Spacer()
                pingControl
            }
            .padding(.horizontal, 42)
            powerControl
        }
        .frame(height: 150)
        .padding(.horizontal, 0)
        .padding(.bottom, 0)
    }

    private var dockTray: some View {
        RoundedRectangle(cornerRadius: 52, style: .continuous)
            .fill(Theme.panel.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 52, style: .continuous)
                    .stroke(Theme.currentAccent(store).opacity(0.86), lineWidth: 5)
            )
            .shadow(color: Theme.currentAccent(store).opacity(0.28), radius: 22, x: 0, y: 0)
            .frame(height: 94)
            .padding(.top, 42)
    }

    private var flagControl: some View {
        HStack(spacing: 14) {
            Text(store.tunnel.connected ? flagEmoji(store.tunnel.countryCode) : "◎")
                .font(.system(size: 42, weight: .black))
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.tunnel.connected ? (store.tunnel.countryName ?? store.tunnel.countryCode ?? "Connected") : "Ready")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(store.tunnel.exitIP ?? "Location pending")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 230, alignment: .leading)
    }

    private var powerControl: some View {
        Button {
            store.toggleConnection()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.currentAccent(store).opacity(0.96),
                                Theme.currentAccent(store).opacity(0.68)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Theme.currentAccent(store).opacity(0.55), radius: 26, x: 0, y: 0)

                if store.tunnel.connecting {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.black.opacity(0.78))
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(.black.opacity(0.82))
                }
            }
            .frame(width: 126, height: 126)
        }
        .buttonStyle(.plain)
        .help(store.tunnel.connected ? "Disconnect" : "Connect")
    }

    private var pingControl: some View {
        Button {
            store.runLatencyTest()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 35, weight: .black))
                    .foregroundStyle(Theme.currentAccent(store))
                Text(store.lastPingMs.map { "\($0)" } ?? "--")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(store.lastPingMs.map(pingColor) ?? Theme.currentAccent(store))
                Text("ms")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .baselineOffset(-8)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 210, alignment: .trailing)
        .help("Ping")
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Import Config")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            TextEditor(text: $importText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 190)
                .background(Color.black.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if importText.isEmpty {
                        Text("VLESS URI or subscription URL")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.34))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 12) {
                Button {
                    store.importFromClipboard()
                    showingImportPopup = false
                } label: {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Cancel") {
                    showingImportPopup = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    store.importSubscriptionLink(importText)
                    importText = ""
                    showingImportPopup = false
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PrimaryButtonStyle(accent: Theme.currentAccent(store)))
            }
        }
        .padding(24)
        .background(Theme.panel)
    }

    private var proxyPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Local Proxy")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showingProxyPopup = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            proxyChip(icon: "globe", text: "HTTP 127.0.0.1:2081")
            proxyChip(icon: "point.3.connected.trianglepath.dotted", text: "SOCKS 2082")
        }
        .padding(18)
        .frame(width: 280)
        .background(Theme.panel)
    }

    private func proxyChip(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.currentAccent(store))
                .font(.system(size: 15, weight: .black))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 12)
    }

    private func pingColor(_ ping: Int) -> Color {
        if ping < 750 {
            return Theme.green
        }
        if ping <= 850 {
            return Theme.orange
        }
        return Theme.red
    }

    private func flagEmoji(_ code: String?) -> String {
        guard let code = code?.uppercased(), code.count == 2 else {
            return "◎"
        }
        return code.unicodeScalars.compactMap { scalar -> String? in
            guard let value = UnicodeScalar(127397 + scalar.value) else { return nil }
            return String(value)
        }.joined()
    }
}

private enum Theme {
    static let background = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let panel = Color(red: 0.04, green: 0.06, blue: 0.08)
    static let navy = Color(red: 0.10, green: 0.16, blue: 0.36)
    static let purple = Color(red: 0.34, green: 0.19, blue: 0.62)
    static let orange = Color(red: 1.00, green: 0.55, blue: 0.20)
    static let cyan = Color(red: 0.35, green: 0.90, blue: 0.96)
    static let green = Color(red: 0.44, green: 0.94, blue: 0.60)
    static let red = Color(red: 1.00, green: 0.32, blue: 0.32)

    @MainActor
    static func currentAccent(_ store: AppStore) -> Color {
        if store.tunnel.connected {
            return green
        }
        if store.tunnel.connecting {
            return orange
        }
        return purple
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(accent.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IconButtonStyle: ButtonStyle {
    var accent: Color
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black.opacity(0.82))
            .background(
                Circle()
                    .fill(accent.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .shadow(color: accent.opacity(0.28), radius: compact ? 10 : 16, x: 0, y: 4)
    }
}
