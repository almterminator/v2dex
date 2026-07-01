import XCTest
@testable import V2DexCore

final class SmokeTests: XCTestCase {
    func testPerAppConfigRoutesOnlySelectedProcessesThroughProxy() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(
            node: node,
            mode: .perApp,
            appRules: [
                AppRouteRule(bundleId: "com.google.Chrome", name: "Chrome", processName: "Google Chrome", enabled: true)
            ]
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let route = try XCTUnwrap(json["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let processRule = try XCTUnwrap(rules.first { $0["process_name"] != nil })
        let processNames = try XCTUnwrap(processRule["process_name"] as? [String])

        XCTAssertEqual(route["final"] as? String, "proxy")
        XCTAssertEqual(processRule["action"] as? String, "route")
        XCTAssertEqual(processRule["outbound"] as? String, "proxy")
        XCTAssertTrue(processNames.contains("Google Chrome"))
        XCTAssertTrue(processNames.contains("Google Chrome Helper"))
    }

    func testSingboxConfigIncludesPerformanceDefaults() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(node: node, mode: .full, appRules: [])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let log = try XCTUnwrap(json["log"] as? [String: Any])
        let dns = try XCTUnwrap(json["dns"] as? [String: Any])
        let route = try XCTUnwrap(json["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let outbounds = try XCTUnwrap(json["outbounds"] as? [[String: Any]])
        let proxy = try XCTUnwrap(outbounds.first { $0["tag"] as? String == "proxy" })

        XCTAssertEqual(log["level"] as? String, "warn")
        XCTAssertEqual(dns["strategy"] as? String, "prefer_ipv4")
        XCTAssertNotNil(route["default_domain_resolver"])
        XCTAssertTrue(rules.contains { $0["action"] as? String == "resolve" })
        XCTAssertTrue(rules.contains { $0["action"] as? String == "sniff" })
        XCTAssertEqual(proxy["tcp_fast_open"] as? Bool, true)
        XCTAssertEqual(proxy["udp_fragment"] as? Bool, true)
        XCTAssertNotNil(proxy["domain_resolver"])
    }

    func testPerAppConfigKeepsLocalProxyInboundOnProxyOutbound() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(
            node: node,
            mode: .perApp,
            appRules: [
                AppRouteRule(bundleId: "com.openai.codex", name: "Codex", processName: "Codex", enabled: true)
            ]
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let route = try XCTUnwrap(json["route"] as? [String: Any])

        XCTAssertEqual(route["final"] as? String, "proxy")
    }

    func testPerAppConfigIncludesCodexProcessPathRegexes() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(
            node: node,
            mode: .perApp,
            appRules: [
                AppRouteRule(bundleId: "com.openai.codex", name: "Codex", processName: "Codex", enabled: true)
            ]
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let route = try XCTUnwrap(json["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let regexRule = try XCTUnwrap(rules.first(where: { $0["process_path_regex"] != nil }))
        let regexes = try XCTUnwrap(regexRule["process_path_regex"] as? [String])

        XCTAssertTrue(regexes.contains(#"^/.*/Codex\.app/Contents/Resources/codex$"#))
        XCTAssertTrue(regexes.contains(#"^/.*/Codex\.app/Contents/Resources/node_repl$"#))
    }

    func testPerAppTelegramDoesNotRequireTunOrAdminPrivileges() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(
            node: node,
            mode: .perApp,
            appRules: [
                AppRouteRule(bundleId: "ru.keepcoder.Telegram", name: "Telegram", processName: "Telegram", enabled: true)
            ]
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbounds = try XCTUnwrap(json["inbounds"] as? [[String: Any]])
        let route = try XCTUnwrap(json["route"] as? [String: Any])
        XCTAssertFalse(inbounds.contains { ($0["type"] as? String) == "tun" })
        XCTAssertEqual(route["final"] as? String, "proxy")
    }

    func testFullModeUsesLocalProxyInboundForSystemProxy() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(node: node, mode: .full, appRules: [])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbounds = try XCTUnwrap(json["inbounds"] as? [[String: Any]])
        let route = try XCTUnwrap(json["route"] as? [String: Any])

        XCTAssertFalse(inbounds.contains { ($0["type"] as? String) == "tun" })
        XCTAssertTrue(inbounds.contains { ($0["type"] as? String) == "mixed" })
        XCTAssertEqual(route["final"] as? String, "proxy")
    }

    func testFullModeWithTelegramDoesNotRequireTunOrAdminPrivileges() throws {
        let node = ProxyNode(
            id: "1",
            name: "Node",
            protocolType: "vless",
            server: "example.invalid",
            port: 443,
            security: "tls",
            transport: "ws",
            sni: nil,
            path: "/"
        )

        let data = try SingboxConfigBuilder.build(
            node: node,
            mode: .full,
            appRules: [
                AppRouteRule(bundleId: "com.google.Chrome", name: "Chrome", processName: "Google Chrome", enabled: true),
                AppRouteRule(bundleId: "ru.keepcoder.Telegram", name: "Telegram", processName: "Telegram", enabled: true)
            ]
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbounds = try XCTUnwrap(json["inbounds"] as? [[String: Any]])
        let route = try XCTUnwrap(json["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])

        XCTAssertFalse(inbounds.contains { ($0["type"] as? String) == "tun" })
        XCTAssertEqual(route["final"] as? String, "proxy")
        XCTAssertTrue(rules.contains { rule in
            guard let processNames = rule["process_name"] as? [String] else {
                return false
            }
            return processNames.contains("Telegram") && (rule["outbound"] as? String) == "proxy"
        })
        XCTAssertFalse(rules.contains { rule in
            guard let processNames = rule["process_name"] as? [String] else {
                return false
            }
            return processNames.contains("Google Chrome")
        })
    }

    func testImportsVLESSWebSocketUriWithEncodedQueryInPath() async throws {
        let raw = "vless://6abf5757-ba4d-4737-a67d-5aae28a08e05@104.16.74.34:2096?encryption=none&host=still-sea-119b.karoos12345.workers.dev&type=ws&security=tls&path=%2FeyJqdW5rIjoieUViT1JmTTIiLCJwcm90b2NvbCI6InZsIiwibW9kZSI6InByb3h5aXAiLCJwYW5lbElQcyI6W119%3Fed%3D2560&sni=StILl-SEa-119b.KArOos12345.WoRKERs.dev&fp=chrome&alpn=http%2F1.1#%252525F0%2525259F%25252592%252525A6%2525252012%25252520-%25252520VLESS%25252520-%25252520IPv4%25252520:%252525202096"

        let nodes = try await SubscriptionImporter.importRaw(raw)
        let node = try XCTUnwrap(nodes.first)

        XCTAssertEqual(node.protocolType, "vless")
        XCTAssertEqual(node.name, "\u{1F4A6} 12 - VLESS - IPv4 : 2096")
        XCTAssertEqual(node.server, "104.16.74.34")
        XCTAssertEqual(node.port, 2096)
        XCTAssertEqual(node.uuid, "6abf5757-ba4d-4737-a67d-5aae28a08e05")
        XCTAssertEqual(node.security, "tls")
        XCTAssertEqual(node.transport, "ws")
        XCTAssertEqual(node.wsHost, "still-sea-119b.karoos12345.workers.dev")
        XCTAssertEqual(node.sni, "StILl-SEa-119b.KArOos12345.WoRKERs.dev")
        XCTAssertEqual(node.fingerprint, "chrome")
        XCTAssertEqual(node.alpn, ["http/1.1"])
        XCTAssertEqual(
            node.path,
            "/eyJqdW5rIjoieUViT1JmTTIiLCJwcm90b2NvbCI6InZsIiwibW9kZSI6InByb3h5aXAiLCJwYW5lbElQcyI6W119?ed=2560"
        )

        let data = try SingboxConfigBuilder.build(node: node, mode: .full, appRules: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outbounds = try XCTUnwrap(json["outbounds"] as? [[String: Any]])
        let proxy = try XCTUnwrap(outbounds.first { $0["tag"] as? String == "proxy" })
        let tls = try XCTUnwrap(proxy["tls"] as? [String: Any])
        let transport = try XCTUnwrap(proxy["transport"] as? [String: Any])
        let headers = try XCTUnwrap(transport["headers"] as? [String: String])

        XCTAssertEqual(tls["server_name"] as? String, "StILl-SEa-119b.KArOos12345.WoRKERs.dev")
        XCTAssertEqual(
            transport["path"] as? String,
            "/eyJqdW5rIjoieUViT1JmTTIiLCJwcm90b2NvbCI6InZsIiwibW9kZSI6InByb3h5aXAiLCJwYW5lbElQcyI6W119"
        )
        XCTAssertEqual(transport["max_early_data"] as? Int, 2560)
        XCTAssertEqual(transport["early_data_header_name"] as? String, "Sec-WebSocket-Protocol")
        XCTAssertEqual(headers["Host"], "still-sea-119b.karoos12345.workers.dev")
    }
}
