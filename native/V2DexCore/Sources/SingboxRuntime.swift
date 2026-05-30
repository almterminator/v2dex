import Darwin
import Foundation

public final class SingboxRuntime: @unchecked Sendable {
    public static let shared = SingboxRuntime()
    private static let environmentBinaryKey = "V2DEX_SINGBOX_PATH"
    private static let sourceRepoBinaryPath: String = {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRootURL.appendingPathComponent(".local/bin/sing-box").path
    }()

    private let fileManager = FileManager.default
    private let stateQueue = DispatchQueue(label: "V2DexCore.SingboxRuntime")
    private var process: Process?
    private var binaryPath: String?
    private var activeConfigPath: String?
    private var lastError: String?
    private var lastConnectedAt: Date?
    private var connecting = false
    private var mode: TunnelMode = .full
    private var backend: RuntimeBackend = .systemProxy
    private var outputLog: [String] = []
    private var elevatedPID: Int32?
    private var elevatedLogPath: String?
    private var proxiedAppBundleIDs: [String] = []
    private var unsupportedPerAppBundleIDs: [String] = []
    private var proxyController = MacSystemProxyController()

    private init() {}

    public func resolveBinaryPath(explicitPath: String? = nil) -> String? {
        let resourcePath = Bundle.main.resourcePath.map { "\($0)/sing-box" }
        let localRepoBinary = fileManager.currentDirectoryPath + "/.local/bin/sing-box"
        let candidates = [
            explicitPath,
            ProcessInfo.processInfo.environment[Self.environmentBinaryKey],
            Bundle.main.path(forResource: "sing-box", ofType: nil),
            resourcePath,
            Self.sourceRepoBinaryPath,
            localRepoBinary,
            "/opt/homebrew/bin/sing-box",
            "/usr/local/bin/sing-box"
        ].compactMap { $0 }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    public func start(
        configData: Data,
        mode: TunnelMode,
        appRules: [AppRouteRule] = [],
        binaryPath explicitBinaryPath: String? = nil
    ) throws -> TunnelStatusSnapshot {
        try stopIfNeeded()

        guard let resolvedBinaryPath = resolveBinaryPath(explicitPath: explicitBinaryPath) else {
            throw SingboxRuntimeError.binaryNotFound(environmentKey: Self.environmentBinaryKey)
        }

        let configPath = try writeConfig(configData)
        let usesElevatedTun = configContainsTunInbound(configData)
        let elevatedLogPath = fileManager.temporaryDirectory
            .appendingPathComponent("v2dex-sing-box-\(UUID().uuidString).log")
            .path

        stateQueue.sync {
            self.connecting = true
            self.mode = mode
            self.lastError = nil
            self.binaryPath = resolvedBinaryPath
            self.activeConfigPath = configPath
            self.elevatedLogPath = usesElevatedTun ? elevatedLogPath : nil
            self.proxiedAppBundleIDs = []
            self.unsupportedPerAppBundleIDs = []
        }

        if usesElevatedTun {
            do {
                let pid = try launchElevatedSingbox(
                    binaryPath: resolvedBinaryPath,
                    configPath: configPath,
                    logPath: elevatedLogPath
                )
                try waitForProxyReady(elevatedPID: pid, logPath: elevatedLogPath)
                try proxyController.disableProxy()
                stateQueue.sync {
                    self.process = nil
                    self.elevatedPID = pid
                    self.connecting = false
                    self.lastConnectedAt = Date()
                    self.backend = .appProxy
                }
                return statusSnapshot()
            } catch {
                try? killElevatedSingbox()
                try? proxyController.disableProxy()
                stateQueue.sync {
                    self.connecting = false
                    self.elevatedPID = nil
                    self.elevatedLogPath = nil
                    self.lastError = error.localizedDescription
                }
                throw error
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedBinaryPath)
        process.arguments = ["run", "-c", configPath]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let outputHandler: (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else {
                return
            }
            self?.appendOutput(line)
        }

        stdout.fileHandleForReading.readabilityHandler = outputHandler
        stderr.fileHandleForReading.readabilityHandler = outputHandler

        process.terminationHandler = { [weak self] process in
            self?.stateQueue.sync {
                self?.process = nil
                self?.connecting = false
                if process.terminationStatus != 0 {
                    self?.lastError = "sing-box exited with code \(process.terminationStatus)"
                }
            }
        }

        do {
            try process.run()
            try waitForProxyReady(process: process)
            if mode == .full {
                try proxyController.enableProxy(
                    host: SingboxConfigBuilder.localProxyHost,
                    port: SingboxConfigBuilder.localProxyPort
                )
                let launchResult = try AppProxyLauncher.relaunchRunningEnvironmentProxyApps(
                    rules: appRules,
                    host: SingboxConfigBuilder.localProxyHost,
                    port: SingboxConfigBuilder.localProxyPort
                )
                stateQueue.sync {
                    self.proxiedAppBundleIDs = launchResult.launchedBundleIDs
                    self.unsupportedPerAppBundleIDs = launchResult.unsupportedBundleIDs
                }
            } else {
                try proxyController.disableProxy()
                let launchResult = try AppProxyLauncher.relaunchSelectedApps(
                    rules: appRules,
                    host: SingboxConfigBuilder.localProxyHost,
                    port: SingboxConfigBuilder.localProxyPort
                )
                stateQueue.sync {
                    self.proxiedAppBundleIDs = launchResult.launchedBundleIDs
                    self.unsupportedPerAppBundleIDs = launchResult.unsupportedBundleIDs
                }
            }
            stateQueue.sync {
                self.process = process
                self.connecting = false
                self.lastConnectedAt = Date()
                self.backend = mode == .full ? .systemProxy : .appProxy
            }
            return statusSnapshot()
        } catch {
            process.terminate()
            let proxiedApps = stateQueue.sync { self.proxiedAppBundleIDs }
            if !proxiedApps.isEmpty {
                try? AppProxyLauncher.relaunchAppsWithoutProxy(bundleIdentifiers: proxiedApps)
            }
            try? proxyController.disableProxy()
            stateQueue.sync {
                self.connecting = false
                self.proxiedAppBundleIDs = []
                self.lastError = error.localizedDescription
            }
            throw error
        }
    }

    public func stopIfNeeded() throws {
        let (process, elevatedPID, proxiedApps) = stateQueue.sync { (self.process, self.elevatedPID, self.proxiedAppBundleIDs) }
        var cleanupErrors: [String] = []

        guard let process else {
            if elevatedPID != nil {
                do {
                    try killElevatedSingbox()
                } catch {
                    cleanupErrors.append(error.localizedDescription)
                }
            }
            if !proxiedApps.isEmpty {
                do {
                    try AppProxyLauncher.relaunchAppsWithoutProxy(bundleIdentifiers: proxiedApps)
                } catch {
                    cleanupErrors.append(error.localizedDescription)
                }
            }
            do {
                try proxyController.disableProxy()
            } catch {
                cleanupErrors.append(error.localizedDescription)
            }
            stateQueue.sync {
                self.proxiedAppBundleIDs = []
                self.elevatedPID = nil
                self.elevatedLogPath = nil
            }
            if !cleanupErrors.isEmpty {
                throw SingboxRuntimeError.cleanupFailed(reason: cleanupErrors.joined(separator: "\n"))
            }
            return
        }

        if !proxiedApps.isEmpty {
            do {
                try AppProxyLauncher.relaunchAppsWithoutProxy(bundleIdentifiers: proxiedApps)
            } catch {
                cleanupErrors.append(error.localizedDescription)
            }
        }
        do {
            try proxyController.disableProxy()
        } catch {
            cleanupErrors.append(error.localizedDescription)
        }
        process.terminate()
        stateQueue.sync {
            self.process = nil
            self.elevatedPID = nil
            self.elevatedLogPath = nil
            self.connecting = false
            self.proxiedAppBundleIDs = []
            self.unsupportedPerAppBundleIDs = []
        }
        if !cleanupErrors.isEmpty {
            throw SingboxRuntimeError.cleanupFailed(reason: cleanupErrors.joined(separator: "\n"))
        }
    }

    public func statusSnapshot() -> TunnelStatusSnapshot {
        stateQueue.sync {
            TunnelStatusSnapshot(
                connected: process?.isRunning == true || elevatedPID.map(isPIDRunning(_:)) == true,
                connecting: connecting,
                mode: mode,
                backend: backend,
                lastError: lastError,
                lastConnectedAt: lastConnectedAt,
                binaryPath: binaryPath,
                activeConfigPath: activeConfigPath,
                proxyHost: SingboxConfigBuilder.localProxyHost,
                proxyPort: SingboxConfigBuilder.localProxyPort
            )
        }
    }

    public func recentOutput(limit: Int = 80) -> [String] {
        stateQueue.sync {
            Array(outputLog.suffix(limit))
        }
    }

    private func writeConfig(_ data: Data) throws -> String {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("v2dex-runtime", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("sing-box-\(UUID().uuidString).json")
        try data.write(to: configURL, options: .atomic)
        return configURL.path
    }

    private func appendOutput(_ string: String) {
        stateQueue.sync {
            outputLog.append(contentsOf: string.split(separator: "\n").map(String.init))
            if outputLog.count > 500 {
                outputLog.removeFirst(outputLog.count - 500)
            }
        }
    }

    private func configContainsTunInbound(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = object["inbounds"] as? [[String: Any]] else {
            return false
        }

        return inbounds.contains { inbound in
            (inbound["type"] as? String) == "tun"
        }
    }

    private func launchElevatedSingbox(binaryPath: String, configPath: String, logPath: String) throws -> Int32 {
        let command = [
            shellQuote(binaryPath),
            "run",
            "-c",
            shellQuote(configPath),
            "</dev/null",
            ">",
            shellQuote(logPath),
            "2>&1",
            "&",
            "echo $!"
        ].joined(separator: " ")
        let output = try runAdministratorShell(command)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let pid = Int32(output.split(separator: "\n").last ?? "") else {
            throw SingboxRuntimeError.proxyStartupFailed(reason: "Could not parse elevated sing-box PID: \(output)")
        }

        return pid
    }

    private func killElevatedSingbox() throws {
        guard let pid = stateQueue.sync(execute: { self.elevatedPID }) else {
            return
        }

        if isPIDRunning(pid) {
            _ = try? runAdministratorShell("kill -TERM \(pid)")
            Thread.sleep(forTimeInterval: 0.5)
        }

        if isPIDRunning(pid) {
            _ = try runAdministratorShell("kill -KILL \(pid)")
        }
    }

    private func runAdministratorShell(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw SingboxRuntimeError.elevatedCommandFailed(reason: errorOutput.isEmpty ? output : errorOutput)
        }

        return output
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func waitForProxyReady(process: Process, timeout: TimeInterval = 6) throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if process.isRunning == false {
                let logTail = recentOutput(limit: 20).joined(separator: "\n")
                throw SingboxRuntimeError.proxyStartupFailed(
                    reason: logTail.isEmpty ? "sing-box exited before opening the local proxy port." : logTail
                )
            }

            if isLocalProxyReachable() {
                return
            }

            Thread.sleep(forTimeInterval: 0.2)
        }

        let logTail = recentOutput(limit: 20).joined(separator: "\n")
        throw SingboxRuntimeError.proxyStartupFailed(
            reason: logTail.isEmpty ? "Timed out waiting for the local proxy listener on 127.0.0.1:2080." : logTail
        )
    }

    private func waitForProxyReady(elevatedPID: Int32, logPath: String, timeout: TimeInterval = 8) throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !isPIDRunning(elevatedPID) {
                let logTail = readLogTail(path: logPath)
                throw SingboxRuntimeError.proxyStartupFailed(
                    reason: logTail.isEmpty ? "elevated sing-box exited before opening the local proxy port." : logTail
                )
            }

            if isLocalProxyReachable() {
                appendOutput(readLogTail(path: logPath))
                return
            }

            Thread.sleep(forTimeInterval: 0.2)
        }

        let logTail = readLogTail(path: logPath)
        throw SingboxRuntimeError.proxyStartupFailed(
            reason: logTail.isEmpty ? "Timed out waiting for elevated sing-box on 127.0.0.1:2080." : logTail
        )
    }

    private func isPIDRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private func readLogTail(path: String, lineLimit: Int = 40) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }

        return text
            .split(separator: "\n")
            .suffix(lineLimit)
            .joined(separator: "\n")
    }

    private func isLocalProxyReachable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = [
            "-z",
            "-G",
            "1",
            SingboxConfigBuilder.localProxyHost,
            String(SingboxConfigBuilder.localProxyPort)
        ]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

public enum SingboxRuntimeError: LocalizedError {
    case binaryNotFound(environmentKey: String)
    case proxyStartupFailed(reason: String)
    case cleanupFailed(reason: String)
    case elevatedCommandFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(environmentKey):
            return """
            sing-box binary was not found. Bundle it into the app resources, install it at /opt/homebrew/bin/sing-box or /usr/local/bin/sing-box, or set \(environmentKey) to the executable path.
            """
        case let .proxyStartupFailed(reason):
            return "Local proxy did not become ready. \(reason)"
        case let .cleanupFailed(reason):
            return "Proxy cleanup did not complete successfully. \(reason)"
        case let .elevatedCommandFailed(reason):
            return "Administrator permission for TUN mode failed. \(reason)"
        }
    }
}
