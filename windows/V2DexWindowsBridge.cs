using System;
using System.Collections.Generic;
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
            var nodes = new[]
            {
                new Dictionary<string, object?>
                {
                    ["id"] = Guid.NewGuid().ToString("N"),
                    ["name"] = "Imported URI",
                    ["protocol"] = uri.StartsWith("vless://", StringComparison.OrdinalIgnoreCase) ? "vless" : "unknown",
                    ["server"] = "pending.windows.backend",
                    ["port"] = 443
                }
            };
            var result = new Dictionary<string, object?>
            {
                ["nodes"] = nodes
            };

            return Task.FromResult(JsonSerializer.Serialize(result));
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
    }
}
