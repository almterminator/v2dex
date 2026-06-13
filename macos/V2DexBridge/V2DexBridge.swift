import Foundation
#if canImport(AppKit)
import AppKit
#endif
import React

@objc(V2DexBridge)
final class V2DexBridge: NSObject {
    private let persistedStateKey = "v2dex.persisted.app.state"
    private let debugStartKey = "v2dex.debug.lastNativeStart"

    override init() {
        super.init()
        #if canImport(AppKit)
        MacNativeConnectOverlay.shared.installWhenReady()
        #endif
    }

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
    func importFromUri(_ uri: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
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
                    let result = try await ConnectivityTester.testProxyHTTPProbe(to: node)
                    let host = URL(string: result.url)?.host ?? result.url
                    resolve([
                        "message": "Reached \(host) through config in \(result.latencyMs)ms.",
                        "latencyMs": result.latencyMs,
                        "url": result.url
                    ])
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
                    proxyHost: SingboxConfigBuilder.loopbackProxyHost,
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
                        proxyHost: SingboxConfigBuilder.loopbackProxyHost,
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
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        saveNativeStartDebug(stage: "called", mode: mode, error: nil)
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
                self.saveNativeStartDebug(stage: "resolved", mode: mode, error: nil)
                resolve(object)
            } catch {
                self.saveNativeStartDebug(stage: "failed", mode: mode, error: error.localizedDescription)
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

    private func saveNativeStartDebug(stage: String, mode: String, error: String?) {
        var payload: [String: Any] = [
            "stage": stage,
            "mode": mode,
            "at": ISO8601DateFormatter().string(from: Date())
        ]
        if let error {
            payload["error"] = error
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let value = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(value, forKey: debugStartKey)
        }
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

#if canImport(AppKit)
private final class MacNativeConnectOverlay: NSObject {
    static let shared = MacNativeConnectOverlay()

    private let persistedStateKey = "v2dex.persisted.app.state"
    private let debugStartKey = "v2dex.debug.lastNativeStart"
    private weak var button: NSButton?

    func installWhenReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.installIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.installIfNeeded()
        }
    }

    private func installIfNeeded() {
        guard button == nil,
              let window = NSApp.windows.first(where: { $0.contentView != nil }),
              let contentView = window.contentView else {
            return
        }

        let connectButton = NSButton(frame: mobileConnectButtonFrame(in: contentView))
        connectButton.title = currentTitle()
        connectButton.isBordered = false
        connectButton.bezelStyle = .regularSquare
        connectButton.controlSize = .large
        connectButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        connectButton.target = self
        connectButton.action = #selector(toggleConnection)
        connectButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        connectButton.wantsLayer = true
        connectButton.layer?.backgroundColor = currentButtonColor().cgColor
        connectButton.layer?.cornerRadius = 16
        connectButton.layer?.masksToBounds = true
        connectButton.layer?.zPosition = 1000
        applyTitleColor(to: connectButton)

        contentView.addSubview(connectButton)
        button = connectButton
    }

    private func mobileConnectButtonFrame(in contentView: NSView) -> NSRect {
        let shellPadding: CGFloat = 16
        let actionBarPadding: CGFloat = 12
        let buttonGap: CGFloat = 12
        let buttonHeight: CGFloat = 50
        let contentWidth = contentView.bounds.width
        let contentHeight = contentView.bounds.height
        let availableWidth = max(contentWidth - shellPadding * 2 - actionBarPadding * 2 - buttonGap, 160)
        let buttonWidth = floor(availableWidth / 2)
        let buttonY = contentView.isFlipped
            ? max(contentHeight - shellPadding - actionBarPadding - buttonHeight, shellPadding)
            : shellPadding + actionBarPadding
        return NSRect(
            x: shellPadding + actionBarPadding,
            y: buttonY,
            width: buttonWidth,
            height: buttonHeight
        )
    }

    @objc
    private func toggleConnection() {
        button?.isEnabled = false
        button?.title = "Working..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let status = SingboxRuntime.shared.statusSnapshot()
                if status.connected || status.connecting {
                    try SingboxRuntime.shared.stopIfNeeded()
                    self.saveDebug(stage: "native-overlay-stopped", mode: status.mode.rawValue, error: nil)
                } else {
                    let persistedState = try self.loadPersistedState()
                    let node = try self.activeNode(from: persistedState)
                    let appRules = persistedState.appRules ?? []
                    let mode = persistedState.mode ?? .full
                    let configData = try SingboxConfigBuilder.build(node: node, mode: mode, appRules: appRules)
                    _ = try SingboxRuntime.shared.start(configData: configData, mode: mode, appRules: appRules)
                    self.saveDebug(stage: "native-overlay-started", mode: mode.rawValue, error: nil)
                }

                DispatchQueue.main.async {
                    self.button?.title = self.currentTitle()
                    if let button = self.button {
                        button.layer?.backgroundColor = self.currentButtonColor().cgColor
                        self.applyTitleColor(to: button)
                    }
                    self.button?.isEnabled = true
                }
            } catch {
                self.saveDebug(stage: "native-overlay-failed", mode: nil, error: error.localizedDescription)
                DispatchQueue.main.async {
                    self.button?.title = "Connect"
                    if let button = self.button {
                        button.layer?.backgroundColor = self.currentButtonColor().cgColor
                        self.applyTitleColor(to: button)
                    }
                    self.button?.isEnabled = true
                }
            }
        }
    }

    private func currentTitle() -> String {
        let status = SingboxRuntime.shared.statusSnapshot()
        if status.connecting {
            return "Connecting..."
        }
        return status.connected ? "Disconnect" : "Connect"
    }

    private func currentButtonColor() -> NSColor {
        let status = SingboxRuntime.shared.statusSnapshot()
        if status.connecting {
            return NSColor(red: 1.0, green: 0.46, blue: 0.46, alpha: 1.0)
        }
        if status.connected {
            return NSColor(red: 0.48, green: 1.0, blue: 0.70, alpha: 1.0)
        }
        return NSColor(red: 0.42, green: 0.72, blue: 1.0, alpha: 1.0)
    }

    private func applyTitleColor(to button: NSButton) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor(red: 0.02, green: 0.07, blue: 0.09, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 15, weight: .bold),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func loadPersistedState() throws -> PersistedNativeState {
        guard let raw = UserDefaults.standard.string(forKey: persistedStateKey),
              let data = raw.data(using: .utf8) else {
            throw NativeOverlayError.noPersistedState
        }
        return try JSONDecoder().decode(PersistedNativeState.self, from: data)
    }

    private func activeNode(from state: PersistedNativeState) throws -> ProxyNode {
        let profile = state.profiles.first { $0.id == state.activeProfileId } ?? state.profiles.first
        let node = profile?.nodes.first { $0.id == state.activeNodeId } ?? profile?.nodes.first
        guard let node else {
            throw NativeOverlayError.noActiveNode
        }
        return node
    }

    private func saveDebug(stage: String, mode: String?, error: String?) {
        var payload: [String: Any] = [
            "stage": stage,
            "at": ISO8601DateFormatter().string(from: Date())
        ]
        if let mode {
            payload["mode"] = mode
        }
        if let error {
            payload["error"] = error
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let value = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(value, forKey: debugStartKey)
        }
    }
}

private struct PersistedNativeState: Decodable {
    let profiles: [PersistedNativeProfile]
    let appRules: [AppRouteRule]?
    let activeProfileId: String?
    let activeNodeId: String?
    let mode: TunnelMode?
}

private struct PersistedNativeProfile: Decodable {
    let id: String
    let nodes: [ProxyNode]
}

private enum NativeOverlayError: LocalizedError {
    case noPersistedState
    case noActiveNode

    var errorDescription: String? {
        switch self {
        case .noPersistedState:
            return "No saved V2Dex config was found."
        case .noActiveNode:
            return "No active V2Dex node was selected."
        }
    }
}
#endif
