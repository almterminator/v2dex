import Foundation
import Network

public enum ConnectivityTester {
    public static func testEndpointPing(to node: ProxyNode, timeout: TimeInterval = 1.5) async throws -> Int {
        do {
            return try await testICMPPing(host: node.server, timeout: timeout)
        } catch {
            return max(try await testTCPConnection(to: node, timeout: min(timeout, 1.5)), 12)
        }
    }

    public static func testProxyHTTPProbe(
        to node: ProxyNode,
        binaryPath explicitBinaryPath: String? = nil,
        timeout: TimeInterval = 20
    ) async throws -> TunnelHTTPProbeResult {
        guard let binaryPath = SingboxRuntime.shared.resolveBinaryPath(explicitPath: explicitBinaryPath) else {
            throw SingboxRuntimeError.binaryNotFound(environmentKey: "V2DEX_SINGBOX_PATH")
        }

        let proxyPort = randomLocalPort()
        let configData = try buildProbeConfig(node: node, proxyPort: proxyPort)
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2dex-probe-\(UUID().uuidString).json")
        try configData.write(to: configURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: configURL) }

        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["run", "-c", configURL.path]
        process.standardOutput = output
        process.standardError = errorOutput
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            try await waitForTCPPort(
                host: SingboxConfigBuilder.loopbackProxyHost,
                port: proxyPort,
                timeout: min(max(timeout, 2.0), 3.0)
            )

            var lastError: Error?
            let urlsToTry = timeout <= 2.5 ? Array(probeURLs.prefix(2)) : probeURLs
            for url in urlsToTry {
                guard !Task.isCancelled else { throw TestError.cancelled }
                do {
                    return try await testHTTPViaLocalProxy(
                        url: url,
                        proxyHost: SingboxConfigBuilder.loopbackProxyHost,
                        proxyPort: proxyPort,
                        timeout: timeout
                    )
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? TestError.timeout
        } catch {
            if !process.isRunning {
                let stderr = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stderr.isEmpty {
                    throw TestError.commandFailed(stderr)
                }
            }
            throw error
        }
    }

    public static func testXrayHTTPProbe(
        to node: ProxyNode,
        binaryPath explicitBinaryPath: String? = nil,
        timeout: TimeInterval = 2.5
    ) async throws -> TunnelHTTPProbeResult {
        guard let binaryPath = SingboxRuntime.shared.resolveXrayBinaryPath(explicitPath: explicitBinaryPath) else {
            throw SingboxRuntimeError.binaryNotFound(environmentKey: "V2DEX_XRAY_PATH")
        }

        let httpPort = randomLocalPort()
        let socksPort = randomLocalPort(excluding: httpPort)
        let configData = try XrayConfigBuilder.build(node: node, httpPort: httpPort, socksPort: socksPort)
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2dex-xray-probe-\(UUID().uuidString).json")
        try configData.write(to: configURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: configURL) }

        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["run", "-config", configURL.path]
        process.standardOutput = output
        process.standardError = errorOutput
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            try await waitForTCPPort(
                host: SingboxConfigBuilder.loopbackProxyHost,
                port: socksPort,
                timeout: min(max(timeout, 1.0), 2.0)
            )

            var lastError: Error?
            for url in Array(probeURLs.prefix(3)) {
                guard !Task.isCancelled else { throw TestError.cancelled }
                do {
                    return try await testHTTPViaLocalProxy(
                        url: url,
                        proxyHost: SingboxConfigBuilder.loopbackProxyHost,
                        proxyPort: socksPort,
                        timeout: timeout
                    )
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? TestError.timeout
        } catch {
            if !process.isRunning {
                let stderr = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stderr.isEmpty {
                    throw TestError.commandFailed(stderr)
                }
            }
            throw error
        }
    }

    public static func testTCPConnection(to node: ProxyNode, timeout: TimeInterval = 6) async throws -> Int {
        let startedAt = Date()
        let port = NWEndpoint.Port(integerLiteral: UInt16(node.port))
        let connection = NWConnection(host: NWEndpoint.Host(node.server), port: port, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "V2DexCore.ConnectivityTester")
            let state = FinishState()

            @Sendable func finish(_ result: Result<Int, Error>) {
                guard state.beginFinish() else { return }
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let latency = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
                    finish(.success(latency))
                case let .failed(error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(TestError.cancelled))
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(TestError.timeout))
            }

            connection.start(queue: queue)
        }
    }

    private static func testICMPPing(host: String, timeout: TimeInterval) async throws -> Int {
        let output = try await runCommand(
            path: "/sbin/ping",
            arguments: [
                "-c",
                "1",
                "-W",
                String(Int((timeout * 1000).rounded())),
                host
            ],
            timeout: timeout + 0.5
        )
        guard let latency = parsePingLatency(output) else {
            throw TestError.commandFailed("Could not parse ping latency.")
        }
        return latency
    }

    private static func parsePingLatency(_ output: String) -> Int? {
        guard let range = output.range(of: "time=") else { return nil }
        let suffix = output[range.upperBound...]
        let value = suffix.prefix { character in
            character.isNumber || character == "."
        }
        guard let latency = Double(value) else { return nil }
        return max(Int(latency.rounded()), 1)
    }

    public static func testHTTPViaLocalProxy(
        url: String,
        proxyHost: String,
        proxyPort: Int,
        timeout: TimeInterval = 15
    ) async throws -> TunnelHTTPProbeResult {
        let startedAt = Date()
        let response = try await runCurl(
            arguments: [
                "--silent",
                "--show-error",
                "--output",
                "/dev/null",
                "--write-out",
                "%{http_code}",
                "--max-time",
                String(format: "%.2f", timeout),
                "--proxy",
                "socks5h://\(proxyHost):\(proxyPort)",
                url
            ],
            timeout: timeout + 1
        )
        let status = Int(response.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        guard (200...399).contains(status) else {
            throw TestError.httpStatus(status)
        }

        return TunnelHTTPProbeResult(
            latencyMs: max(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()), 1),
            url: url
        )
    }

    public static func testHTTPReachabilityViaLocalProxy(
        url: String,
        proxyHost: String,
        proxyPort: Int,
        timeout: TimeInterval = 15
    ) async throws -> TunnelHTTPProbeResult {
        let startedAt = Date()
        let response = try await runCurl(
            arguments: [
                "--silent",
                "--show-error",
                "--head",
                "--output",
                "/dev/null",
                "--write-out",
                "%{http_code}",
                "--max-time",
                String(format: "%.2f", timeout),
                "--proxy",
                "socks5h://\(proxyHost):\(proxyPort)",
                url
            ],
            timeout: timeout + 1
        )
        let status = Int(response.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        guard (100...499).contains(status) else {
            throw TestError.httpStatus(status)
        }

        return TunnelHTTPProbeResult(
            latencyMs: max(Int((Date().timeIntervalSince(startedAt) * 1000).rounded()), 1),
            url: url
        )
    }

    public static func fetchTextViaLocalProxy(
        url: String,
        proxyHost: String,
        proxyPort: Int,
        timeout: TimeInterval = 15
    ) async throws -> String {
        try await runCurl(
            arguments: [
                "--silent",
                "--show-error",
                "--max-time",
                String(Int(timeout)),
                "--proxy",
                "socks5h://\(proxyHost):\(proxyPort)",
                url
            ],
            timeout: timeout + 1
        )
    }

    public static func fetchTextDirect(url: String, timeout: TimeInterval = 5) async throws -> String {
        try await runCurl(
            arguments: [
                "--silent",
                "--show-error",
                "--max-time",
                String(format: "%.2f", timeout),
                url
            ],
            timeout: timeout + 1
        )
    }

    private static func runCurl(arguments: [String], timeout: TimeInterval) async throws -> String {
        try await runCommand(path: "/usr/bin/curl", arguments: arguments, timeout: timeout)
    }

    private static func runCommand(path: String, arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            let state = FinishState()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errorOutput
            process.terminationHandler = { process in
                guard state.beginFinish() else { return }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } else {
                    let message = String(decoding: errorData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let commandName = URL(fileURLWithPath: path).lastPathComponent
                    continuation.resume(throwing: TestError.commandFailed(message.isEmpty ? "\(commandName) exited with code \(process.terminationStatus)." : message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard state.beginFinish() else { return }
                process.terminate()
                continuation.resume(throwing: TestError.timeout)
            }
        }
    }

    private static let probeURLs = [
        "https://www.youtube.com/generate_204",
        "https://www.gstatic.com/generate_204",
        "https://cp.cloudflare.com/generate_204",
        "http://cp.cloudflare.com/generate_204",
        "https://www.google.com/generate_204"
    ]

    private static func randomLocalPort(excluding excludedPort: Int? = nil) -> Int {
        var port = Int.random(in: 25000...45000)
        while port == excludedPort {
            port = Int.random(in: 25000...45000)
        }
        return port
    }

    private static func buildProbeConfig(node: ProxyNode, proxyPort: Int) throws -> Data {
        let data = try SingboxConfigBuilder.build(node: node, mode: .full, appRules: [])
        guard var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        config["inbounds"] = [
            [
                "type": "mixed",
                "tag": "mixed-in",
                "listen": SingboxConfigBuilder.loopbackProxyHost,
                "listen_port": proxyPort,
                "set_system_proxy": false
            ]
        ]

        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    private static func waitForTCPPort(host: String, port: Int, timeout: TimeInterval = 6) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        while Date() < deadline {
            do {
                _ = try await testTCPConnection(
                    to: ProxyNode(
                        id: "probe",
                        name: "Probe",
                        protocolType: "tcp",
                        server: host,
                        port: port,
                        security: nil,
                        transport: nil,
                        sni: nil,
                        path: nil
                    ),
                    timeout: 1
                )
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        throw lastError ?? TestError.timeout
    }

    enum TestError: LocalizedError {
        case timeout
        case cancelled
        case httpStatus(Int)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "Connection timed out."
            case .cancelled:
                return "Connection was cancelled."
            case let .httpStatus(status):
                return "HTTP probe failed with status \(status)."
            case let .commandFailed(message):
                return message
            }
        }
    }
}

public struct TunnelHTTPProbeResult: Codable {
    public let latencyMs: Int
    public let url: String
}

private final class FinishState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func beginFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else {
            return false
        }
        finished = true
        return true
    }
}
