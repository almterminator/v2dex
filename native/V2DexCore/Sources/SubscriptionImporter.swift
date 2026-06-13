import Foundation

public enum SubscriptionImporter {
    private static let requestTimeout: TimeInterval = 20

    public static func importRaw(_ raw: String) async throws -> [ProxyNode] {
        let payload = try await importProfile(raw)
        return payload.nodes
    }

    public static func importProfile(_ raw: String) async throws -> ImportedProfilePayload {
        let normalizedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: normalizedRaw),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = requestTimeout

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw mapNetworkError(error, url: url)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImportError.invalidHTTPResponse(url: url.absoluteString)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ImportError.httpStatus(
                    code: httpResponse.statusCode,
                    url: url.absoluteString
                )
            }

            guard !data.isEmpty else {
                throw ImportError.emptySubscriptionResponse(url: url.absoluteString)
            }

            let body = decodeResponseBody(data)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.emptySubscriptionResponse(url: url.absoluteString)
            }

            return try ImportedProfilePayload(
                nodes: importContent(body),
                usage: extractUsage(from: response)
            )
        }

        return try ImportedProfilePayload(nodes: importContent(normalizedRaw))
    }

    private static func importContent(_ raw: String) throws -> [ProxyNode] {
        let decodedBody = decodeSubscriptionBodyIfNeeded(raw)
        let lines = decodedBody
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.isEmpty {
            return [try buildNode(from: raw)]
        }

        return try lines.map(buildNode)
    }

    private static func buildNode(from raw: String) throws -> ProxyNode {
        if raw.hasPrefix("vless://"), let parsed = parseVLESS(raw) {
            return parsed
        }
        if raw.hasPrefix("vmess://"), let parsed = parseVMess(raw) {
            return parsed
        }
        if raw.hasPrefix("hysteria2://"), let parsed = parseHysteria2(raw) {
            return parsed
        }
        if raw.hasPrefix("tuic://"), let parsed = parseTuic(raw) {
            return parsed
        }
        if raw.hasPrefix("trojan://"), let parsed = parseTrojan(raw) {
            return parsed
        }

        throw ImportError.unsupportedScheme
    }

    private static func parseVLESS(_ raw: String) -> ProxyNode? {
        guard let components = URLComponents(string: raw) else {
            return nil
        }

        let host = components.host ?? "localhost"
        let port = components.port ?? 443
        let fragment = decodePercentEncodingRepeatedly(components.fragment)
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { item in
            (item.name, item.value ?? "")
        })

        let uuid = components.user
        let transport = queryItems["type"]
        let securityValue = queryItems["security"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let security = securityValue.isEmpty ? "none" : securityValue
        let path = queryItems["path"]?.removingPercentEncoding ?? "/"
        let sni = queryItems["sni"] ?? queryItems["host"]
        let wsHost = queryItems["host"]
        let flow = queryItems["flow"]
        let udpOverTCP = queryItems["udp-over-tcp"] == "true" || queryItems["uot"] == "1"
        let allowInsecure = queryItems["allowInsecure"] == "1" || queryItems["allowInsecure"]?.lowercased() == "true"
        let publicKey = queryItems["pbk"] ?? queryItems["publicKey"]
        let shortId = queryItems["sid"] ?? queryItems["shortId"]
        let fingerprint = queryItems["fp"] ?? queryItems["fingerprint"]
        let alpn = splitCSV(queryItems["alpn"])
        let label = fragment?.isEmpty == false ? fragment! : "VLESS \(host)"

        return ProxyNode(
            id: stableNodeID(from: raw),
            name: label,
            protocolType: "vless",
            server: host,
            port: port,
            security: security,
            transport: transport,
            sni: sni,
            path: path,
            uuid: uuid,
            wsHost: wsHost,
            flow: flow,
            udpOverTCP: udpOverTCP,
            allowInsecure: allowInsecure,
            publicKey: publicKey,
            shortId: shortId,
            fingerprint: fingerprint,
            alpn: alpn
        )
    }

    private static func parseVMess(_ raw: String) -> ProxyNode? {
        let payload = String(raw.dropFirst("vmess://".count))
        guard let decoded = decodeBase64Like(payload),
              let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let host = (json["add"] as? String) ?? (json["host"] as? String) ?? "localhost"
        let label = (json["ps"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int((json["port"] as? String) ?? "") ?? (json["port"] as? Int) ?? 443
        let transport = (json["net"] as? String) ?? (json["type"] as? String)
        let path = (json["path"] as? String)?.removingPercentEncoding ?? "/"
        let wsHost = json["host"] as? String
        let tlsEnabled = ((json["tls"] as? String) ?? "").lowercased() == "tls"
        let sni = json["sni"] as? String ?? wsHost
        let alpn = splitCSV(json["alpn"] as? String)

        return ProxyNode(
            id: stableNodeID(from: raw),
            name: label?.isEmpty == false ? label! : "VMess \(host)",
            protocolType: "vmess",
            server: host,
            port: port,
            security: tlsEnabled ? "tls" : "none",
            transport: transport,
            sni: sni,
            path: path,
            uuid: json["id"] as? String,
            wsHost: wsHost,
            allowInsecure: ((json["allowInsecure"] as? String) ?? "") == "1",
            alpn: alpn,
            alterId: Int((json["aid"] as? String) ?? "") ?? (json["aid"] as? Int),
            vmessCipher: json["scy"] as? String
        )
    }

    private static func parseHysteria2(_ raw: String) -> ProxyNode? {
        guard let components = URLComponents(string: raw) else {
            return nil
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        return ProxyNode(
            id: stableNodeID(from: raw),
            name: decodePercentEncodingRepeatedly(components.fragment) ?? "Hysteria2 \(components.host ?? "server")",
            protocolType: "hysteria2",
            server: components.host ?? "localhost",
            port: components.port ?? 443,
            security: "tls",
            transport: nil,
            sni: queryItems["sni"],
            path: nil,
            password: components.user,
            allowInsecure: queryItems["insecure"] == "1" || queryItems["allowInsecure"] == "1",
            alpn: splitCSV(queryItems["alpn"])
        )
    }

    private static func parseTuic(_ raw: String) -> ProxyNode? {
        guard let components = URLComponents(string: raw) else {
            return nil
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        return ProxyNode(
            id: stableNodeID(from: raw),
            name: decodePercentEncodingRepeatedly(components.fragment) ?? "TUIC \(components.host ?? "server")",
            protocolType: "tuic",
            server: components.host ?? "localhost",
            port: components.port ?? 443,
            security: "tls",
            transport: nil,
            sni: queryItems["sni"],
            path: nil,
            uuid: components.user,
            password: components.password,
            allowInsecure: queryItems["allow_insecure"] == "1" || queryItems["allowInsecure"] == "1",
            alpn: splitCSV(queryItems["alpn"])
        )
    }

    private static func parseTrojan(_ raw: String) -> ProxyNode? {
        guard let components = URLComponents(string: raw) else {
            return nil
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let transport = queryItems["type"]
        return ProxyNode(
            id: stableNodeID(from: raw),
            name: decodePercentEncodingRepeatedly(components.fragment) ?? "Trojan \(components.host ?? "server")",
            protocolType: "trojan",
            server: components.host ?? "localhost",
            port: components.port ?? 443,
            security: "tls",
            transport: transport,
            sni: queryItems["sni"] ?? queryItems["host"],
            path: queryItems["path"]?.removingPercentEncoding ?? "/",
            password: components.user,
            wsHost: queryItems["host"],
            allowInsecure: queryItems["allowInsecure"] == "1",
            alpn: splitCSV(queryItems["alpn"])
        )
    }

    private static func decodeSubscriptionBodyIfNeeded(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }
        return decodeBase64Like(trimmed) ?? trimmed
    }

    private static func decodeBase64Like(_ raw: String) -> String? {
        let sanitized = raw
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        let padding = (4 - (sanitized.count % 4)) % 4
        let padded = sanitized + String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: padded) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeResponseBody(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        if let isoLatin1 = String(data: data, encoding: .isoLatin1) {
            return isoLatin1
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func mapNetworkError(_ error: Error, url: URL) -> ImportError {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .networkRequestFailed(url: url.absoluteString, reason: error.localizedDescription)
        }
        let code = URLError.Code(rawValue: nsError.code)

        switch code {
        case .timedOut:
            return .requestTimedOut(url: url.absoluteString, timeout: Int(requestTimeout))
        case .badServerResponse, .cannotParseResponse, .zeroByteResource:
            return .emptySubscriptionResponse(url: url.absoluteString)
        default:
            return .networkRequestFailed(url: url.absoluteString, reason: error.localizedDescription)
        }
    }

    private static func splitCSV(_ value: String?) -> [String]? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let parts = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }

    private static func decodePercentEncodingRepeatedly(_ value: String?) -> String? {
        guard var decoded = value else {
            return nil
        }

        for _ in 0..<5 {
            guard let next = decoded.removingPercentEncoding, next != decoded else {
                return decoded
            }
            decoded = next
        }

        return decoded
    }

    private static func stableNodeID(from raw: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "node-\(String(hash, radix: 16))"
    }

    private static func extractUsage(from response: URLResponse) -> SubscriptionUsage? {
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }

        let headerValue = httpResponse.allHeaderFields.first { key, _ in
            String(describing: key).caseInsensitiveCompare("subscription-userinfo") == .orderedSame
                || String(describing: key).caseInsensitiveCompare("x-subscription-userinfo") == .orderedSame
        }?.value as? String

        guard let headerValue, !headerValue.isEmpty else {
            return nil
        }

        var values: [String: Int64] = [:]
        for part in headerValue.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = Int64(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))
            values[key] = value
        }

        let uploadBytes = values["upload"]
        let downloadBytes = values["download"]
        let totalBytes = values["total"]
        let usedBytes: Int64? = {
            let upload = uploadBytes ?? 0
            let download = downloadBytes ?? 0
            return uploadBytes == nil && downloadBytes == nil ? nil : upload + download
        }()
        let remainingBytes: Int64? = {
            guard let totalBytes else { return nil }
            return max(totalBytes - (usedBytes ?? 0), 0)
        }()
        let expiresAt: Date? = {
            guard let expire = values["expire"], expire > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(expire))
        }()

        if uploadBytes == nil, downloadBytes == nil, totalBytes == nil, expiresAt == nil {
            return nil
        }

        return SubscriptionUsage(
            uploadBytes: uploadBytes,
            downloadBytes: downloadBytes,
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            remainingBytes: remainingBytes,
            expiresAt: expiresAt
        )
    }

    enum ImportError: LocalizedError {
        case unsupportedScheme
        case requestTimedOut(url: String, timeout: Int)
        case invalidHTTPResponse(url: String)
        case httpStatus(code: Int, url: String)
        case emptySubscriptionResponse(url: String)
        case networkRequestFailed(url: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedScheme:
                return "This config format is not supported yet."
            case let .requestTimedOut(url, timeout):
                return "Subscription request timed out after \(timeout)s: \(url)"
            case let .invalidHTTPResponse(url):
                return "Subscription server returned an invalid HTTP response: \(url)"
            case let .httpStatus(code, url):
                return "Subscription server returned HTTP \(code): \(url)"
            case let .emptySubscriptionResponse(url):
                return "Subscription server accepted the connection but returned an empty response: \(url)"
            case let .networkRequestFailed(url, reason):
                return "Subscription request failed for \(url): \(reason)"
            }
        }
    }
}
