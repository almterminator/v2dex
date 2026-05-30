import Foundation

public enum SingboxConfigBuilder {
    public static let localProxyHost = "127.0.0.1"
    public static let localProxyPort = 2080
    public static let tunAddress = "172.19.0.1/30"

    public static func build(node: ProxyNode, mode: TunnelMode, appRules: [AppRouteRule]) throws -> Data {
        let routeRules = mode == .perApp ? buildPerAppRouteRules(appRules: appRules) : []
        let useTun = mode == .full || (mode == .perApp && requiresTun(appRules: appRules))
        let finalOutbound = mode == .perApp && useTun ? "direct" : "proxy"

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
        appRules.contains { rule in
            rule.enabled && ["ru.keepcoder.Telegram", "com.tdesktop.Telegram"].contains(rule.bundleId)
        }
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
            "listen": localProxyHost,
            "listen_port": localProxyPort,
            "set_system_proxy": false
        ])

        return values
    }

    private static func buildPerAppRouteRules(appRules: [AppRouteRule]) -> [[String: Any]] {
        var routeRules: [[String: Any]] = []

        for rule in appRules where rule.enabled {
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
                var ws: [String: Any] = [
                    "type": "ws",
                    "path": node.path ?? "/"
                ]
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
}
