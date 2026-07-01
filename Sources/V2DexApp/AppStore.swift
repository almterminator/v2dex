import AppKit
import Combine
import Foundation
import V2DexCore

@MainActor
final class AppStore: ObservableObject {
    @Published var selection: SidebarSection = .overview
    @Published var tunnel = TunnelSnapshot()
    @Published var profiles: [ProfileSummary] = DemoData.profiles
    @Published var appRules: [AppRuleViewModel] = DemoData.appRules
    @Published var searchText = ""
    @Published var statusLine = "Ready"
    @Published var configPreview = "{}"

    private struct PersistedAppState: Codable {
        var profiles: [ProfileSummary]
        var appRules: [AppRuleViewModel]
        var activeProfileId: String?
        var activeNodeId: String?
        var mode: TunnelMode?
    }

    var activeProfile: ProfileSummary? {
        profiles.first { $0.id == tunnel.selectedProfileID } ?? profiles.first
    }

    var activeNode: ProxyNode? {
        guard let activeProfile else { return nil }
        return activeProfile.nodes.first { $0.id == tunnel.selectedNodeID } ?? activeProfile.nodes.first
    }

    init() {
        loadPersistedState()
        tunnel.selectedProfileID = tunnel.selectedProfileID ?? profiles.first?.id
        tunnel.selectedNodeID = tunnel.selectedNodeID ?? profiles.first?.nodes.first?.id
        refreshConfigPreview()
    }

    func toggleConnection() {
        if tunnel.connected {
            tunnel.connecting = true
            statusLine = "Stopping local proxy runtime..."
            Task {
                do {
                    try SingboxRuntime.shared.stopIfNeeded()
                    await MainActor.run {
                        tunnel.connected = false
                        tunnel.connecting = false
                        tunnel.lastError = nil
                        statusLine = "System proxy disconnected"
                    }
                } catch {
                    await MainActor.run {
                        tunnel.connected = false
                        tunnel.connecting = false
                        tunnel.lastError = error.localizedDescription
                        statusLine = "Disconnect failed: \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        guard let node = activeNode else {
            tunnel.lastError = "No active node"
            statusLine = "No active node"
            return
        }

        tunnel.connecting = true
        statusLine = "Starting local proxy runtime..."

        Task {
            do {
                let configData = try SingboxConfigBuilder.build(
                    node: node,
                    mode: tunnel.mode,
                    appRules: appRules.map(\.coreRule)
                )
                let snapshot = try SingboxRuntime.shared.start(
                    configData: configData,
                    mode: tunnel.mode,
                    appRules: appRules.map(\.coreRule)
                )
                await MainActor.run {
                    tunnel.connecting = snapshot.connecting
                    tunnel.connected = snapshot.connected
                    tunnel.lastConnectedAt = snapshot.lastConnectedAt ?? Date()
                    tunnel.lastError = nil
                    statusLine = "macOS proxy active via \(node.name)"
                }
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

    func setMode(_ mode: TunnelMode) {
        tunnel.mode = mode
        statusLine = mode == .full ? "System proxy enabled" : "App filter preview enabled"
        refreshConfigPreview()
    }

    func selectProfile(_ profile: ProfileSummary) {
        tunnel.selectedProfileID = profile.id
        tunnel.selectedNodeID = profile.nodes.first?.id
        refreshConfigPreview()
    }

    func selectNode(_ node: ProxyNode) {
        tunnel.selectedNodeID = node.id
        statusLine = "Selected \(node.name)"
        refreshConfigPreview()
    }

    func toggleRule(_ rule: AppRuleViewModel) {
        guard let index = appRules.firstIndex(where: { $0.id == rule.id }) else { return }
        appRules[index].enabled.toggle()
        refreshConfigPreview()
    }

    func importFromClipboard() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        guard !raw.isEmpty else {
            statusLine = "Clipboard is empty"
            return
        }
        statusLine = "Importing from clipboard..."

        Task {
            do {
                let importedNodes = try await SubscriptionImporter.importRaw(raw)
                let profile = ProfileSummary(
                    id: UUID().uuidString,
                    title: "Imported Clipboard Profile",
                    source: "Clipboard",
                    updatedAt: Date(),
                    trafficUsedGB: 0,
                    trafficTotalGB: 0,
                    nodes: importedNodes
                )
                profiles.insert(profile, at: 0)
                selectProfile(profile)
                statusLine = "Imported \(importedNodes.count) node(s) from clipboard"
            } catch {
                statusLine = "Clipboard import failed: \(error.localizedDescription)"
            }
        }
    }

    func importSubscriptionLink(_ link: String) {
        let cleaned = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusLine = "Enter a subscription or URI first"
            return
        }
        statusLine = "Importing profile..."

        Task {
            do {
                let importedNodes = try await SubscriptionImporter.importRaw(cleaned)
                let profile = ProfileSummary(
                    id: UUID().uuidString,
                    title: cleaned.contains("http") ? "Subscription Profile" : "Manual URI Profile",
                    source: cleaned.contains("http") ? "Subscription" : "URI",
                    updatedAt: Date(),
                    trafficUsedGB: Double.random(in: 24...180),
                    trafficTotalGB: 300,
                    nodes: importedNodes
                )
                profiles.insert(profile, at: 0)
                selectProfile(profile)
                statusLine = "Imported profile from \(profile.source.lowercased())"
            } catch {
                statusLine = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    func discoverApplications() {
        let appDirectories = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var discovered: [AppRuleViewModel] = []
        let fileManager = FileManager.default

        for directory in appDirectories {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url) else { continue }
                let bundleId = bundle.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? name
                discovered.append(.init(bundleId: bundleId, name: name, processName: executable, enabled: false))
                if discovered.count >= 40 {
                    break
                }
            }

            if discovered.count >= 40 {
                break
            }
        }

        if !discovered.isEmpty {
            let merged = Dictionary(uniqueKeysWithValues: (appRules + discovered).map { ($0.id, $0) })
            appRules = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            statusLine = "Discovered \(discovered.count) applications"
            refreshConfigPreview()
        }
    }

    func runLatencyTest() {
        guard let node = activeNode else {
            statusLine = "No active profile"
            return
        }

        statusLine = "Testing \(node.name)..."

        Task {
            do {
                let result = try await ConnectivityTester.testProxyHTTPProbe(to: node)
                await MainActor.run {
                    statusLine = "Ping \(result.latencyMs) ms via \(result.url)"
                }
            } catch {
                await MainActor.run {
                    statusLine = "Ping failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshConfigPreview() {
        guard let node = activeNode else {
            configPreview = "{}"
            return
        }

        do {
            let data = try SingboxConfigBuilder.build(
                node: node,
                mode: tunnel.mode,
                appRules: appRules.map(\.coreRule)
            )
            configPreview = String(decoding: data, as: UTF8.self)
        } catch {
            configPreview = "{\n  \"error\": \"\(error.localizedDescription)\"\n}"
        }
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
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }

        guard let state = try? decoder.decode(PersistedAppState.self, from: data) else {
            statusLine = "Saved profile could not be loaded"
            return
        }

        if !state.profiles.isEmpty {
            profiles = state.profiles
        }
        if !state.appRules.isEmpty {
            appRules = state.appRules
        }
        tunnel.selectedProfileID = state.activeProfileId
        tunnel.selectedNodeID = state.activeNodeId
        tunnel.mode = state.mode ?? .full
        statusLine = "Loaded saved profile"
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
}
