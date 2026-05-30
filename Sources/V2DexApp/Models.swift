import Foundation
import V2DexCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case routing = "Routing"
    case profiles = "Profiles"
    case latency = "Latency"
    case settings = "Settings"

    var id: String { rawValue }
}

struct ProfileSummary: Identifiable {
    let id: String
    var title: String
    var source: String
    var updatedAt: Date
    var trafficUsedGB: Double
    var trafficTotalGB: Double
    var nodes: [ProxyNode]
}

struct TunnelSnapshot {
    var connected = false
    var connecting = false
    var mode: TunnelMode = .full
    var dnsLeakProtection = true
    var selectedProfileID: String?
    var selectedNodeID: String?
    var lastError: String?
    var lastConnectedAt: Date?
}

struct AppRuleViewModel: Identifiable {
    let id: String
    let bundleId: String
    let name: String
    let processName: String
    var enabled: Bool

    init(bundleId: String, name: String, processName: String, enabled: Bool) {
        self.id = bundleId
        self.bundleId = bundleId
        self.name = name
        self.processName = processName
        self.enabled = enabled
    }

    var coreRule: AppRouteRule {
        AppRouteRule(bundleId: bundleId, name: name, processName: processName, enabled: enabled)
    }
}
