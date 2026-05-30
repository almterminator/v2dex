import AppKit
import Foundation

final class MacSystemProxyController {
    private let networksetupPath = "/usr/sbin/networksetup"
    private let stateQueue = DispatchQueue(label: "V2DexCore.MacSystemProxyController")
    private var savedState: [String: ProxyState] = [:]

    func enableProxy(host: String, port: Int) throws {
        let services = try activeNetworkServices()
        let previousState = try Dictionary(uniqueKeysWithValues: services.map { service in
            (service, try currentState(for: service))
        })

        do {
            for service in services {
                try runNetworksetup(["-setwebproxy", service, host, String(port)])
                try runNetworksetup(["-setsecurewebproxy", service, host, String(port)])
                try runNetworksetup(["-setsocksfirewallproxy", service, host, String(port)])
                try runNetworksetup(["-setwebproxystate", service, "on"])
                try runNetworksetup(["-setsecurewebproxystate", service, "on"])
                try runNetworksetup(["-setsocksfirewallproxystate", service, "on"])
            }
            stateQueue.sync {
                savedState = previousState
            }
        } catch {
            try? restore(previousState)
            throw error
        }
    }

    func disableProxy() throws {
        let previousState = stateQueue.sync { savedState }
        defer {
            stateQueue.sync {
                savedState.removeAll()
            }
        }

        if previousState.isEmpty {
            try forceDisableAllProxies()
        } else {
            try restore(previousState)
        }
    }

    func forceDisableAllProxies() throws {
        let services = try activeNetworkServices()
        for service in services {
            try runNetworksetup(["-setwebproxystate", service, "off"])
            try runNetworksetup(["-setsecurewebproxystate", service, "off"])
            try runNetworksetup(["-setsocksfirewallproxystate", service, "off"])
            try runNetworksetup(["-setautoproxystate", service, "off"])
            try runNetworksetup(["-setproxyautodiscovery", service, "off"])
        }
    }

    private func activeNetworkServices() throws -> [String] {
        let output = try runNetworksetup(["-listallnetworkservices"])
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") }
    }

    private func currentState(for service: String) throws -> ProxyState {
        ProxyState(
            web: try proxyRecord(for: service, kind: .web),
            secureWeb: try proxyRecord(for: service, kind: .secureWeb),
            socks: try proxyRecord(for: service, kind: .socks)
        )
    }

    private func restore(_ states: [String: ProxyState]) throws {
        for (service, state) in states {
            try restore(state.web, service: service)
            try restore(state.secureWeb, service: service)
            try restore(state.socks, service: service)
        }
    }

    private func restore(_ record: ProxyRecord, service: String) throws {
        switch record.kind {
        case .web:
            try runNetworksetup(["-setwebproxy", service, record.host, String(record.port)])
            try runNetworksetup(["-setwebproxystate", service, record.enabled ? "on" : "off"])
        case .secureWeb:
            try runNetworksetup(["-setsecurewebproxy", service, record.host, String(record.port)])
            try runNetworksetup(["-setsecurewebproxystate", service, record.enabled ? "on" : "off"])
        case .socks:
            try runNetworksetup(["-setsocksfirewallproxy", service, record.host, String(record.port)])
            try runNetworksetup(["-setsocksfirewallproxystate", service, record.enabled ? "on" : "off"])
        }
    }

    private func proxyRecord(for service: String, kind: ProxyKind) throws -> ProxyRecord {
        let output = try runNetworksetup([kind.getArgument, service])
        let parsed = parseProxyOutput(output)
        return ProxyRecord(
            kind: kind,
            enabled: parsed.enabled,
            host: parsed.host.isEmpty ? "127.0.0.1" : parsed.host,
            port: parsed.port
        )
    }

    private func parseProxyOutput(_ output: String) -> (enabled: Bool, host: String, port: Int) {
        var enabled = false
        var host = ""
        var port = 0

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "Enabled":
                enabled = value.caseInsensitiveCompare("Yes") == .orderedSame
                    || value.caseInsensitiveCompare("On") == .orderedSame
            case "Server":
                host = value
            case "Port":
                port = Int(value) ?? 0
            default:
                break
            }
        }

        return (enabled, host, port)
    }

    @discardableResult
    private func runNetworksetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: networksetupPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw MacSystemProxyControllerError.commandFailed(
                arguments: arguments,
                message: errorOutput.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
    }
}

private struct ProxyState {
    let web: ProxyRecord
    let secureWeb: ProxyRecord
    let socks: ProxyRecord
}

private struct ProxyRecord {
    let kind: ProxyKind
    let enabled: Bool
    let host: String
    let port: Int
}

private enum ProxyKind {
    case web
    case secureWeb
    case socks

    var getArgument: String {
        switch self {
        case .web:
            return "-getwebproxy"
        case .secureWeb:
            return "-getsecurewebproxy"
        case .socks:
            return "-getsocksfirewallproxy"
        }
    }
}

enum MacSystemProxyControllerError: LocalizedError {
    case commandFailed(arguments: [String], message: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, message):
            let detail = message.isEmpty ? "unknown error" : message
            return "macOS proxy update failed for \(arguments.joined(separator: " ")): \(detail)"
        }
    }
}
