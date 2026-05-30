import Foundation
#if canImport(AppKit)
import AppKit
#endif
import React
import V2DexCore

@objc(V2DexBridge)
final class V2DexBridge: NSObject {
    private let persistedStateKey = "v2dex.persisted.app.state"

    @objc
    static func requiresMainQueueSetup() -> Bool {
        false
    }

    @objc(importFromClipboard:rejecter:)
    func importFromClipboard(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        #if canImport(AppKit)
        let value = NSPasteboard.general.string(forType: .string) ?? ""
        resolve(value)
        #else
        reject("clipboard_unavailable", "Clipboard access is unavailable on this platform.", nil)
        #endif
    }

    @objc(copyToClipboard:resolver:rejecter:)
    func copyToClipboard(_ value: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        resolve(nil)
        #else
        reject("clipboard_unavailable", "Clipboard access is unavailable on this platform.", nil)
        #endif
    }

    @objc(scanQrFromCamera:rejecter:)
    func scanQrFromCamera(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        reject("qr_scan_unavailable", "QR camera scanning is unavailable on macOS.", nil)
    }

    @objc(scanQrFromGallery:rejecter:)
    func scanQrFromGallery(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        reject("qr_scan_unavailable", "QR gallery scanning is unavailable on macOS.", nil)
    }

    @objc(importFromUri:resolver:rejecter:)
    func importFromUri(_ uri: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        Task {
            do {
                let payload = try await BackendCoordinator.importProfile(from: uri)
                let data = try makeEncoder().encode(payload)
                resolve(String(decoding: data, as: UTF8.self))
            } catch {
                reject("import_failed", error.localizedDescription, error)
            }
        }
    }

    @objc(discoverInstalledApplications:rejecter:)
    func discoverInstalledApplications(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        do {
            let apps = BackendCoordinator.discoverApplications()
            let data = try makeEncoder().encode(apps)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            resolve(object)
        } catch {
            reject("app_discovery_failed", error.localizedDescription, error)
        }
    }

    @objc(loadAppState:rejecter:)
    func loadAppState(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(UserDefaults.standard.string(forKey: persistedStateKey) ?? "")
    }

    @objc(saveAppState:resolver:rejecter:)
    func saveAppState(_ stateJson: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        UserDefaults.standard.set(stateJson, forKey: persistedStateKey)
        resolve(nil)
    }

    @objc(testProfileDownload:resolver:rejecter:)
    func testProfileDownload(_ sourceValue: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        Task {
            do {
                let result = try await BackendCoordinator.testSubscriptionDownload(from: sourceValue)
                resolve(result)
            } catch {
                reject("download_test_failed", error.localizedDescription, error)
            }
        }
    }

    @objc(testServerConnection:resolver:rejecter:)
    func testServerConnection(_ nodeJson: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        do {
            let node = try JSONDecoder().decode(ProxyNode.self, from: Data(nodeJson.utf8))
            Task {
                do {
                    let latency = try await ConnectivityTester.testTCPConnection(to: node)
                    resolve(["message": "Server reachable in \(latency)ms.", "latencyMs": latency])
                } catch {
                    reject("server_test_failed", error.localizedDescription, error)
                }
            }
        } catch {
            reject("server_test_failed", error.localizedDescription, error)
        }
    }

    @objc(testTunnelHttpLatency:resolver:rejecter:)
    func testTunnelHttpLatency(_ url: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        Task {
            do {
                let result = try await ConnectivityTester.testHTTPViaLocalProxy(
                    url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                    proxyHost: SingboxConfigBuilder.localProxyHost,
                    proxyPort: SingboxConfigBuilder.localProxyPort
                )
                let host = URL(string: result.url)?.host ?? result.url
                resolve([
                    "message": "Reached \(host) in \(result.latencyMs)ms",
                    "latencyMs": result.latencyMs,
                    "url": result.url
                ])
            } catch {
                reject("tunnel_ping_failed", error.localizedDescription, error)
            }
        }
    }

    @objc(getTunnelIpInfo:rejecter:)
    func getTunnelIpInfo(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        Task {
            let endpoints = [
                "http://ip-api.com/json/?fields=status,country,countryCode,query,message",
                "https://ipwho.is/"
            ]
            var lastError: Error?

            for endpoint in endpoints {
                do {
                    let payload = try await ConnectivityTester.fetchTextViaLocalProxy(
                        url: endpoint,
                        proxyHost: SingboxConfigBuilder.localProxyHost,
                        proxyPort: SingboxConfigBuilder.localProxyPort
                    )
                    if let object = try parseIpInfoPayload(payload) {
                        resolve(object)
                        return
                    }
                } catch {
                    lastError = error
                }
            }

            reject("ip_info_failed", lastError?.localizedDescription ?? "IP lookup failed.", lastError)
        }
    }

    @objc(startTunnel:mode:appRulesJson:resolver:rejecter:)
    func startTunnel(
        _ configJson: String,
        mode: String,
        appRulesJson: String,
        resolve: RCTPromiseResolveBlock,
        reject: RCTPromiseRejectBlock
    ) {
        Task {
            do {
                let tunnelMode = TunnelMode(rawValue: mode) ?? .full
                let appRules = try JSONDecoder().decode([AppRouteRule].self, from: Data(appRulesJson.utf8))
                let snapshot = try SingboxRuntime.shared.start(
                    configData: Data(configJson.utf8),
                    mode: tunnelMode,
                    appRules: appRules
                )
                let data = try makeEncoder().encode(snapshot)
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                resolve(object)
            } catch {
                reject("start_tunnel_failed", error.localizedDescription, error)
            }
        }
    }

    @objc(stopTunnel:rejecter:)
    func stopTunnel(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        do {
            try SingboxRuntime.shared.stopIfNeeded()
            resolve(nil)
        } catch {
            reject("stop_tunnel_failed", error.localizedDescription, error)
        }
    }

    @objc(getTunnelStatus:rejecter:)
    func getTunnelStatus(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        do {
            let snapshot = SingboxRuntime.shared.statusSnapshot()
            let data = try makeEncoder().encode(snapshot)
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            resolve(object)
        } catch {
            reject("status_failed", error.localizedDescription, error)
        }
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func parseIpInfoPayload(_ payload: String) throws -> [String: String]? {
        guard let data = payload.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let status = json["status"] as? String, status != "success" {
            return nil
        }
        if let success = json["success"] as? Bool, !success {
            return nil
        }

        var result: [String: String] = [:]
        if let ip = (json["query"] as? String) ?? (json["ip"] as? String) {
            result["ip"] = ip
        }
        if let country = json["country"] as? String {
            result["country"] = country
        }
        if let countryCode = (json["countryCode"] as? String) ?? (json["country_code"] as? String) {
            result["countryCode"] = countryCode
        }

        return result.isEmpty ? nil : result
    }
}
