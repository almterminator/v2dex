import Foundation

public enum TunnelMode: String, Codable {
    case full
    case perApp = "per-app"
}

public enum RuntimeBackend: String, Codable {
    case systemProxy = "system-proxy"
    case appProxy = "app-proxy"
}

public struct ProxyNode: Codable, Identifiable {
    public let id: String
    public let name: String
    public let protocolType: String
    public let server: String
    public let port: Int
    public let security: String?
    public let transport: String?
    public let sni: String?
    public let path: String?
    public let uuid: String?
    public let password: String?
    public let wsHost: String?
    public let flow: String?
    public let udpOverTCP: Bool?
    public let allowInsecure: Bool?
    public let publicKey: String?
    public let shortId: String?
    public let fingerprint: String?
    public let alpn: [String]?
    public let alterId: Int?
    public let vmessCipher: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case protocolType = "protocol"
        case server
        case port
        case security
        case transport
        case sni
        case path
        case uuid
        case password
        case wsHost
        case flow
        case udpOverTCP
        case allowInsecure
        case publicKey
        case shortId
        case fingerprint
        case alpn
        case alterId
        case vmessCipher
    }

    public init(
        id: String,
        name: String,
        protocolType: String,
        server: String,
        port: Int,
        security: String?,
        transport: String?,
        sni: String?,
        path: String?,
        uuid: String? = nil,
        password: String? = nil,
        wsHost: String? = nil,
        flow: String? = nil,
        udpOverTCP: Bool? = nil,
        allowInsecure: Bool? = nil,
        publicKey: String? = nil,
        shortId: String? = nil,
        fingerprint: String? = nil,
        alpn: [String]? = nil,
        alterId: Int? = nil,
        vmessCipher: String? = nil
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.server = server
        self.port = port
        self.security = security
        self.transport = transport
        self.sni = sni
        self.path = path
        self.uuid = uuid
        self.password = password
        self.wsHost = wsHost
        self.flow = flow
        self.udpOverTCP = udpOverTCP
        self.allowInsecure = allowInsecure
        self.publicKey = publicKey
        self.shortId = shortId
        self.fingerprint = fingerprint
        self.alpn = alpn
        self.alterId = alterId
        self.vmessCipher = vmessCipher
    }
}

public struct AppRouteRule: Codable, Identifiable {
    public let id: String
    public let bundleId: String
    public let name: String
    public let processName: String
    public let enabled: Bool

    public init(bundleId: String, name: String, processName: String, enabled: Bool) {
        self.id = bundleId
        self.bundleId = bundleId
        self.name = name
        self.processName = processName
        self.enabled = enabled
    }
}

public struct SubscriptionUsage: Codable {
    public let uploadBytes: Int64?
    public let downloadBytes: Int64?
    public let totalBytes: Int64?
    public let usedBytes: Int64?
    public let remainingBytes: Int64?
    public let expiresAt: Date?

    public init(
        uploadBytes: Int64? = nil,
        downloadBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        usedBytes: Int64? = nil,
        remainingBytes: Int64? = nil,
        expiresAt: Date? = nil
    ) {
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.remainingBytes = remainingBytes
        self.expiresAt = expiresAt
    }
}

public struct ImportedProfilePayload: Codable {
    public let nodes: [ProxyNode]
    public let usage: SubscriptionUsage?

    public init(nodes: [ProxyNode], usage: SubscriptionUsage? = nil) {
        self.nodes = nodes
        self.usage = usage
    }
}

public struct TunnelStatusSnapshot: Codable {
    public let connected: Bool
    public let connecting: Bool
    public let mode: TunnelMode
    public let backend: RuntimeBackend
    public let lastError: String?
    public let lastConnectedAt: Date?
    public let binaryPath: String?
    public let activeConfigPath: String?
    public let proxyHost: String?
    public let proxyPort: Int?

    public init(
        connected: Bool,
        connecting: Bool,
        mode: TunnelMode,
        backend: RuntimeBackend = .systemProxy,
        lastError: String? = nil,
        lastConnectedAt: Date? = nil,
        binaryPath: String? = nil,
        activeConfigPath: String? = nil,
        proxyHost: String? = nil,
        proxyPort: Int? = nil
    ) {
        self.connected = connected
        self.connecting = connecting
        self.mode = mode
        self.backend = backend
        self.lastError = lastError
        self.lastConnectedAt = lastConnectedAt
        self.binaryPath = binaryPath
        self.activeConfigPath = activeConfigPath
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
    }
}
