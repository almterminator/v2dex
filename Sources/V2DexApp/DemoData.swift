import Foundation
import V2DexCore

enum DemoData {
    static let profiles: [ProfileSummary] = [
        .init(
            id: "primary",
            title: "Primary Reality Cluster",
            source: "Subscription",
            updatedAt: Date(),
            trafficUsedGB: 128,
            trafficTotalGB: 300,
            nodes: [
                ProxyNode(
                    id: "tokyo",
                    name: "Tokyo Low-Latency",
                    protocolType: "vless",
                    server: "tokyo-01.example.invalid",
                    port: 443,
                    security: "reality",
                    transport: "grpc",
                    sni: "cdn.example.invalid",
                    path: "proxy"
                ),
                ProxyNode(
                    id: "frankfurt",
                    name: "Frankfurt Fallback",
                    protocolType: "hysteria2",
                    server: "fra-02.example.invalid",
                    port: 8443,
                    security: "tls",
                    transport: "ws",
                    sni: "fra.example.invalid",
                    path: "/edge"
                )
            ]
        )
    ]

    static let appRules: [AppRuleViewModel] = [
        .init(bundleId: "com.google.Chrome", name: "Google Chrome", processName: "Google Chrome", enabled: true),
        .init(bundleId: "ru.keepcoder.Telegram", name: "Telegram", processName: "Telegram", enabled: true),
        .init(bundleId: "com.microsoft.VSCode", name: "Visual Studio Code", processName: "Code", enabled: false),
        .init(bundleId: "com.valvesoftware.steam", name: "Steam", processName: "steam_osx", enabled: false)
    ]
}
