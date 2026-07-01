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

struct ProfileSummary: Identifiable, Codable {
    let id: String
    var title: String
    var source: String
    var updatedAt: Date
    var trafficUsedGB: Double
    var trafficTotalGB: Double
    var nodes: [ProxyNode]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case updatedAt
        case trafficUsedGB
        case trafficTotalGB
        case nodes
    }

    init(
        id: String,
        title: String,
        source: String,
        updatedAt: Date,
        trafficUsedGB: Double,
        trafficTotalGB: Double,
        nodes: [ProxyNode]
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.updatedAt = updatedAt
        self.trafficUsedGB = trafficUsedGB
        self.trafficTotalGB = trafficTotalGB
        self.nodes = nodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        source = try container.decode(String.self, forKey: .source)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        trafficUsedGB = try container.decodeIfPresent(Double.self, forKey: .trafficUsedGB) ?? 0
        trafficTotalGB = try container.decodeIfPresent(Double.self, forKey: .trafficTotalGB) ?? 0
        nodes = try container.decode([ProxyNode].self, forKey: .nodes)
    }
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

struct AppRuleViewModel: Identifiable, Codable {
    let id: String
    let bundleId: String
    let name: String
    let processName: String
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case bundleId
        case name
        case processName
        case enabled
    }

    init(bundleId: String, name: String, processName: String, enabled: Bool) {
        self.id = bundleId
        self.bundleId = bundleId
        self.name = name
        self.processName = processName
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleId = try container.decode(String.self, forKey: .bundleId)
        self.id = bundleId
        self.bundleId = bundleId
        self.name = try container.decode(String.self, forKey: .name)
        self.processName = try container.decode(String.self, forKey: .processName)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(name, forKey: .name)
        try container.encode(processName, forKey: .processName)
        try container.encode(enabled, forKey: .enabled)
    }

    var coreRule: AppRouteRule {
        AppRouteRule(bundleId: bundleId, name: name, processName: processName, enabled: enabled)
    }
}
