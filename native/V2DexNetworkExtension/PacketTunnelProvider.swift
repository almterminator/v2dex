import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let environmentBinaryKey = "V2DEX_SINGBOX_PATH"
    private var singboxProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard
            let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
            let singboxConfig = providerConfig["singboxConfig"] as? String
        else {
            completionHandler(PacketTunnelError.missingConfiguration)
            return
        }

        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "240.0.0.2")
        networkSettings.mtu = 9000 as NSNumber

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        networkSettings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        networkSettings.dnsSettings = dns

        setTunnelNetworkSettings(networkSettings) { [weak self] error in
            guard error == nil else {
                completionHandler(error)
                return
            }

            do {
                try self?.launchSingbox(
                    with: singboxConfig,
                    binaryPath: providerConfig["singboxBinaryPath"] as? String
                )
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        singboxProcess?.terminate()
        singboxProcess = nil
        stdoutPipe = nil
        stderrPipe = nil
        completionHandler()
    }

    private func launchSingbox(with configuration: String, binaryPath: String?) throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let configURL = tempDirectory.appendingPathComponent("sing-box.json")
        try configuration.write(to: configURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolveBinaryPath(binaryPath))
        process.arguments = ["run", "-c", configURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else {
                return
            }
            NSLog("%@", line)
        }
        stderr.fileHandleForReading.readabilityHandler = stdout.fileHandleForReading.readabilityHandler

        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        singboxProcess = process
        stdoutPipe = stdout
        stderrPipe = stderr
    }

    private func resolveBinaryPath(_ configuredPath: String?) -> String {
        let resourcePath = Bundle.main.resourcePath.map { "\($0)/sing-box" }
        let localRepoBinary = FileManager.default.currentDirectoryPath + "/.local/bin/sing-box"
        let candidates = [
            configuredPath,
            Bundle.main.path(forResource: "sing-box", ofType: nil),
            ProcessInfo.processInfo.environment[Self.environmentBinaryKey],
            resourcePath,
            localRepoBinary,
            "/opt/homebrew/bin/sing-box",
            "/usr/local/bin/sing-box"
        ].compactMap { $0 }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return configuredPath ?? "/usr/local/bin/sing-box"
    }
}

enum PacketTunnelError: Error {
    case missingConfiguration
}
