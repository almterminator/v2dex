import Foundation
import Network

public enum ConnectivityTester {
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
                String(Int(timeout)),
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

    private static func runCurl(arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            let state = FinishState()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
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
                    continuation.resume(throwing: TestError.commandFailed(message.isEmpty ? "curl exited with code \(process.terminationStatus)." : message))
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
