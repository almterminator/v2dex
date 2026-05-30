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
        let firstRule = try XCTUnwrap(rules.first)
        let processNames = try XCTUnwrap(firstRule["process_name"] as? [String])

        XCTAssertEqual(route["final"] as? String, "proxy")
        XCTAssertEqual(firstRule["outbound"] as? String, "proxy")
        XCTAssertTrue(processNames.contains("Google Chrome"))
        XCTAssertTrue(processNames.contains("Google Chrome Helper"))
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

    func testPerAppTelegramUsesTunWithDirectFallback() throws {
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

        XCTAssertTrue(inbounds.contains { ($0["type"] as? String) == "tun" })
        XCTAssertEqual(route["final"] as? String, "direct")
    }

    func testFullModeUsesTunWithProxyFallback() throws {
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

        XCTAssertTrue(inbounds.contains { ($0["type"] as? String) == "tun" })
        XCTAssertEqual(route["final"] as? String, "proxy")
    }
}
