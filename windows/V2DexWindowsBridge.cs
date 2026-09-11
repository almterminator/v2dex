using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;

namespace V2Dex.Windows
{
    public sealed class TunnelStatusSnapshot
    {
        public bool connected { get; set; }
        public bool connecting { get; set; }
        public string mode { get; set; } = "full";
        public string? backend { get; set; }
        public string? lastError { get; set; }
        public string? lastConnectedAt { get; set; }
        public string? binaryPath { get; set; }
        public string? activeConfigPath { get; set; }
        public string? proxyHost { get; set; }
        public int? proxyPort { get; set; }
    }

    public sealed class TunnelHttpLatencyResult
    {
        public string message { get; set; } = "";
        public int? latencyMs { get; set; }
        public string? url { get; set; }
    }

    public sealed class TunnelIpInfo
    {
        public string? ip { get; set; }
        public string? country { get; set; }
        public string? countryCode { get; set; }
    }

    public sealed class AppRouteRule
    {
        public string bundleId { get; set; } = "";
        public string name { get; set; } = "";
        public string processName { get; set; } = "";
        public bool enabled { get; set; }
    }

    public sealed class V2DexWindowsBridge
    {
        private readonly WindowsTunnelRuntime runtime = new WindowsTunnelRuntime();

        public Task<string> ImportFromUri(string uri)
        {
            var nodeUris = ExtractNodeUris(uri);
            var nodes = nodeUris.Select(ParseNodeUri).Where(node => node != null).ToArray();

            if (nodes.Length == 0)
            {
                throw new NotSupportedException("No supported configs were found.");
            }

            var result = new Dictionary<string, object?>
            {
                ["nodes"] = nodes
            };

            return Task.FromResult(JsonSerializer.Serialize(result));
        }

        public Task<TunnelHttpLatencyResult> TestServerConnection(string nodeJson)
        {
            return runtime.TestServerConnectionAsync(nodeJson);
        }

        public Task<IReadOnlyList<AppRouteRule>> DiscoverInstalledApplications()
        {
            IReadOnlyList<AppRouteRule> apps = new[]
            {
                new AppRouteRule { bundleId = "chrome", name = "Google Chrome", processName = "chrome.exe", enabled = false },
                new AppRouteRule { bundleId = "telegram", name = "Telegram", processName = "Telegram.exe", enabled = false },
                new AppRouteRule { bundleId = "vscode", name = "Visual Studio Code", processName = "Code.exe", enabled = false }
            };

            return Task.FromResult(apps);
        }

        public Task<TunnelStatusSnapshot> StartTunnel(string configJson, string mode, string appRulesJson)
        {
            return runtime.StartAsync(configJson, mode, appRulesJson);
        }

        public Task StopTunnel()
        {
            return runtime.StopAsync();
        }

        public Task<TunnelStatusSnapshot> GetTunnelStatus()
        {
            return runtime.GetStatusAsync();
        }

        public Task<TunnelHttpLatencyResult> TestTunnelHttpLatency(string url)
        {
            return runtime.TestTunnelHttpLatencyAsync(url);
        }

        public Task<TunnelIpInfo> GetTunnelIpInfo()
        {
            return runtime.GetTunnelIpInfoAsync();
        }

        public Task CopyToClipboard(string value)
        {
            return runtime.CopyToClipboardAsync(value);
        }

        public Task<string> ScanQrFromCamera()
        {
            throw new NotSupportedException("QR camera scanning is unavailable on Windows.");
        }

        public Task<string> ScanQrFromGallery()
        {
            throw new NotSupportedException("QR gallery scanning is unavailable on Windows.");
        }

        private static IEnumerable<string> ExtractNodeUris(string source)
        {
            return source
                .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(value =>
                    value.StartsWith("vless://", StringComparison.OrdinalIgnoreCase) ||
                    value.StartsWith("socks://", StringComparison.OrdinalIgnoreCase) ||
                    value.StartsWith("socks5://", StringComparison.OrdinalIgnoreCase) ||
                    LooksLikeHttpProxyUri(value));
        }

        private static Dictionary<string, object?>? ParseNodeUri(string uri)
        {
            if (uri.StartsWith("vless://", StringComparison.OrdinalIgnoreCase))
            {
                return ParseVlessUri(uri);
            }
            if (uri.StartsWith("socks://", StringComparison.OrdinalIgnoreCase) ||
                uri.StartsWith("socks5://", StringComparison.OrdinalIgnoreCase))
            {
                return ParseSimpleProxyUri(uri, "socks5");
            }
            if (uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return ParseSimpleProxyUri(uri, uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ? "https" : "http");
            }

            return null;
        }

        private static bool LooksLikeHttpProxyUri(string value)
        {
            if (!value.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                !value.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (!Uri.TryCreate(value, UriKind.Absolute, out var uri))
            {
                return false;
            }

            return !string.IsNullOrWhiteSpace(uri.UserInfo) ||
                   (!uri.IsDefaultPort && string.IsNullOrWhiteSpace(uri.AbsolutePath.Trim('/')));
        }

        private static Dictionary<string, object?> ParseVlessUri(string raw)
        {
            var parsed = new Uri(raw);
            var query = ParseQuery(parsed.Query);
            var wsHost = Read(query, "host");
            var name = DecodePercentEncodingRepeatedly(parsed.Fragment.TrimStart('#'));
            var alpn = Read(query, "alpn")
                ?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Where(value => value.Length > 0)
                .ToArray();

            return new Dictionary<string, object?>
            {
                ["id"] = $"node-{HashString(raw)}",
                ["name"] = name.Length > 0 ? name : $"VLESS {parsed.Host}",
                ["protocol"] = "vless",
                ["server"] = parsed.Host,
                ["port"] = parsed.IsDefaultPort ? 443 : parsed.Port,
                ["security"] = Read(query, "security") ?? "none",
                ["transport"] = Read(query, "type") ?? "tcp",
                ["path"] = Read(query, "path") ?? "/",
                ["sni"] = Read(query, "sni") ?? wsHost,
                ["wsHost"] = wsHost,
                ["flow"] = Read(query, "flow"),
                ["uuid"] = DecodePercentEncodingRepeatedly(parsed.UserInfo),
                ["allowInsecure"] = IsTrue(Read(query, "allowInsecure")),
                ["publicKey"] = Read(query, "pbk") ?? Read(query, "publicKey"),
                ["shortId"] = Read(query, "sid") ?? Read(query, "shortId"),
                ["fingerprint"] = Read(query, "fp") ?? Read(query, "fingerprint"),
                ["alpn"] = alpn is { Length: > 0 } ? alpn : null,
                ["rawUri"] = raw
            };
        }

        private static Dictionary<string, object?> ParseSimpleProxyUri(string raw, string protocol)
        {
            var parsed = new Uri(raw);
            var name = DecodePercentEncodingRepeatedly(parsed.Fragment.TrimStart('#'));
            var credentials = DecodeProxyCredentials(parsed.UserInfo);

            return new Dictionary<string, object?>
            {
                ["id"] = $"node-{HashString(raw)}",
                ["name"] = name.Length > 0 ? name : $"{protocol.ToUpperInvariant()} {parsed.Host}",
                ["protocol"] = protocol,
                ["server"] = parsed.Host,
                ["port"] = parsed.IsDefaultPort ? (protocol == "https" ? 443 : 80) : parsed.Port,
                ["username"] = credentials.username,
                ["password"] = credentials.password,
                ["rawUri"] = raw
            };
        }

        private static (string? username, string? password) DecodeProxyCredentials(string userInfo)
        {
            if (string.IsNullOrWhiteSpace(userInfo))
            {
                return (null, null);
            }

            var decoded = DecodePercentEncodingRepeatedly(userInfo);
            try
            {
                var base64Decoded = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(decoded));
                if (!string.IsNullOrWhiteSpace(base64Decoded))
                {
                    decoded = base64Decoded;
                }
            }
            catch
            {
            }

            var parts = decoded.Split(':', 2);
            return parts.Length == 2 ? (parts[0], parts[1]) : (decoded, null);
        }

        private static Dictionary<string, string> ParseQuery(string query)
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var part in query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var pieces = part.Split('=', 2);
                result[DecodePercentEncodingRepeatedly(pieces[0])] =
                    DecodePercentEncodingRepeatedly(pieces.Length > 1 ? pieces[1] : "");
            }

            return result;
        }

        private static string? Read(Dictionary<string, string> query, string key)
        {
            return query.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value) ? value : null;
        }

        private static bool IsTrue(string? value)
        {
            return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
        }

        private static string DecodePercentEncodingRepeatedly(string value)
        {
            var decoded = value;
            for (var index = 0; index < 5; index += 1)
            {
                var next = Uri.UnescapeDataString(decoded);
                if (next == decoded)
                {
                    return decoded;
                }

                decoded = next;
            }

            return decoded;
        }

        private static string HashString(string value)
        {
            var hash = 7;
            foreach (var character in value)
            {
                hash = unchecked(hash * 31 + character);
            }

            return hash.ToString("x");
        }
    }
}
