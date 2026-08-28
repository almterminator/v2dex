import AppKit
import Combine
import Foundation
import V2DexCore

@MainActor
final class AppStore: ObservableObject {
    @Published var selection: SidebarSection = .overview
    @Published var tunnel = TunnelSnapshot()
    @Published var profiles: [ProfileSummary] = DemoData.profiles
    @Published var subscriptions: [SubscriptionSummary] = []
    @Published var appRules: [AppRuleViewModel] = DemoData.appRules
    @Published var searchText = ""
    @Published var statusLine = "Ready"
    @Published var configPreview = "{}"
    @Published var lastPingMs: Int?
    @Published var lastPingProfileID: String?
    @Published var pinging = false
    @Published var pingingAll = false
    @Published var pingingSubscriptionIDs: Set<String> = []
    @Published var updatingSubscriptionIDs: Set<String> = []
    @Published var collapsedSubscriptionIDs: Set<String> = []
    @Published var profilePingStates: [String: ProfilePingState] = [:]
    @Published var profileCountryCodes: [String: String] = [:]
    @Published var routerSocksModeEnabled = false
    private var routerSocksProxyActive = false

    nonisolated private static let routerSocksPort = 43_080
    nonisolated private static let pingBatchSize = 3
    nonisolated private static let proxyPingTimeout: TimeInterval = 2.5
    nonisolated private static let connectedProbeURLs = [
        "https://www.youtube.com/generate_204",
        "https://www.gstatic.com/generate_204",
        "https://cp.cloudflare.com/generate_204",
        "http://cp.cloudflare.com/generate_204"
    ]
    nonisolated private static let exitLookupURLs = [
        "https://ipinfo.io/json",
        "https://ipwho.is/",
        "https://ipapi.co/json/"
    ]

    private struct PersistedAppState: Codable {
        var profiles: [ProfileSummary]
        var subscriptions: [SubscriptionSummary]
        var appRules: [AppRuleViewModel]
        var activeProfileId: String?
        var activeNodeId: String?
        var mode: TunnelMode?
        var collapsedSubscriptionIDs: [String]?
        var profileCountryCodes: [String: String]?
        var routerSocksModeEnabled: Bool?
    }

    var activeProfile: ProfileSummary? {
        profiles.first { $0.id == tunnel.selectedProfileID } ?? profiles.first
    }

    var activeNode: ProxyNode? {
        guard let activeProfile else { return nil }
        return activeProfile.nodes.first { $0.id == tunnel.selectedNodeID } ?? activeProfile.nodes.first
    }

    var standaloneProfiles: [ProfileSummary] {
        let subscribedProfileIDs = Set(subscriptions.flatMap(\.profileIDs))
        return profiles.filter { !subscribedProfileIDs.contains($0.id) }
    }

    init() {
        loadPersistedState()
        tunnel.selectedProfileID = tunnel.selectedProfileID ?? profiles.first?.id
        tunnel.selectedNodeID = tunnel.selectedNodeID ?? profiles.first?.nodes.first?.id
        refreshConfigPreview()
        cleanupStaleProxyOnLaunch()
    }

    func toggleConnection() {
        if tunnel.connected || tunnel.connecting {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        if routerSocksModeEnabled {
            connectRouterSocksProxy()
            return
        }

        guard let node = activeNode else {
            tunnel.lastError = "No config selected"
            statusLine = "No config selected"
            return
        }

        tunnel.connecting = true
        tunnel.lastError = nil
        routerSocksProxyActive = false
        statusLine = "Starting local proxy..."

        Task {
            do {
                let configData = try XrayConfigBuilder.build(node: node)
                let snapshot = try SingboxRuntime.shared.startXray(
                    configData: configData,
                    mode: .full,
                    socksOnlySystemProxy: node.protocolType == "socks5"
                )

                await MainActor.run {
                    tunnel.connecting = snapshot.connecting
                    tunnel.connected = snapshot.connected
                    tunnel.lastConnectedAt = snapshot.lastConnectedAt ?? Date()
                    tunnel.lastError = nil
                    statusLine = "Connected locally via \(node.name). Checking exit location..."
                }

                await refreshExitLocation(afterConnectingTo: node)
                await runActivePing()
            } catch {
                await MainActor.run {
                    tunnel.connecting = false
                    tunnel.connected = false
                    tunnel.lastError = error.localizedDescription
                    statusLine = "Connect failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func cleanupStaleProxyOnLaunch() {
        Task {
            let snapshot = SingboxRuntime.shared.statusSnapshot()
            guard !snapshot.connected else { return }
            do {
                try SingboxRuntime.shared.stopIfNeeded()
            } catch {
                await MainActor.run {
                    tunnel.lastError = error.localizedDescription
                    statusLine = "Proxy cleanup warning: \(error.localizedDescription)"
                }
            }
        }
    }

    func disconnect() {
        if routerSocksProxyActive {
            disconnectRouterSocksProxy()
            return
        }

        tunnel.connecting = true
        statusLine = "Disconnecting..."

        Task {
            do {
                try SingboxRuntime.shared.stopIfNeeded()
                await MainActor.run {
                    tunnel.connected = false
                    tunnel.connecting = false
                    tunnel.lastError = nil
                    tunnel.exitIP = nil
                    tunnel.countryCode = nil
                    tunnel.countryName = nil
                    routerSocksProxyActive = false
                    statusLine = "Disconnected. Wi-Fi proxies are off."
                }
            } catch {
                await MainActor.run {
                    tunnel.connected = false
                    tunnel.connecting = false
                    tunnel.lastError = error.localizedDescription
                    tunnel.exitIP = nil
                    tunnel.countryCode = nil
                    tunnel.countryName = nil
                    routerSocksProxyActive = false
                    statusLine = "Disconnected with cleanup warning: \(error.localizedDescription)"
                }
            }
        }
    }

    func setRouterSocksModeEnabled(_ enabled: Bool) {
        routerSocksModeEnabled = enabled
        statusLine = enabled ? "Router SOCKS mode enabled" : "Router SOCKS mode disabled"
        persistState()
    }

    private func connectRouterSocksProxy() {
        tunnel.connecting = true
        tunnel.lastError = nil
        statusLine = "Detecting router gateway..."

        Task {
            do {
                let routerHost = try SingboxRuntime.shared.enableRouterSocksProxy(port: Self.routerSocksPort)
                await MainActor.run {
                    tunnel.connected = true
                    tunnel.connecting = false
                    tunnel.lastConnectedAt = Date()
                    tunnel.lastError = nil
                    tunnel.exitIP = nil
                    tunnel.countryCode = nil
                    tunnel.countryName = nil
                    routerSocksProxyActive = true
                    statusLine = "Wi-Fi SOCKS proxy: \(routerHost):\(Self.routerSocksPort)"
                }
            } catch {
                await MainActor.run {
                    tunnel.connected = false
                    tunnel.connecting = false
                    tunnel.lastError = error.localizedDescription
                    routerSocksProxyActive = false
                    statusLine = "Router SOCKS failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func disconnectRouterSocksProxy() {
        tunnel.connecting = true
        statusLine = "Turning off router SOCKS..."

        Task {
            do {
                try SingboxRuntime.shared.disableRouterSocksProxy()
                await MainActor.run {
                    tunnel.connected = false
                    tunnel.connecting = false
                    tunnel.lastError = nil
                    tunnel.exitIP = nil
                    tunnel.countryCode = nil
                    tunnel.countryName = nil
                    routerSocksProxyActive = false
                    statusLine = "Router SOCKS proxy is off."
                }
            } catch {
                await MainActor.run {
                    tunnel.connected = false
                    tunnel.connecting = false
                    tunnel.lastError = error.localizedDescription
                    tunnel.exitIP = nil
                    tunnel.countryCode = nil
                    tunnel.countryName = nil
                    routerSocksProxyActive = false
                    statusLine = "Router SOCKS cleanup warning: \(error.localizedDescription)"
                }
            }
        }
    }

    func setMode(_ mode: TunnelMode) {
        tunnel.mode = mode
        statusLine = mode == .full ? "System proxy enabled" : "App filter preview disabled on macOS without Network Extension"
        refreshConfigPreview()
        persistState()
    }

    func selectProfile(_ profile: ProfileSummary) {
        tunnel.selectedProfileID = profile.id
        tunnel.selectedNodeID = profile.nodes.first?.id
        statusLine = "Selected \(profile.title)"
        refreshConfigPreview()
        persistState()
    }

    func selectNode(_ node: ProxyNode) {
        tunnel.selectedNodeID = node.id
        statusLine = "Selected \(node.name)"
        refreshConfigPreview()
        persistState()
    }

    func toggleRule(_ rule: AppRuleViewModel) {
        guard let index = appRules.firstIndex(where: { $0.id == rule.id }) else { return }
        appRules[index].enabled.toggle()
        refreshConfigPreview()
        persistState()
    }

    func importFromClipboard() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        guard !raw.isEmpty else {
            statusLine = "Clipboard is empty"
            return
        }
        importSubscriptionLink(raw)
    }

    func importSubscriptionLink(_ link: String) {
        let cleaned = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusLine = "VLESS URI or subscription URL"
            return
        }

        let isSubscription = cleaned.lowercased().hasPrefix("http://") || cleaned.lowercased().hasPrefix("https://")
        if isSubscription {
            statusLine = "Importing subscription..."
        } else {
            statusLine = "Importing config..."
        }

        Task {
            do {
                let payload = try await SubscriptionImporter.importProfile(cleaned)
                let importedProfiles = payload.nodes.map { node in
                    ProfileSummary(
                        id: UUID().uuidString,
                        title: node.name,
                        source: isSubscription ? "Subscription" : "URI",
                        updatedAt: Date(),
                        trafficUsedGB: 0,
                        trafficTotalGB: Double(payload.usage?.totalBytes ?? 0) / 1_073_741_824,
                        nodes: [node]
                    )
                }

                await MainActor.run {
                    profiles.insert(contentsOf: importedProfiles, at: 0)
                    if isSubscription {
                        let subscription = SubscriptionSummary(
                            id: "sub-\(UUID().uuidString)",
                            title: subscriptionTitle(from: cleaned),
                            url: cleaned,
                            profileIDs: importedProfiles.map(\.id),
                            updatedAt: Date()
                        )
                        subscriptions.insert(subscription, at: 0)
                    }
                    if let first = importedProfiles.first {
                        selectProfile(first)
                    }
                    statusLine = "Imported \(importedProfiles.count) config(s)"
                    persistState()
                }
            } catch {
                await MainActor.run {
                    statusLine = isSubscription
                        ? "Subscription import failed: \(error.localizedDescription)"
                        : "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func updateSubscription(_ subscription: SubscriptionSummary) {
        guard !updatingSubscriptionIDs.contains(subscription.id) else { return }
        updatingSubscriptionIDs.insert(subscription.id)
        statusLine = "Updating \(subscription.title)..."

        Task {
            do {
                let payload = try await SubscriptionImporter.importProfile(subscription.url)
                let refreshedProfiles = payload.nodes.map { node in
                    ProfileSummary(
                        id: UUID().uuidString,
                        title: node.name,
                        source: "Subscription",
                        updatedAt: Date(),
                        trafficUsedGB: 0,
                        trafficTotalGB: Double(payload.usage?.totalBytes ?? 0) / 1_073_741_824,
                        nodes: [node]
                    )
                }

                await MainActor.run {
                    let currentSubscription = subscriptions.first { $0.id == subscription.id } ?? subscription
                    let oldIDs = Set(currentSubscription.profileIDs)
                    profiles.removeAll { oldIDs.contains($0.id) }
                    profiles.insert(contentsOf: refreshedProfiles, at: 0)
                    if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                        subscriptions[index].profileIDs = refreshedProfiles.map(\.id)
                        subscriptions[index].updatedAt = Date()
                    }
                    if let first = refreshedProfiles.first {
                        selectProfile(first)
                    }
                    updatingSubscriptionIDs.remove(subscription.id)
                    statusLine = "Updated \(refreshedProfiles.count) configs from \(subscription.title)"
                    persistState()
                }
            } catch {
                await MainActor.run {
                    updatingSubscriptionIDs.remove(subscription.id)
                    statusLine = "Update failed for \(subscription.title): \(error.localizedDescription)"
                }
            }
        }
    }

    func renameProfile(_ profile: ProfileSummary) {
        promptRename(title: "Rename Config", message: "Enter a new name for this config.", placeholder: "Config name", value: profile.title) { [weak self] newTitle in
            guard let self, let index = self.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            self.profiles[index].title = newTitle
            self.statusLine = "Renamed config to \(newTitle)"
            self.persistState()
        }
    }

    func deleteProfile(_ profile: ProfileSummary) {
        profiles.removeAll { $0.id == profile.id }
        subscriptions = subscriptions.map { subscription in
            var copy = subscription
            copy.profileIDs.removeAll { $0 == profile.id }
            return copy
        }.filter { !$0.profileIDs.isEmpty }
        if tunnel.selectedProfileID == profile.id {
            tunnel.selectedProfileID = profiles.first?.id
            tunnel.selectedNodeID = profiles.first?.nodes.first?.id
        }
        statusLine = "Deleted \(profile.title)"
        refreshConfigPreview()
        persistState()
    }

    func renameSubscription(_ subscription: SubscriptionSummary) {
        promptRename(title: "Rename Subscription", message: "Enter a new name for this subscription.", placeholder: "Subscription name", value: subscription.title) { [weak self] newTitle in
            guard let self, let index = self.subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
            self.subscriptions[index].title = newTitle
            self.statusLine = "Renamed subscription to \(newTitle)"
            self.persistState()
        }
    }

    func deleteSubscription(_ subscription: SubscriptionSummary) {
        let profileIDs = Set(subscription.profileIDs)
        subscriptions.removeAll { $0.id == subscription.id }
        profiles.removeAll { profileIDs.contains($0.id) }
        if let active = tunnel.selectedProfileID, profileIDs.contains(active) {
            tunnel.selectedProfileID = profiles.first?.id
            tunnel.selectedNodeID = profiles.first?.nodes.first?.id
        }
        statusLine = "Deleted subscription \(subscription.title)"
        refreshConfigPreview()
        persistState()
    }

    func toggleSubscriptionCollapsed(_ subscription: SubscriptionSummary) {
        if collapsedSubscriptionIDs.contains(subscription.id) {
            collapsedSubscriptionIDs.remove(subscription.id)
        } else {
            collapsedSubscriptionIDs.insert(subscription.id)
        }
        persistState()
    }

    func pingProfile(_ profile: ProfileSummary) {
        guard let node = profile.nodes.first else { return }
        profilePingStates[profile.id] = .pinging
        statusLine = "Pinging \(profile.title)..."

        Task {
            do {
                async let measured = measuredLatency(for: node, profileID: profile.id)
                async let countryCode = Self.resolveProfileCountryCode(profile)
                let latency = try await measured
                let resolvedCountryCode = await countryCode
                await MainActor.run {
                    profilePingStates[profile.id] = latency > 850 ? .timeout : .latency(latency)
                    if let resolvedCountryCode {
                        profileCountryCodes[profile.id] = resolvedCountryCode
                    }
                    lastPingMs = latency
                    lastPingProfileID = profile.id
                    statusLine = latency > 850 ? "Ping failed for \(profile.title)" : "Pinged \(profile.title) in \(latency) ms"
                    sortProfilesByPing()
                    persistState()
                }
            } catch {
                await MainActor.run {
                    profilePingStates[profile.id] = .timeout
                    statusLine = "Ping failed for \(profile.title)"
                }
            }
        }
    }

    func pingAllProfiles() {
        guard !pingingAll else { return }
        let targets = standaloneProfiles
        guard !targets.isEmpty else {
            statusLine = "No saved standalone configs to ping."
            return
        }

        pingingAll = true
        statusLine = "Pinging saved configs..."
        targets.forEach { profilePingStates[$0.id] = .pinging }

        Task {
            await pingProfilesInBatches(targets)

            await MainActor.run {
                pingingAll = false
                statusLine = "Ping all complete."
                persistState()
            }
        }
    }

    func pingSubscription(_ subscription: SubscriptionSummary) {
        guard !pingingSubscriptionIDs.contains(subscription.id) else { return }
        pingingSubscriptionIDs.insert(subscription.id)
        statusLine = "Pinging \(subscription.title)..."

        let subscriptionProfiles = profiles.filter { subscription.profileIDs.contains($0.id) }
        subscriptionProfiles.forEach { profilePingStates[$0.id] = .pinging }

        Task {
            await pingProfilesInBatches(subscriptionProfiles)

            await MainActor.run {
                pingingSubscriptionIDs.remove(subscription.id)
                statusLine = "Ping complete for \(subscription.title)"
                persistState()
            }
        }
    }

    private func pingProfilesInBatches(_ targets: [ProfileSummary]) async {
        for startIndex in stride(from: 0, to: targets.count, by: Self.pingBatchSize) {
            let endIndex = min(startIndex + Self.pingBatchSize, targets.count)
            let batch = Array(targets[startIndex..<endIndex])

            await withTaskGroup(of: (String, Int?, String?).self) { group in
                for profile in batch {
                    group.addTask {
                        guard let node = profile.nodes.first else {
                            return (profile.id, nil, nil)
                        }
                        async let countryCode = Self.resolveProfileCountryCode(profile)
                        do {
                            let latency = try await Self.measuredProbeLatency(for: node)
                            return (profile.id, latency, await countryCode)
                        } catch {
                            return (profile.id, nil, await countryCode)
                        }
                    }
                }

                for await (profileID, latency, countryCode) in group {
                    await MainActor.run {
                        if let latency, latency <= 850 {
                            profilePingStates[profileID] = .latency(latency)
                        } else {
                            profilePingStates[profileID] = .timeout
                        }
                        if let countryCode {
                            profileCountryCodes[profileID] = countryCode
                        }
                        sortProfilesByPing()
                    }
                }
            }
        }
    }

    func runLatencyTest() {
        guard let activeProfile else {
            statusLine = "No imported config yet."
            return
        }
        pingProfile(activeProfile)
    }

    func refreshConfigPreview() {
        guard let node = activeNode else {
            configPreview = "{}"
            return
        }

        do {
            let data = try XrayConfigBuilder.build(node: node)
            configPreview = String(decoding: data, as: UTF8.self)
        } catch {
            configPreview = "{\n  \"error\": \"\(error.localizedDescription)\"\n}"
        }
    }

    func discoverApplications() {
        statusLine = "Per-app routing requires a signed Network Extension on macOS."
    }

    var filteredRules: [AppRuleViewModel] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return appRules }
        return appRules.filter {
            $0.name.localizedCaseInsensitiveContains(term) ||
            $0.processName.localizedCaseInsensitiveContains(term) ||
            $0.bundleId.localizedCaseInsensitiveContains(term)
        }
    }

    private func runActivePing() async {
        guard let activeProfile else { return }
        await MainActor.run {
            pinging = true
            profilePingStates[activeProfile.id] = .pinging
            statusLine = "Pinging \(activeProfile.title)..."
        }

        do {
            let latency = try await measuredLatency(for: activeProfile.nodes[0], profileID: activeProfile.id)
            await MainActor.run {
                pinging = false
                profilePingStates[activeProfile.id] = latency > 850 ? .timeout : .latency(latency)
                lastPingMs = latency
                lastPingProfileID = activeProfile.id
                statusLine = latency > 850 ? "Ping failed for \(activeProfile.title)" : "Pinged \(activeProfile.title) in \(latency) ms"
                sortProfilesByPing()
            }
        } catch {
            await MainActor.run {
                pinging = false
                profilePingStates[activeProfile.id] = .timeout
                statusLine = "Ping failed for \(activeProfile.title)"
            }
        }
    }

    private func measuredLatency(for node: ProxyNode, profileID: String?) async throws -> Int {
        if tunnel.connected,
           profileID == nil || profileID == activeProfile?.id,
           let proxyPort = SingboxConfigBuilder.localProxyPort as Int? {
            _ = try await Self.measuredConnectedProxyLatency(proxyPort: proxyPort)
            return try await Self.measuredEndpointLatency(for: node)
        }

        return try await Self.measuredProbeLatency(for: node)
    }

    private nonisolated static func measuredConnectedProxyLatency(proxyPort: Int) async throws -> Int {
        var lastError: Error?
        for url in connectedProbeURLs {
            do {
                let result = try await ConnectivityTester.testHTTPViaLocalProxy(
                    url: url,
                    proxyHost: SingboxConfigBuilder.loopbackProxyHost,
                    proxyPort: proxyPort,
                    timeout: proxyPingTimeout
                )
                return result.latencyMs
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.timedOut)
    }

    private nonisolated static func measuredProbeLatency(for node: ProxyNode) async throws -> Int {
        try await measuredEndpointLatency(for: node)
    }

    private nonisolated static func measuredEndpointLatency(for node: ProxyNode) async throws -> Int {
        try await ConnectivityTester.testEndpointPing(to: node, timeout: proxyPingTimeout)
    }

    private nonisolated static func resolveProfileCountryCode(_ profile: ProfileSummary) async -> String? {
        if let fromText = inferCountryCode(from: "\(profile.title) \(profile.nodes.first?.name ?? "")") {
            return fromText
        }
        guard let server = profile.nodes.first?.server, !server.isEmpty else {
            return nil
        }
        return await lookupCountryCode(for: server)
    }

    private nonisolated static func lookupCountryCode(for server: String) async -> String? {
        guard let encodedServer = server.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        do {
            let response = try await ConnectivityTester.fetchTextDirect(
                url: "http://ip-api.com/json/\(encodedServer)?fields=status,countryCode,query",
                timeout: 2
            )
            guard let data = response.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["status"] as? String) == "success",
                  let code = json["countryCode"] as? String,
                  code.count == 2
            else {
                return nil
            }
            return code.uppercased()
        } catch {
            return nil
        }
    }

    private nonisolated static func inferCountryCode(from text: String) -> String? {
        if let flagCode = countryCodeFromFlagEmoji(text) {
            return flagCode
        }

        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let names: [(String, String)] = [
            ("united states", "US"), ("usa", "US"), ("u.s.a", "US"), ("america", "US"),
            ("canada", "CA"),
            ("germany", "DE"), ("deutschland", "DE"),
            ("france", "FR"),
            ("netherlands", "NL"), ("holland", "NL"),
            ("united kingdom", "GB"), ("uk", "GB"), ("england", "GB"),
            ("turkey", "TR"), ("turkiye", "TR"),
            ("finland", "FI"),
            ("sweden", "SE"),
            ("norway", "NO"),
            ("italy", "IT"),
            ("spain", "ES"),
            ("poland", "PL"),
            ("romania", "RO"),
            ("singapore", "SG"),
            ("japan", "JP"),
            ("korea", "KR"),
            ("india", "IN"),
            ("australia", "AU"),
            ("russia", "RU"),
            ("uae", "AE"), ("emirates", "AE"),
            ("iran", "IR")
        ]

        return names.first { normalized.contains($0.0) }?.1
    }

    private nonisolated static func countryCodeFromFlagEmoji(_ text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        for index in scalars.indices.dropLast() {
            let first = scalars[index].value
            let second = scalars[scalars.index(after: index)].value
            let regionalIndicatorBase: UInt32 = 127397
            guard (127462...127487).contains(first),
                  (127462...127487).contains(second),
                  let firstScalar = UnicodeScalar(first - regionalIndicatorBase),
                  let secondScalar = UnicodeScalar(second - regionalIndicatorBase)
            else {
                continue
            }
            return "\(String(firstScalar))\(String(secondScalar))"
        }
        return nil
    }

    private func refreshExitLocation(afterConnectingTo node: ProxyNode) async {
        do {
            let response = try await Self.fetchExitLocationPayload()
            let location = parseLocationPayload(response)
            await MainActor.run {
                tunnel.exitIP = location.ip
                tunnel.countryCode = location.countryCode
                tunnel.countryName = location.countryName
                if let profileID = tunnel.selectedProfileID, let countryCode = location.countryCode {
                    profileCountryCodes[profileID] = countryCode
                    persistState()
                }
                statusLine = "Connected via \(node.name)"
            }
        } catch {
            await MainActor.run {
                statusLine = "Connected via \(node.name), but exit country lookup failed."
            }
        }
    }

    private nonisolated static func fetchExitLocationPayload() async throws -> String {
        var lastError: Error?
        for url in exitLookupURLs {
            do {
                let response = try await ConnectivityTester.fetchTextViaLocalProxy(
                    url: url,
                    proxyHost: SingboxConfigBuilder.loopbackProxyHost,
                    proxyPort: SingboxConfigBuilder.localProxyPort,
                    timeout: 4
                )
                if response.contains("country") || response.contains("country_code") || response.contains("countryCode") {
                    return response
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.timedOut)
    }

    private func parseLocationPayload(_ response: String) -> (ip: String?, countryCode: String?, countryName: String?) {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, nil, nil)
        }

        let ip = json["ip"] as? String ?? json["query"] as? String
        let country = json["country"] as? String
        let countryCode = json["country_code"] as? String
            ?? json["countryCode"] as? String
            ?? (country?.count == 2 ? country : nil)
        let countryName = (country?.count == 2 ? nil : country) ?? json["country_name"] as? String
        return (ip, countryCode?.uppercased(), countryName)
    }

    private func sortProfilesByPing() {
        profiles.sort { lhs, rhs in
            pingSortValue(lhs.id) < pingSortValue(rhs.id)
        }
    }

    private func pingSortValue(_ profileID: String) -> Int {
        switch profilePingStates[profileID] {
        case let .latency(ms):
            return ms
        case .timeout:
            return 10_000
        case .pinging:
            return 9_000
        case .idle, .none:
            return 8_000
        }
    }

    private func subscriptionTitle(from value: String) -> String {
        guard let url = URL(string: value), let host = url.host else {
            return "Subscription"
        }
        let lastPath = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPath.isEmpty ? host : lastPath
    }

    private func persistState() {
        let state = PersistedAppState(
            profiles: profiles,
            subscriptions: subscriptions,
            appRules: appRules,
            activeProfileId: tunnel.selectedProfileID,
            activeNodeId: tunnel.selectedNodeID,
            mode: tunnel.mode,
            collapsedSubscriptionIDs: Array(collapsedSubscriptionIDs),
            profileCountryCodes: profileCountryCodes,
            routerSocksModeEnabled: routerSocksModeEnabled
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state),
              let raw = String(data: data, encoding: .utf8)
        else {
            return
        }
        UserDefaults.standard.set(raw, forKey: "v2dex.persisted.app.state")
    }

    private func loadPersistedState() {
        guard let raw = UserDefaults.standard.string(forKey: "v2dex.persisted.app.state"),
              let data = raw.data(using: .utf8)
        else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date"
            )
        }

        guard let state = try? decoder.decode(PersistedAppState.self, from: data) else {
            statusLine = "Saved profile could not be loaded"
            return
        }

        if !state.profiles.isEmpty {
            profiles = state.profiles
        }
        subscriptions = state.subscriptions
        if !state.appRules.isEmpty {
            appRules = state.appRules
        }
        tunnel.selectedProfileID = state.activeProfileId
        tunnel.selectedNodeID = state.activeNodeId
        tunnel.mode = state.mode ?? .full
        collapsedSubscriptionIDs = Set(state.collapsedSubscriptionIDs ?? [])
        profileCountryCodes = state.profileCountryCodes ?? [:]
        routerSocksModeEnabled = state.routerSocksModeEnabled ?? false
        statusLine = "Loaded saved config"
    }

    private func promptRename(
        title: String,
        message: String,
        placeholder: String,
        value: String,
        onSave: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = placeholder
        input.stringValue = value
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let cleaned = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            onSave(cleaned)
        }
    }
}
