import SwiftUI
import V2DexCore

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var importText = ""
    @State private var showingImportPopup = false
    @State private var showingProxyPopup = false
    @State private var savedConfigsCollapsed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            backgroundGlow

            appShell
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

            controlDock
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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

    private var backgroundGlow: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.background,
                    Theme.navy.opacity(0.46),
                    Theme.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [.clear, Theme.purple.opacity(0.20), Theme.cyan.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear], center: .bottomTrailing, startRadius: 120, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    private var appShell: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar
                .padding(.horizontal, 28)
                .padding(.top, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    savedConfigsPanel
                    subscriptionsSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 144)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Theme.shellGradient)
            }
        )
        .shadow(color: Theme.purple.opacity(0.18), radius: 26, x: 0, y: 0)
        .shadow(color: .black.opacity(0.40), radius: 30, x: 0, y: 20)
    }

    private var trafficLights: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(red: 1.00, green: 0.34, blue: 0.30))
            Circle().fill(Color(red: 1.00, green: 0.72, blue: 0.25))
            Circle().fill(Color(red: 0.43, green: 0.82, blue: 0.34))
        }
        .frame(width: 94, height: 16)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.activeProfile?.title ?? "No config selected")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.44)
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 4)

                Text(store.statusLine)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                headerIconButton(icon: "globe", iconSize: 18, help: "Connection") {
                    showingProxyPopup = true
                }
                headerIconButton(icon: "plus", iconSize: 22, help: "Import config") {
                    showingImportPopup = true
                }
            }
            .padding(.top, 1)
        }
    }

    private var savedConfigsPanel: some View {
        let savedProfiles = store.standaloneProfiles
        return VStack(alignment: .leading, spacing: 14) {
            headerCard(
                title: "Saved Configs",
                subtitle: nil,
                count: savedProfiles.count,
                collapsed: savedConfigsCollapsed,
                primaryIcon: "speedometer",
                secondaryIcon: nil,
                primaryLoading: store.pingingAll,
                secondaryLoading: false,
                onToggle: {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        savedConfigsCollapsed.toggle()
                    }
                },
                onPrimary: {
                    store.pingAllProfiles()
                },
                onSecondary: nil
            )

            if !savedConfigsCollapsed {
                if savedProfiles.isEmpty {
                    emptyProfiles
                } else {
                    VStack(spacing: 10) {
                        ForEach(savedProfiles) { profile in
                            profileRow(profile, allowsEditing: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.subscriptions) { subscription in
                subscriptionCard(subscription)
            }
        }
    }

    private var emptyProfiles: some View {
        liquidCard(height: 78) {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Theme.currentAccent(store))
                Text("No imported config yet.")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func subscriptionCard(_ subscription: SubscriptionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerCard(
                title: subscription.title,
                subtitle: "\(subscription.profileIDs.count) configs",
                count: nil,
                collapsed: store.collapsedSubscriptionIDs.contains(subscription.id),
                primaryIcon: "speedometer",
                secondaryIcon: "arrow.clockwise",
                primaryLoading: store.pingingSubscriptionIDs.contains(subscription.id),
                secondaryLoading: store.updatingSubscriptionIDs.contains(subscription.id),
                onToggle: {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        store.toggleSubscriptionCollapsed(subscription)
                    }
                },
                onPrimary: {
                    store.pingSubscription(subscription)
                },
                onSecondary: {
                    store.updateSubscription(subscription)
                }
            )
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
                VStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        profileRow(profile, allowsEditing: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func headerCard(
        title: String,
        subtitle: String?,
        count: Int?,
        collapsed: Bool,
        primaryIcon: String,
        secondaryIcon: String?,
        primaryLoading: Bool,
        secondaryLoading: Bool,
        onToggle: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)?
    ) -> some View {
        liquidCard(height: 74) {
            HStack(spacing: 14) {
                Button(action: onToggle) {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 34)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(.system(size: subtitle == nil ? 20 : 19, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)

                        if let count {
                            Text("\(count)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.90))
                                .frame(minWidth: 28, minHeight: 28)
                                .background(
                                    Circle()
                                        .fill(Theme.purple.opacity(0.34))
                                )
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    orbButton(icon: primaryIcon, size: 36, iconSize: 14, loading: primaryLoading, help: "Ping") {
                        onPrimary()
                    }

                    if let secondaryIcon, let onSecondary {
                        orbButton(icon: secondaryIcon, size: 36, iconSize: 16, loading: secondaryLoading, help: "Update") {
                            onSecondary()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func profileRow(_ profile: ProfileSummary, allowsEditing: Bool) -> some View {
        Button {
            store.selectProfile(profile)
        } label: {
            liquidCard(height: 58, selected: profile.id == store.activeProfile?.id) {
                HStack(spacing: 10) {
                    profileFlag(for: profile)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.title)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Text(profile.nodes.first.map { "\($0.server):\($0.port)" } ?? profile.source)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.50))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 10)

                    pingBadge(for: profile)
                }
                .padding(.horizontal, 14)
            }
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

    @ViewBuilder
    private func profileFlag(for profile: ProfileSummary) -> some View {
        if let countryCode = store.profileCountryCodes[profile.id] {
            Text(flagEmoji(countryCode))
                .font(.system(size: 28, weight: .black))
                .frame(width: 36, height: 38)
                .accessibilityLabel(Text(countryCode))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accentGradient(store))
                .symbolVariant(.none)
                .frame(width: 36, height: 38)
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
                Text("\(ms)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(pingColor(ms))
                Text("ms")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .baselineOffset(-5)
            case .timeout:
                Text("TIMEOUT")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.red)
            case .idle:
                Text("--")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(width: 74, alignment: .trailing)
    }

    private var controlDock: some View {
        ZStack(alignment: .center) {
            dockTray

            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Theme.dockButtonWell))
                .shadow(color: Theme.currentAccent(store).opacity(0.34), radius: 24, x: 0, y: 0)
                .shadow(color: .black.opacity(0.42), radius: 16, x: 0, y: 12)
                .frame(width: 100, height: 100)
                .offset(y: -18)

            HStack(alignment: .center) {
                routerOrFlagDockControl
                Spacer()
                pingControl
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            powerControl
                .offset(y: -18)
        }
        .frame(height: 110)
    }

    private var dockTray: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Theme.dockGlass))
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)
                    .blur(radius: 1)
                    .padding(.horizontal, 22)
                    .padding(.top, 5)
            }
            .shadow(color: Theme.currentAccent(store).opacity(0.30), radius: 20, x: 0, y: 0)
            .shadow(color: .black.opacity(0.46), radius: 20, x: 0, y: 14)
            .frame(height: 72)
            .padding(.top, 18)
    }

    private var routerOrFlagDockControl: some View {
        Group {
            if let exitLabel = dockExitLabel {
                HStack(spacing: 10) {
                    Text(flagEmoji(store.tunnel.countryCode))
                        .font(.system(size: 28, weight: .black))
                        .frame(width: 38, height: 44)
                    Text(exitLabel)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(width: 120, alignment: .leading)
            } else {
                routerSocksDockControl
            }
        }
    }

    private var dockExitLabel: String? {
        guard store.tunnel.connected else { return nil }
        if let countryName = store.tunnel.countryName, !countryName.isEmpty {
            return countryName
        }
        if let countryCode = store.tunnel.countryCode, !countryCode.isEmpty {
            return countryCode
        }
        return nil
    }

    private var routerSocksDockControl: some View {
        Button {
            store.setRouterSocksModeEnabled(!store.routerSocksModeEnabled)
        } label: {
            ZStack(alignment: store.routerSocksModeEnabled ? .trailing : .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.54),
                                Color.white.opacity(store.routerSocksModeEnabled ? 0.18 : 0.07)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: store.routerSocksModeEnabled ? Theme.currentAccent(store).opacity(0.42) : .black.opacity(0.24), radius: 14, x: 0, y: 0)

                Circle()
                    .fill(store.routerSocksModeEnabled ? AnyShapeStyle(Theme.accentGradient(store)) : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.92), Theme.panel.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: Theme.purple.opacity(0.58), radius: 18, x: 0, y: 0)
                    .padding(4)
            }
            .frame(width: 66, height: 34)
        }
        .buttonStyle(.plain)
        .help("Router SOCKS")
    }

    private var powerControl: some View {
        Button {
            store.toggleConnection()
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.powerGradient(store))
                    .shadow(color: Theme.currentAccent(store).opacity(0.64), radius: 20, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.46), radius: 14, x: 0, y: 9)

                if store.tunnel.connecting {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 82, height: 82)
        }
        .buttonStyle(.plain)
        .help(store.tunnel.connected ? "Disconnect" : "Connect")
    }

    private var pingControl: some View {
        Button {
            store.runLatencyTest()
        } label: {
            HStack(spacing: 8) {
                if store.pinging {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.currentAccent(store))
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Theme.currentAccent(store))
                }
                Text(store.lastPingMs.map { "\($0)" } ?? "--")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(store.lastPingMs.map(pingColor) ?? Theme.currentAccent(store))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("ms")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
                    .baselineOffset(-5)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 126, alignment: .trailing)
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
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
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
                Text("Connection")
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

            Divider()
                .overlay(Color.white.opacity(0.14))

            Toggle(isOn: routerSocksModeBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Router SOCKS")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Auto gateway · SOCKS 43080")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.currentAccent(store))
        }
        .padding(18)
        .frame(width: 300)
        .background(Theme.panel)
    }

    private var routerSocksModeBinding: Binding<Bool> {
        Binding(
            get: { store.routerSocksModeEnabled },
            set: { store.setRouterSocksModeEnabled($0) }
        )
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
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func orbButton(icon: String, size: CGFloat, iconSize: CGFloat, loading: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Theme.violet.opacity(0.24), Theme.panel.opacity(0.76)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: size * 0.42, height: size * 0.42)
                            .blur(radius: 1.8)
                            .offset(x: size * 0.12, y: size * 0.10)
                    }
                    .shadow(color: Theme.currentAccent(store).opacity(0.28), radius: 12, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 6)

                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func headerIconButton(icon: String, iconSize: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .shadow(color: Theme.currentAccent(store).opacity(0.46), radius: 8, x: 0, y: 0)
                .shadow(color: .black.opacity(0.26), radius: 5, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func liquidCard<Content: View>(height: CGFloat, selected: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(selected ? 0.18 : 0.10),
                            Theme.shellTop.opacity(0.54),
                            Theme.panel.opacity(0.72),
                            Theme.purple.opacity(selected ? 0.22 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.white.opacity(0.09), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 118, height: height * 0.62)
                        .blur(radius: 1.2)
                        .opacity(0.48)
                }
                .overlay(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Theme.currentAccent(store).opacity(selected ? 0.20 : 0.10), .clear],
                                center: .bottomTrailing,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                        .allowsHitTesting(false)
                }
                .shadow(color: Theme.currentAccent(store).opacity(selected ? 0.26 : 0.10), radius: selected ? 12 : 7, x: 0, y: 0)
                .shadow(color: .black.opacity(0.26), radius: 11, x: 0, y: 7)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
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
    static let background = Color(red: 0.012, green: 0.014, blue: 0.030)
    static let panel = Color(red: 0.034, green: 0.038, blue: 0.082)
    static let shellTop = Color(red: 0.046, green: 0.052, blue: 0.118)
    static let shellMid = Color(red: 0.024, green: 0.030, blue: 0.068)
    static let navy = Color(red: 0.085, green: 0.105, blue: 0.260)
    static let purple = Color(red: 0.37, green: 0.20, blue: 0.84)
    static let violet = Color(red: 0.60, green: 0.52, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.24)
    static let cyan = Color(red: 0.44, green: 0.84, blue: 1.00)
    static let green = Color(red: 0.39, green: 0.96, blue: 0.66)
    static let red = Color(red: 1.00, green: 0.34, blue: 0.42)
    static let shellGradient = LinearGradient(
        colors: [
            shellTop.opacity(0.82),
            shellMid.opacity(0.86),
            background.opacity(0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let shellStroke = LinearGradient(colors: [Color.white.opacity(0.40), violet.opacity(0.70), purple.opacity(0.36)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardStroke = LinearGradient(colors: [Color.white.opacity(0.42), violet.opacity(0.56), purple.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let headerGlass = LinearGradient(
        colors: [
            Color.white.opacity(0.13),
            shellTop.opacity(0.52),
            panel.opacity(0.74),
            purple.opacity(0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let dockGlass = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            shellTop.opacity(0.64),
            panel.opacity(0.94),
            purple.opacity(0.22)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let dockButtonWell = LinearGradient(
        colors: [
            Color.white.opacity(0.16),
            panel.opacity(0.78),
            background.opacity(0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    @MainActor
    static func currentAccent(_ store: AppStore) -> Color {
        if store.tunnel.connected {
            return green
        }
        if store.tunnel.connecting {
            return orange
        }
        return violet
    }

    @MainActor
    static func accentGradient(_ store: AppStore) -> LinearGradient {
        let colors: [Color]
        if store.tunnel.connected {
            colors = [cyan, green]
        } else if store.tunnel.connecting {
            colors = [orange, Color(red: 1.0, green: 0.34, blue: 0.16)]
        } else {
            colors = [violet, purple]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @MainActor
    static func powerGradient(_ store: AppStore) -> LinearGradient {
        let colors: [Color]
        if store.tunnel.connected {
            colors = [Color.white.opacity(0.28), green.opacity(0.84), cyan.opacity(0.55), panel]
        } else if store.tunnel.connecting {
            colors = [Color.white.opacity(0.26), orange.opacity(0.84), panel]
        } else {
            colors = [Color.white.opacity(0.30), violet.opacity(0.72), purple.opacity(0.54), panel]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
