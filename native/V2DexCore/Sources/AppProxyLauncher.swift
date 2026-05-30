import AppKit
import Foundation

struct AppProxyLaunchResult {
    let launchedBundleIDs: [String]
    let unsupportedBundleIDs: [String]
}

enum AppProxyLauncher {
    private static let openToolPath = "/usr/bin/open"
    private static let chromiumProxyArguments = [
        "--proxy-bypass-list=<-loopback>",
        "--disable-quic",
        "--origin-to-force-quic-on=",
    ]
    private static let environmentProxyBundleIDs: Set<String> = [
        "ru.keepcoder.Telegram",
        "com.tdesktop.Telegram"
    ]

    static func relaunchSelectedApps(
        rules: [AppRouteRule],
        host: String,
        port: Int
    ) throws -> AppProxyLaunchResult {
        let enabledBundleIDs = rules
            .filter(\.enabled)
            .map(\.bundleId)

        var launchedBundleIDs: [String] = []
        var unsupportedBundleIDs: [String] = []

        for bundleID in enabledBundleIDs {
            guard isRunning(bundleIdentifier: bundleID) else {
                continue
            }

            guard supportsProxyArgument(bundleIdentifier: bundleID) else {
                unsupportedBundleIDs.append(bundleID)
                continue
            }

            try terminateRunningApps(bundleIdentifier: bundleID)
            try launchApp(
                bundleIdentifier: bundleID,
                arguments: proxyArguments(host: host, port: port, bundleIdentifier: bundleID),
                proxyHost: host,
                proxyPort: port
            )
            launchedBundleIDs.append(bundleID)
        }

        return AppProxyLaunchResult(
            launchedBundleIDs: launchedBundleIDs,
            unsupportedBundleIDs: unsupportedBundleIDs
        )
    }

    static func relaunchAppsWithoutProxy(bundleIdentifiers: [String]) throws {
        for bundleID in bundleIdentifiers {
            guard isRunning(bundleIdentifier: bundleID) else {
                continue
            }

            try terminateRunningApps(bundleIdentifier: bundleID)
            try launchApp(bundleIdentifier: bundleID, arguments: [])
        }
    }

    static func relaunchRunningEnvironmentProxyApps(
        rules: [AppRouteRule],
        host: String,
        port: Int
    ) throws -> AppProxyLaunchResult {
        let bundleIDs = rules
            .filter { $0.enabled && environmentProxyBundleIDs.contains($0.bundleId) }
            .map(\.bundleId)

        var launchedBundleIDs: [String] = []
        for bundleID in bundleIDs where isRunning(bundleIdentifier: bundleID) {
            try terminateRunningApps(bundleIdentifier: bundleID)
            try launchApp(
                bundleIdentifier: bundleID,
                arguments: [],
                proxyHost: host,
                proxyPort: port
            )
            launchedBundleIDs.append(bundleID)
        }

        return AppProxyLaunchResult(
            launchedBundleIDs: launchedBundleIDs,
            unsupportedBundleIDs: []
        )
    }

    static func relaunchRunningSupportedApps(
        host: String,
        port: Int
    ) throws -> AppProxyLaunchResult {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let supportedBundleIDs = runningBundleIDs
            .filter(supportsProxyArgument(bundleIdentifier:))
            .sorted()

        var launchedBundleIDs: [String] = []
        for bundleID in supportedBundleIDs {
            try terminateRunningApps(bundleIdentifier: bundleID)
            try launchApp(
                bundleIdentifier: bundleID,
                arguments: proxyArguments(host: host, port: port, bundleIdentifier: bundleID),
                proxyHost: host,
                proxyPort: port
            )
            launchedBundleIDs.append(bundleID)
        }

        return AppProxyLaunchResult(
            launchedBundleIDs: launchedBundleIDs,
            unsupportedBundleIDs: []
        )
    }

    private static func terminateRunningApps(bundleIdentifier: String) throws {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in runningApps where !app.isTerminated {
            if !app.terminate() {
                _ = app.forceTerminate()
            }
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let alive = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .contains(where: { !$0.isTerminated })
            if !alive {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let stubbornApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
        for app in stubbornApps {
            _ = app.forceTerminate()
        }

        Thread.sleep(forTimeInterval: 0.2)

        let stillAlive = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains(where: { !$0.isTerminated })
        if stillAlive {
            throw AppProxyLauncherError.terminationTimedOut(bundleIdentifier: bundleIdentifier)
        }
    }

    private static func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains(where: { !$0.isTerminated })
    }

    private static func launchApp(
        bundleIdentifier: String,
        arguments: [String],
        proxyHost: String? = nil,
        proxyPort: Int? = nil
    ) throws {
        if environmentProxyBundleIDs.contains(bundleIdentifier),
           let appURL = bundleApplicationURL(for: bundleIdentifier),
           let executableURL = bundleExecutableURL(for: appURL) {
            try launchExecutable(
                executableURL: executableURL,
                bundleIdentifier: bundleIdentifier,
                arguments: arguments,
                proxyHost: proxyHost,
                proxyPort: proxyPort
            )
            return
        }

        let process = Process()
        process.environment = launchEnvironment(arguments: arguments, host: proxyHost, port: proxyPort)
        process.executableURL = URL(fileURLWithPath: openToolPath)

        if let appURL = bundleApplicationURL(for: bundleIdentifier) {
            process.arguments = ["-n", "-a", appURL.path, "--args"] + arguments
        } else {
            process.arguments = ["-n", "-b", bundleIdentifier, "--args"] + arguments
        }

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppProxyLauncherError.launchFailed(
                bundleIdentifier: bundleIdentifier,
                message: message.isEmpty ? "unknown error" : message
            )
        }
    }

    private static func launchExecutable(
        executableURL: URL,
        bundleIdentifier: String,
        arguments: [String],
        proxyHost: String?,
        proxyPort: Int?
    ) throws {
        let process = Process()
        process.environment = launchEnvironment(arguments: arguments, host: proxyHost, port: proxyPort)
        process.executableURL = executableURL
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        Thread.sleep(forTimeInterval: 0.4)

        if process.isRunning || isRunning(bundleIdentifier: bundleIdentifier) {
            return
        }

        let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw AppProxyLauncherError.launchFailed(
            bundleIdentifier: bundleIdentifier,
            message: message.isEmpty ? "app exited immediately" : message
        )
    }

    private static func bundleApplicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    private static func bundleExecutableURL(for appURL: URL) -> URL? {
        guard let bundle = Bundle(url: appURL),
              let executablePath = bundle.executablePath else {
            return nil
        }

        let executableURL = URL(fileURLWithPath: executablePath)
        return FileManager.default.isExecutableFile(atPath: executableURL.path) ? executableURL : nil
    }

    private static func launchEnvironment(arguments: [String], host: String? = nil, port: Int? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let proxyValue: String?
        if let proxyArgument = arguments.first(where: { $0.hasPrefix("--proxy-server=") }) {
            proxyValue = String(proxyArgument.dropFirst("--proxy-server=".count))
        } else if let host, let port {
            proxyValue = "http://\(host):\(port)"
        } else {
            proxyValue = nil
        }

        guard let proxyValue else {
            environment.removeValue(forKey: "HTTP_PROXY")
            environment.removeValue(forKey: "HTTPS_PROXY")
            environment.removeValue(forKey: "ALL_PROXY")
            environment.removeValue(forKey: "http_proxy")
            environment.removeValue(forKey: "https_proxy")
            environment.removeValue(forKey: "all_proxy")
            return environment
        }

        let socksValue: String
        if let host, let port {
            socksValue = "socks5://\(host):\(port)"
        } else {
            socksValue = proxyValue
        }

        environment["HTTP_PROXY"] = proxyValue
        environment["HTTPS_PROXY"] = proxyValue
        environment["ALL_PROXY"] = socksValue
        environment["SOCKS_PROXY"] = socksValue
        environment["http_proxy"] = proxyValue
        environment["https_proxy"] = proxyValue
        environment["all_proxy"] = socksValue
        environment["socks_proxy"] = socksValue
        return environment
    }

    private static func proxyArguments(host: String, port: Int, bundleIdentifier: String) -> [String] {
        if environmentProxyBundleIDs.contains(bundleIdentifier) {
            return []
        }

        var arguments = ["--proxy-server=http://\(host):\(port)"]
        if isChromiumFamily(bundleIdentifier: bundleIdentifier) {
            arguments.append(contentsOf: chromiumProxyArguments)
        }
        return arguments
    }

    private static func isChromiumFamily(bundleIdentifier: String) -> Bool {
        let knownChromiumPrefixes = [
            "com.google.Chrome",
            "com.brave.Browser",
            "company.thebrowser.Browser",
            "com.microsoft.edgemac",
            "org.chromium.Chromium",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "com.microsoft.VSCode",
            "com.openai.codex",
            "com.openai.chat",
        ]

        return knownChromiumPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) })
    }

    private static func supportsProxyArgument(bundleIdentifier: String) -> Bool {
        isChromiumFamily(bundleIdentifier: bundleIdentifier) || environmentProxyBundleIDs.contains(bundleIdentifier)
    }
}

enum AppProxyLauncherError: LocalizedError {
    case launchFailed(bundleIdentifier: String, message: String)
    case terminationTimedOut(bundleIdentifier: String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(bundleIdentifier, message):
            return "Failed to relaunch \(bundleIdentifier) with proxy settings: \(message)"
        case let .terminationTimedOut(bundleIdentifier):
            return "Failed to terminate \(bundleIdentifier) before relaunching it without stale proxy arguments."
        }
    }
}
