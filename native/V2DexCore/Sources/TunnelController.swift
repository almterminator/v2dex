import Foundation
import NetworkExtension
#if canImport(AppKit)
import AppKit
#endif

public final class TunnelController {
    public static let shared = TunnelController()
    public var providerBundleIdentifier: String {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            return "\(bundleIdentifier).PacketTunnel"
        }
        return "com.alireza.v2dex.PacketTunnel"
    }
    private let managerDescription = "V2Dex Per-App VPN"

    private init() {}

    public func loadManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: { $0.localizedDescription == managerDescription }) {
            return existing
        }

        let manager = NETunnelProviderManager.forPerAppVPN()
        manager.localizedDescription = managerDescription
        manager.protocolConfiguration = NETunnelProviderProtocol()
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        return manager
    }

    public func startTunnel(
        configurationJSON: String,
        appRules: [AppRouteRule],
        binaryPath: String? = nil
    ) async throws {
        let manager = try await loadManager()
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            throw TunnelControllerError.invalidProtocolConfiguration
        }

        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = "V2Dex"
        proto.providerConfiguration = [
            "singboxConfig": configurationJSON,
            "singboxBinaryPath": binaryPath as Any
        ]

        manager.protocolConfiguration = proto
        manager.appRules = try makeAppRules(from: appRules)
        manager.safariDomains = appRules.contains(where: { $0.enabled && $0.bundleId == "com.apple.Safari" }) ? [""] : []
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()
    }

    public func stopTunnel() async throws {
        let manager = try await loadManager()
        manager.connection.stopVPNTunnel()
    }

    public func connectionStatus() async throws -> NEVPNStatus {
        let manager = try await loadManager()
        return manager.connection.status
    }

    public func statusSnapshot(lastError: String? = nil) async throws -> TunnelStatusSnapshot {
        let status = try await connectionStatus()
        return TunnelStatusSnapshot(
            connected: status == .connected,
            connecting: status == .connecting || status == .reasserting,
            mode: .perApp,
            backend: .appProxy,
            lastError: lastError,
            lastConnectedAt: nil,
            binaryPath: nil,
            activeConfigPath: nil,
            proxyHost: nil,
            proxyPort: nil
        )
    }

    private func makeAppRules(from rules: [AppRouteRule]) throws -> [NEAppRule] {
        let enabledBundleIDs = Array(Set(rules.filter(\.enabled).map(\.bundleId))).sorted()
        return try enabledBundleIDs.compactMap { bundleID in
            guard bundleID != "com.apple.Safari" else {
                return try appRule(for: bundleID)
            }
            return try appRule(for: bundleID)
        }
    }

    private func appRule(for bundleIdentifier: String) throws -> NEAppRule {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw TunnelControllerError.applicationNotFound(bundleIdentifier: bundleIdentifier)
        }

        let requirement = try designatedRequirement(forApplicationAt: appURL)
        let rule = NEAppRule(signingIdentifier: bundleIdentifier, designatedRequirement: requirement)
        rule.matchPath = appURL.path
        return rule
    }

    private func designatedRequirement(forApplicationAt appURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dr", "-", appURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let merged = [output, errorOutput].joined(separator: "\n")

        guard process.terminationStatus == 0 || merged.contains("designated =>") else {
            throw TunnelControllerError.designatedRequirementLookupFailed(
                applicationPath: appURL.path,
                message: merged.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        for line in merged.split(separator: "\n") {
            guard let range = line.range(of: "designated =>") else {
                continue
            }
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw TunnelControllerError.designatedRequirementLookupFailed(
            applicationPath: appURL.path,
            message: "codesign did not return a designated requirement"
        )
    }
}

public enum TunnelControllerError: LocalizedError {
    case invalidProtocolConfiguration
    case applicationNotFound(bundleIdentifier: String)
    case designatedRequirementLookupFailed(applicationPath: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidProtocolConfiguration:
            return "The packet tunnel protocol configuration is invalid."
        case let .applicationNotFound(bundleIdentifier):
            return "Could not find installed application for bundle identifier \(bundleIdentifier)."
        case let .designatedRequirementLookupFailed(applicationPath, message):
            return "Could not read designated requirement for \(applicationPath): \(message)"
        }
    }
}
