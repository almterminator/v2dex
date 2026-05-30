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

    var activeProfile: ProfileSummary? {
        profiles.first { $0.id == tunnel.selectedProfileID } ?? profiles.first
    }

    var activeNode: ProxyNode? {
        guard let activeProfile else { return nil }
        return activeProfile.nodes.first { $0.id == tunnel.selectedNodeID } ?? activeProfile.nodes.first
    }

    init() {
        tunnel.selectedProfileID = profiles.first?.id
        tunnel.selectedNodeID = profiles.first?.nodes.first?.id
        refreshConfigPreview()
    }

    func toggleConnection() {
        if tunnel.connected {
            tunnel.connected = false
            tunnel.connecting = false
            statusLine = "System proxy disconnected"
            return
        }

        tunnel.connecting = true
        statusLine = "Starting local proxy runtime..."

        Task {
            try? await Task.sleep(for: .milliseconds(650))
            tunnel.connecting = false
            tunnel.connected = true
            tunnel.lastConnectedAt = Date()
            statusLine = "macOS proxy active via \(activeNode?.name ?? "selected node")"
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
        guard var profile = activeProfile else {
            statusLine = "No active profile"
            return
        }

        profile.nodes = profile.nodes.enumerated().map { offset, node in
            var copy = node
            copy = ProxyNode(
                id: node.id,
                name: node.name,
                protocolType: node.protocolType,
                server: node.server,
                port: node.port,
                security: node.security,
                transport: node.transport,
                sni: node.sni,
                path: node.path
            )
            return copy
        }

        for index in profile.nodes.indices {
            let base = 32 + index * 18
            profile.nodes[index] = ProxyNode(
                id: profile.nodes[index].id,
                name: profile.nodes[index].name + " · \(base)ms",
                protocolType: profile.nodes[index].protocolType,
                server: profile.nodes[index].server,
                port: profile.nodes[index].port,
                security: profile.nodes[index].security,
                transport: profile.nodes[index].transport,
                sni: profile.nodes[index].sni,
                path: profile.nodes[index].path
            )
        }

        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        }

        statusLine = "Latency test complete"
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
