import Darwin
import Foundation

public enum SingboxConfigBuilder {
    public static let localProxyListenHost = "0.0.0.0"
    public static let loopbackProxyHost = "127.0.0.1"
    public static var localProxyHost: String {
        localNetworkProxyHost() ?? localProxyListenHost
    }
    public static let localProxyPort = 2081
    public static let tunAddress = "172.19.0.1/30"

    public static func build(node: ProxyNode, mode: TunnelMode, appRules: [AppRouteRule]) throws -> Data {
        let useTun = requiresTun(appRules: appRules)
        let routeRules = buildRouteRules(mode: mode, appRules: appRules, useTun: useTun)
        let finalOutbound = useTun ? "direct" : "proxy"

        let config: [String: Any] = [
            "log": [
                "level": "info"
            ],
            "inbounds": inbounds(useTun: useTun),
            "outbounds": [
                outboundDictionary(for: node),
                [
                    "tag": "direct",
                    "type": "direct"
                ]
            ],
            "route": [
                "auto_detect_interface": true,
                "final": finalOutbound,
                "rules": routeRules
            ]
        ]

        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    public static func requiresTun(appRules: [AppRouteRule]) -> Bool {
        false
    }

    private static func inbounds(useTun: Bool) -> [[String: Any]] {
        var values: [[String: Any]] = []

        if useTun {
            values.append([
                "type": "tun",
                "tag": "tun-in",
                "address": [
                    tunAddress
                ],
                "auto_route": true,
                "strict_route": true,
                "stack": "system"
            ])
        }

        values.append([
            "type": "mixed",
            "tag": "mixed-in",
            "listen": localProxyListenHost,
            "listen_port": localProxyPort,
            "set_system_proxy": false
        ])

        return values
    }

    private static func localNetworkProxyHost() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }

            let interface = item.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard !isVirtualInterface(name) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let ipAddress = String(cString: hostname)
            if isPrivateIPv4(ipAddress) {
                return ipAddress
            }
            fallback = fallback ?? ipAddress
        }

        return fallback
    }

    private static func isVirtualInterface(_ name: String) -> Bool {
        let blockedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "anpi"]
        return blockedPrefixes.contains { name.hasPrefix($0) }
    }

    private static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        return parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }

    private static func buildRouteRules(mode: TunnelMode, appRules: [AppRouteRule], useTun: Bool) -> [[String: Any]] {
        var routeRules: [[String: Any]] = []

        if useTun {
            routeRules.append([
                "inbound": [
                    "mixed-in"
                ],
                "outbound": "proxy"
            ])
        }

        let selectedRules = appRules.filter { rule in
            guard rule.enabled else {
                return false
            }
            if mode == .perApp {
                return true
            }
            return isTelegramBundle(rule.bundleId)
        }

        for rule in selectedRules {
            let processNames = Array(Set(expandProcessNames(for: rule))).sorted()
            if !processNames.isEmpty {
                routeRules.append([
                    "process_name": processNames,
                    "outbound": "proxy"
                ])
            }

            let pathRegexes = knownProcessPathRegexes(bundleId: rule.bundleId)
            if !pathRegexes.isEmpty {
                routeRules.append([
                    "process_path_regex": pathRegexes,
                    "outbound": "proxy"
                ])
            }
        }

        return routeRules
    }

    private static func isTelegramBundle(_ bundleId: String) -> Bool {
        ["ru.keepcoder.Telegram", "com.tdesktop.Telegram"].contains(bundleId)
    }

    private static func expandProcessNames(for rule: AppRouteRule) -> [String] {
        var names = Set<String>()
        let candidates = [rule.processName, rule.name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            names.insert(candidate)
            names.insert("\(candidate) Helper")
            names.insert("\(candidate) Helper (GPU)")
            names.insert("\(candidate) Helper (Renderer)")
            names.insert("\(candidate)Helper")
        }

        for alias in knownProcessAliases(bundleId: rule.bundleId) {
            names.insert(alias)
        }

        return Array(names)
    }

    private static func knownProcessAliases(bundleId: String) -> [String] {
        switch bundleId {
        case "com.google.Chrome":
            return [
                "Google Chrome",
                "Google Chrome Helper",
                "Google Chrome Helper (GPU)",
                "Google Chrome Helper (Renderer)"
            ]
        case "com.openai.codex":
            return [
                "Codex",
                "Codex Helper",
                "Codex Helper (GPU)",
                "Codex Helper (Renderer)",
                "codex",
                "node_repl"
            ]
        case "com.openai.chat":
            return [
                "ChatGPT",
                "ChatGPTHelper",
                "ChatGPT Helper",
                "ChatGPT Helper (GPU)",
                "ChatGPT Helper (Renderer)"
            ]
        case "ru.keepcoder.Telegram", "com.tdesktop.Telegram":
            return [
                "Telegram",
                "Telegram Desktop",
                "telegram-desktop",
                "TelegramUpdater",
                "Telegram Helper",
                "Telegram Helper (GPU)",
                "Telegram Helper (Renderer)"
            ]
        case "com.apple.Safari":
            return [
                "Safari",
                "com.apple.WebKit.Networking",
                "com.apple.WebKit.WebContent",
                "com.apple.WebKit.GPU",
                "com.apple.Safari.SearchHelper"
            ]
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            return [
                "Code",
                "Code Helper",
                "Code Helper (GPU)",
                "Code Helper (Renderer)"
            ]
        default:
            return []
        }
    }

    private static func knownProcessPathRegexes(bundleId: String) -> [String] {
        switch bundleId {
        case "com.openai.codex":
            return [
                #"^/.*/Codex\.app/Contents/MacOS/Codex$"#,
                #"^/.*/Codex\.app/Contents/Resources/codex$"#,
                #"^/.*/Codex\.app/Contents/Resources/node_repl$"#,
                #"^/.*/Codex\.app/Contents/Frameworks/Codex Helper(?: \(GPU\)| \(Renderer\))?\.app/Contents/MacOS/Codex Helper(?: \(GPU\)| \(Renderer\))?$"#
            ]
        case "com.openai.chat":
            return [
                #"^/.*/ChatGPT\.app/Contents/MacOS/ChatGPT$"#,
                #"^/.*/ChatGPT\.app/Contents/Resources/ChatGPTHelper$"#,
                #"^/.*/ChatGPT\.app/Contents/Frameworks/ChatGPT Helper(?: \(GPU\)| \(Renderer\))?\.app/Contents/MacOS/ChatGPT Helper(?: \(GPU\)| \(Renderer\))?$"#
            ]
        case "ru.keepcoder.Telegram", "com.tdesktop.Telegram":
            return [
                #"^/.*/Telegram\.app/Contents/MacOS/Telegram$"#,
                #"^/.*/Telegram Desktop\.app/Contents/MacOS/Telegram Desktop$"#,
                #"^/.*/Telegram.*\.app/Contents/MacOS/(?:Telegram|Telegram Desktop|telegram-desktop)$"#
            ]
        case "com.google.Chrome":
            return [
                #"^/.*/Google Chrome\.app/Contents/MacOS/Google Chrome$"#,
                #"^/.*/Google Chrome\.app/Contents/Frameworks/Google Chrome Framework\.framework/.*/Helpers/Google Chrome Helper(?: \(GPU\)| \(Renderer\))?\.app/Contents/MacOS/Google Chrome Helper(?: \(GPU\)| \(Renderer\))?$"#
            ]
        case "com.apple.Safari":
            return [
                #"^/.*/Safari\.app/Contents/MacOS/Safari$"#,
                #"^/.*/WebKit\.framework/.*/XPCServices/com\.apple\.WebKit\.(?:Networking|WebContent|GPU)\.xpc/Contents/MacOS/com\.apple\.WebKit\.(?:Networking|WebContent|GPU)$"#,
                #"^/.*/SafariShared\.framework/.*/XPCServices/com\.apple\.Safari\.SearchHelper\.xpc/Contents/MacOS/com\.apple\.Safari\.SearchHelper$"#
            ]
        default:
            return []
        }
    }

    private static func outboundDictionary(for node: ProxyNode) -> [String: Any] {
        var outbound: [String: Any] = [
            "tag": "proxy",
            "type": node.protocolType,
            "server": node.server,
            "server_port": node.port
        ]

        if ["vless", "vmess", "tuic"].contains(node.protocolType), let uuid = node.uuid {
            outbound["uuid"] = uuid
        }

        if ["hysteria2", "tuic", "trojan"].contains(node.protocolType), let password = node.password {
            outbound["password"] = password
        }

        if node.protocolType == "vmess" {
            if let alterId = node.alterId {
                outbound["alter_id"] = alterId
            }
            outbound["security"] = node.vmessCipher ?? "auto"
        }

        if let flow = node.flow, !flow.isEmpty {
            outbound["flow"] = flow
        }

        if let security = node.security, security != "none" {
            var tls: [String: Any] = [
                "enabled": true,
                "server_name": node.sni as Any
            ]
            if let allowInsecure = node.allowInsecure {
                tls["insecure"] = allowInsecure
            }
            if let alpn = node.alpn, !alpn.isEmpty {
                tls["alpn"] = alpn
            }
            if let fingerprint = node.fingerprint, !fingerprint.isEmpty {
                tls["utls"] = [
                    "enabled": true,
                    "fingerprint": fingerprint
                ]
            }
            if security == "reality" {
                var reality: [String: Any] = [
                    "enabled": true
                ]
                if let publicKey = node.publicKey, !publicKey.isEmpty {
                    reality["public_key"] = publicKey
                }
                if let shortId = node.shortId, !shortId.isEmpty {
                    reality["short_id"] = shortId
                }
                tls["reality"] = reality
            }
            outbound["tls"] = tls
        }

        if let transport = node.transport {
            switch transport {
            case "ws":
                var ws = webSocketTransport(path: node.path ?? "/")
                if let wsHost = node.wsHost, !wsHost.isEmpty {
                    ws["headers"] = [
                        "Host": wsHost
                    ]
                }
                outbound["transport"] = ws
            case "grpc":
                outbound["transport"] = [
                    "type": "grpc",
                    "service_name": node.path ?? "grpc"
                ]
            default:
                break
            }
        }

        if node.udpOverTCP == true {
            outbound["udp_over_tcp"] = [
                "enabled": true
            ]
        }

        return outbound
    }

    private static func webSocketTransport(path rawPath: String) -> [String: Any] {
        let parsed = parseWebSocketPath(rawPath)
        var transport: [String: Any] = [
            "type": "ws",
            "path": parsed.path
        ]

        if let maxEarlyData = parsed.maxEarlyData {
            transport["max_early_data"] = maxEarlyData
            transport["early_data_header_name"] = parsed.earlyDataHeaderName ?? "Sec-WebSocket-Protocol"
        }

        return transport
    }

    private static func parseWebSocketPath(_ rawPath: String) -> (
        path: String,
        maxEarlyData: Int?,
        earlyDataHeaderName: String?
    ) {
        let normalizedPath = rawPath.isEmpty ? "/" : rawPath
        guard let questionIndex = normalizedPath.firstIndex(of: "?") else {
            return (normalizedPath, nil, nil)
        }

        let path = String(normalizedPath[..<questionIndex])
        let queryStart = normalizedPath.index(after: questionIndex)
        let query = String(normalizedPath[queryStart...])
        guard var components = URLComponents(string: "https://v2dex.local/?\(query)") else {
            return (normalizedPath, nil, nil)
        }

        let queryItems = components.queryItems ?? []
        let maxEarlyData = queryItems
            .first { $0.name.caseInsensitiveCompare("ed") == .orderedSame }?
            .value
            .flatMap(Int.init)
        guard let maxEarlyData, maxEarlyData > 0 else {
            return (normalizedPath, nil, nil)
        }

        let earlyDataHeaderName = queryItems
            .first { $0.name.caseInsensitiveCompare("eh") == .orderedSame }?
            .value
        let remainingItems = queryItems.filter {
            $0.name.caseInsensitiveCompare("ed") != .orderedSame
                && $0.name.caseInsensitiveCompare("eh") != .orderedSame
        }
        components.queryItems = remainingItems.isEmpty ? nil : remainingItems
        let remainingQuery = components.percentEncodedQuery
        let transportPath = remainingQuery.map { "\(path.isEmpty ? "/" : path)?\($0)" } ?? (path.isEmpty ? "/" : path)

        return (transportPath, maxEarlyData, earlyDataHeaderName)
    }
}
