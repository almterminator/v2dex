import Foundation

public enum XrayConfigBuilder {
    public static let localHTTPProxyPort = 2081
    public static let localSocksProxyPort = 2082

    public static func build(
        node: ProxyNode,
        httpPort: Int = localHTTPProxyPort,
        socksPort: Int = localSocksProxyPort
    ) throws -> Data {
        let config: [String: Any] = [
            "log": [
                "loglevel": "warning"
            ],
            "inbounds": [
                [
                    "tag": "local-http",
                    "listen": SingboxConfigBuilder.loopbackProxyHost,
                    "port": httpPort,
                    "protocol": "http"
                ],
                [
                    "tag": "local-socks",
                    "listen": SingboxConfigBuilder.loopbackProxyHost,
                    "port": socksPort,
                    "protocol": "socks",
                    "settings": [
                        "auth": "noauth",
                        "udp": true,
                        "ip": SingboxConfigBuilder.loopbackProxyHost
                    ],
                    "sniffing": [
                        "enabled": true,
                        "destOverride": [
                            "http",
                            "tls",
                            "quic"
                        ],
                        "routeOnly": false
                    ]
                ]
            ],
            "outbounds": [
                try proxyOutbound(for: node),
                [
                    "tag": "direct",
                    "protocol": "freedom"
                ],
                [
                    "tag": "block",
                    "protocol": "blackhole"
                ]
            ],
            "routing": [
                "domainStrategy": "IPIfNonMatch",
                "rules": [
                    [
                        "type": "field",
                        "ip": [
                            "127.0.0.0/8",
                            "10.0.0.0/8",
                            "172.16.0.0/12",
                            "192.168.0.0/16",
                            "169.254.0.0/16",
                            "fc00::/7",
                            "fe80::/10"
                        ],
                        "outboundTag": "direct"
                    ],
                    [
                        "type": "field",
                        "network": "tcp,udp",
                        "outboundTag": "proxy"
                    ]
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    private static func proxyOutbound(for node: ProxyNode) throws -> [String: Any] {
        var outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": xrayProtocol(for: node),
            "streamSettings": streamSettings(for: node)
        ]

        switch node.protocolType {
        case "vless":
            var user: [String: Any] = [
                "encryption": "none"
            ]
            if let uuid = node.uuid, !uuid.isEmpty {
                user["id"] = uuid
            }
            if let flow = node.flow, !flow.isEmpty {
                user["flow"] = flow
            }
            outbound["settings"] = [
                "vnext": [
                    [
                        "address": node.server,
                        "port": node.port,
                        "users": [
                            user
                        ]
                    ]
                ]
            ]
        case "vmess":
            var user: [String: Any] = [
                "alterId": node.alterId ?? 0,
                "security": node.vmessCipher ?? "auto"
            ]
            if let uuid = node.uuid, !uuid.isEmpty {
                user["id"] = uuid
            }
            outbound["settings"] = [
                "vnext": [
                    [
                        "address": node.server,
                        "port": node.port,
                        "users": [
                            user
                        ]
                    ]
                ]
            ]
        case "trojan":
            var server: [String: Any] = [
                "address": node.server,
                "port": node.port
            ]
            if let password = node.password, !password.isEmpty {
                server["password"] = password
            }
            outbound["settings"] = [
                "servers": [
                    server
                ]
            ]
        case "socks5":
            outbound["protocol"] = "socks"
            outbound.removeValue(forKey: "streamSettings")
            var server: [String: Any] = [
                "address": node.server,
                "port": node.port
            ]
            if let username = node.username, !username.isEmpty {
                server["users"] = [
                    [
                        "user": username,
                        "pass": node.password ?? ""
                    ]
                ]
            }
            outbound["settings"] = [
                "servers": [
                    server
                ]
            ]
        case "http", "https":
            outbound["protocol"] = "http"
            outbound.removeValue(forKey: "streamSettings")
            var server: [String: Any] = [
                "address": node.server,
                "port": node.port
            ]
            if let username = node.username, !username.isEmpty {
                server["users"] = [
                    [
                        "user": username,
                        "pass": node.password ?? ""
                    ]
                ]
            }
            outbound["settings"] = [
                "servers": [
                    server
                ]
            ]
        default:
            throw XrayConfigBuilderError.unsupportedProtocol(node.protocolType)
        }

        return outbound
    }

    private static func xrayProtocol(for node: ProxyNode) -> String {
        node.protocolType == "socks5" ? "socks" : node.protocolType
    }

    private static func streamSettings(for node: ProxyNode) -> [String: Any] {
        let network: String
        switch node.transport {
        case "grpc":
            network = "grpc"
        case "ws":
            network = "ws"
        default:
            network = "tcp"
        }

        var stream: [String: Any] = [
            "network": network,
            "security": node.security == "reality" ? "reality" : node.security == "tls" ? "tls" : "none",
            "sockopt": [
                "tcpFastOpen": true
            ]
        ]

        if node.security == "tls" {
            var tls: [String: Any] = [:]
            if let sni = node.sni, !sni.isEmpty {
                tls["serverName"] = sni
            }
            if let allowInsecure = node.allowInsecure {
                tls["allowInsecure"] = allowInsecure
            }
            if let alpn = node.alpn, !alpn.isEmpty {
                tls["alpn"] = alpn
            }
            if let fingerprint = node.fingerprint, !fingerprint.isEmpty {
                tls["fingerprint"] = fingerprint
            }
            stream["tlsSettings"] = tls
        }

        if node.security == "reality" {
            var reality: [String: Any] = [:]
            if let sni = node.sni, !sni.isEmpty {
                reality["serverName"] = sni
            }
            if let publicKey = node.publicKey, !publicKey.isEmpty {
                reality["publicKey"] = publicKey
            }
            if let shortId = node.shortId, !shortId.isEmpty {
                reality["shortId"] = shortId
            }
            reality["fingerprint"] = node.fingerprint ?? "chrome"
            stream["realitySettings"] = reality
        }

        if network == "ws" {
            var ws: [String: Any] = [
                "path": normalizedWebSocketPath(node.path ?? "/")
            ]
            if let wsHost = node.wsHost, !wsHost.isEmpty {
                ws["headers"] = [
                    "Host": wsHost
                ]
            }
            stream["wsSettings"] = ws
        }

        if network == "grpc" {
            stream["grpcSettings"] = [
                "serviceName": (node.path ?? "grpc").replacingOccurrences(of: #"^/"#, with: "", options: .regularExpression)
            ]
        }

        return stream
    }

    private static func normalizedWebSocketPath(_ rawPath: String) -> String {
        let cleanedPath = rawPath.replacingOccurrences(of: #"\/"#, with: "/")
        return cleanedPath.isEmpty ? "/" : cleanedPath
    }
}

public enum XrayConfigBuilderError: LocalizedError {
    case unsupportedProtocol(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProtocol(value):
            return "\(value.uppercased()) is not supported by the macOS Xray runtime yet."
        }
    }
}
