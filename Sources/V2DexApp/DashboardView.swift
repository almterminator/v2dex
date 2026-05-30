import SwiftUI
import V2DexCore

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var importText = ""

    var body: some View {
        ZStack {
            background

            HStack(spacing: 24) {
                sidebar
                mainContent
            }
            .padding(28)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.08, blue: 0.12),
                Color(red: 0.07, green: 0.18, blue: 0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 10)
                .offset(x: 120, y: -120)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.green.opacity(0.14))
                .frame(width: 360, height: 360)
                .blur(radius: 12)
                .offset(x: -120, y: 100)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("V2DEX")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(2)

            Text("High-performance macOS proxy client")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 10) {
                ForEach(SidebarSection.allCases) { item in
                    Button {
                        store.selection = item
                    } label: {
                        HStack {
                            Text(item.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(store.selection == item ? Color.white.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(store.selection == item ? 1 : 0.72))
                }
            }

            Spacer()

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Runtime")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.mint)
                    Text(store.statusLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
        .frame(width: 250)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                profileRow
                toolsRow
                routingRow
                configPreview
            }
            .padding(.bottom, 20)
        }
    }

    private var hero: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tunnel State")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.48, green: 0.93, blue: 0.83))
                    .tracking(1.2)

                Text(store.tunnel.connected ? "Connected" : (store.tunnel.connecting ? "Connecting" : "Disconnected"))
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(store.activeNode?.name ?? "No node selected") · \(store.tunnel.mode == .full ? "System proxy" : "App filter preview")")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 14) {
                    statPill(title: "Protocol", value: (store.activeNode?.protocolType.uppercased() ?? "N/A"))
                    statPill(title: "Traffic Left", value: trafficRemaining)
                    statPill(title: "DNS Guard", value: store.tunnel.dnsLeakProtection ? "Enabled" : "Off")
                }

                HStack(spacing: 12) {
                    Button(store.tunnel.connected ? "Disconnect" : "Connect") {
                        store.toggleConnection()
                    }
                    .buttonStyle(PrimaryButtonStyle(accent: store.tunnel.connected ? .red : .mint))

                    Button(store.tunnel.mode == .full ? "Switch to Per-App" : "Switch to Full Tunnel") {
                        store.setMode(store.tunnel.mode == .full ? .perApp : .full)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Discover Apps") {
                        store.discoverApplications()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Latency Test") {
                        store.runLatencyTest()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var profileRow: some View {
        HStack(alignment: .top, spacing: 18) {
            card {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Profiles")
                    ForEach(store.profiles) { profile in
                        Button {
                            store.selectProfile(profile)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.title)
                                        .font(.system(size: 15, weight: .bold))
                                    Text("\(profile.source) · \(profile.nodes.count) nodes")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                                Spacer()
                                if profile.id == store.activeProfile?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.mint)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(profile.id == store.activeProfile?.id ? 0.12 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Nodes")
                    ForEach(store.activeProfile?.nodes ?? []) { node in
                        Button {
                            store.selectNode(node)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(node.name)
                                        .font(.system(size: 15, weight: .bold))
                                    Text("\(node.protocolType.uppercased()) · \(node.server):\(node.port)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                                Spacer()
                                if node.id == store.activeNode?.id {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(.cyan)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(node.id == store.activeNode?.id ? 0.12 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var toolsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            card {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Import")
                    TextField("Subscription link, direct URI, or manual entry", text: $importText)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.black.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        Button("Import Clipboard") {
                            store.importFromClipboard()
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button("Import Text") {
                            store.importSubscriptionLink(importText)
                        }
                        .buttonStyle(PrimaryButtonStyle(accent: .blue))
                    }

                    Text("Supports subscription links, direct URIs, and clipboard import. Real protocol parsing is stubbed through the current importer layer.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            card {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("System Mode")
                    Picker("Mode", selection: Binding(
                        get: { store.tunnel.mode },
                        set: { store.setMode($0) }
                    )) {
                        Text("Full Tunnel").tag(TunnelMode.full)
                        Text("Per-App").tag(TunnelMode.perApp)
                    }
                    .pickerStyle(.segmented)

                    Text("Local-only mode runs `sing-box` as a user-space proxy and toggles the macOS system proxy. Packet Tunnel wiring remains scaffolded for a future signed Network Extension build.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
    }

    private var routingRow: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionHeader("App Routing Preview")
                    Spacer()
                    TextField("Search apps", text: $store.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(store.filteredRules) { rule in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.name)
                                        .font(.system(size: 15, weight: .bold))
                                    Text(rule.processName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { rule.enabled },
                                    set: { _ in store.toggleRule(rule) }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }

                            Text(rule.bundleId)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var configPreview: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Generated sing-box Config")
                ScrollView(.horizontal) {
                    Text(store.configPreview)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var trafficRemaining: String {
        guard let profile = store.activeProfile else { return "N/A" }
        let remaining = max(profile.trafficTotalGB - profile.trafficUsedGB, 0)
        return String(format: "%.0f GB", remaining)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 12)
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.64))
            .tracking(1.1)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(accent.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
