import Foundation

public struct TunnelLaunchRequest: Codable {
    public let node: ProxyNode
    public let mode: TunnelMode
    public let appRules: [AppRouteRule]
    public let explicitBinaryPath: String?

    public init(node: ProxyNode, mode: TunnelMode, appRules: [AppRouteRule], explicitBinaryPath: String? = nil) {
        self.node = node
        self.mode = mode
        self.appRules = appRules
        self.explicitBinaryPath = explicitBinaryPath
    }
}

public enum BackendCoordinator {
    public static func importNodes(from raw: String) async throws -> [ProxyNode] {
        try await SubscriptionImporter.importRaw(raw)
    }

    public static func importProfile(from raw: String) async throws -> ImportedProfilePayload {
        try await SubscriptionImporter.importProfile(raw)
    }

    public static func buildConfig(for request: TunnelLaunchRequest) throws -> Data {
        try SingboxConfigBuilder.build(node: request.node, mode: request.mode, appRules: request.appRules)
    }

    public static func launchRuntime(for request: TunnelLaunchRequest) throws -> TunnelStatusSnapshot {
        let configData = try buildConfig(for: request)
        return try SingboxRuntime.shared.start(
            configData: configData,
            mode: request.mode,
            appRules: request.appRules,
            binaryPath: request.explicitBinaryPath
        )
    }

    public static func discoverApplications(limit: Int = 200) -> [AppRouteRule] {
        ApplicationDiscovery.discover(limit: limit)
    }

    public static func testSubscriptionDownload(from raw: String) async throws -> String {
        let payload = try await SubscriptionImporter.importProfile(raw)
        if let remainingBytes = payload.usage?.remainingBytes {
            let formatted = ByteCountFormatter.string(fromByteCount: remainingBytes, countStyle: .binary)
            return "Downloaded and parsed \(payload.nodes.count) node(s). Remaining: \(formatted)."
        }
        return "Downloaded and parsed \(payload.nodes.count) node(s)."
    }
}
