using System;
using System.IO;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace V2Dex.Windows
{
    public sealed class WindowsTunnelRuntime
    {
        private TunnelStatusSnapshot snapshot = new TunnelStatusSnapshot();

        public async Task<TunnelStatusSnapshot> StartAsync(string configJson, string mode, string appRulesJson = "[]")
        {
            var runtimeDir = Path.Combine(Path.GetTempPath(), "v2dex-runtime");
            Directory.CreateDirectory(runtimeDir);
            var configPath = Path.Combine(runtimeDir, $"sing-box-{Guid.NewGuid():N}.json");
            await File.WriteAllTextAsync(configPath, configJson);

            snapshot = new TunnelStatusSnapshot
            {
                connected = false,
                connecting = false,
                mode = string.IsNullOrWhiteSpace(mode) ? "full" : mode,
                backend = mode == "per-app" ? "app-proxy" : "system-proxy",
                lastError = "Windows native tunnel runtime is not implemented yet.",
                activeConfigPath = configPath,
                binaryPath = null,
                proxyHost = "127.0.0.1",
                proxyPort = 2080
            };

            return snapshot;
        }

        public Task StopAsync()
        {
            snapshot.connected = false;
            snapshot.connecting = false;
            snapshot.proxyHost = null;
            snapshot.proxyPort = null;
            snapshot.backend = null;

            TryClearSystemProxySettings();
            return Task.CompletedTask;
        }

        public Task<TunnelStatusSnapshot> GetStatusAsync()
        {
            return Task.FromResult(snapshot);
        }

        public async Task<TunnelHttpLatencyResult> TestTunnelHttpLatencyAsync(string url)
        {
            var startedAt = Stopwatch.StartNew();
            using var client = CreateProxyHttpClient();
            using var request = new HttpRequestMessage(HttpMethod.Get, url.Trim());
            request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
            request.Headers.Pragma.ParseAdd("no-cache");
            request.Headers.UserAgent.ParseAdd("V2Dex/1.0");

            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
            if ((int)response.StatusCode < 200 || (int)response.StatusCode > 399)
            {
                throw new InvalidOperationException($"HTTP probe failed with status {(int)response.StatusCode}.");
            }

            var latencyMs = Math.Max((int)startedAt.ElapsedMilliseconds, 1);
            return new TunnelHttpLatencyResult
            {
                message = $"Reached {request.RequestUri?.Host ?? url} in {latencyMs}ms",
                latencyMs = latencyMs,
                url = url
            };
        }

        public async Task<TunnelIpInfo> GetTunnelIpInfoAsync()
        {
            var endpoints = new[]
            {
                "http://ip-api.com/json/?fields=status,country,countryCode,query,message",
                "https://ipwho.is/"
            };
            Exception? lastError = null;

            using var client = CreateProxyHttpClient();
            foreach (var endpoint in endpoints)
            {
                try
                {
                    var payload = await client.GetStringAsync(endpoint);
                    var result = ParseIpInfoPayload(payload);
                    if (result != null)
                    {
                        return result;
                    }
                }
                catch (Exception error)
                {
                    lastError = error;
                }
            }

            throw new InvalidOperationException(lastError?.Message ?? "IP lookup failed.");
        }

        public Task CopyToClipboardAsync(string value)
        {
            var process = new Process();
            process.StartInfo.FileName = "powershell.exe";
            process.StartInfo.Arguments = "-NoProfile -Command Set-Clipboard";
            process.StartInfo.RedirectStandardInput = true;
            process.StartInfo.CreateNoWindow = true;
            process.StartInfo.UseShellExecute = false;
            process.Start();
            process.StandardInput.Write(value);
            process.StandardInput.Close();
            process.WaitForExit(5000);
            return Task.CompletedTask;
        }

        private static HttpClient CreateProxyHttpClient()
        {
            var handler = new HttpClientHandler
            {
                Proxy = new WebProxy("http://127.0.0.1:2080"),
                UseProxy = true
            };
            return new HttpClient(handler)
            {
                Timeout = TimeSpan.FromSeconds(15)
            };
        }

        private static TunnelIpInfo? ParseIpInfoPayload(string payload)
        {
            using var document = JsonDocument.Parse(payload);
            var root = document.RootElement;

            if (root.TryGetProperty("status", out var status) &&
                status.ValueKind == JsonValueKind.String &&
                status.GetString() != "success")
            {
                return null;
            }

            if (root.TryGetProperty("success", out var success) &&
                success.ValueKind == JsonValueKind.False)
            {
                return null;
            }

            var result = new TunnelIpInfo
            {
                ip = ReadString(root, "query") ?? ReadString(root, "ip"),
                country = ReadString(root, "country"),
                countryCode = ReadString(root, "countryCode") ?? ReadString(root, "country_code")
            };

            return result.ip == null && result.country == null && result.countryCode == null ? null : result;
        }

        private static string? ReadString(JsonElement root, string key)
        {
            return root.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
        }

        private static void TryClearSystemProxySettings()
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                    writable: true
                );

                key?.SetValue("ProxyEnable", 0, RegistryValueKind.DWord);
                key?.DeleteValue("ProxyServer", throwOnMissingValue: false);
                key?.DeleteValue("ProxyOverride", throwOnMissingValue: false);
                key?.DeleteValue("AutoConfigURL", throwOnMissingValue: false);
            }
            catch
            {
            }

            try
            {
                var process = new Process();
                process.StartInfo.FileName = "netsh";
                process.StartInfo.Arguments = "winhttp reset proxy";
                process.StartInfo.CreateNoWindow = true;
                process.StartInfo.UseShellExecute = false;
                process.Start();
                process.WaitForExit(5000);
            }
            catch
            {
            }
        }
    }
}
