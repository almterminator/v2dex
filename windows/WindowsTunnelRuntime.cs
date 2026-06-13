using System;
using System.IO;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace V2Dex.Windows
{
    public sealed class WindowsTunnelRuntime
    {
        private TunnelStatusSnapshot snapshot = new TunnelStatusSnapshot();
        private Process? tunnelProcess;
        private string? activeConfigPath;

        public async Task<TunnelStatusSnapshot> StartAsync(string configJson, string mode, string appRulesJson = "[]")
        {
            var runtimeDir = Path.Combine(Path.GetTempPath(), "v2dex-runtime");
            Directory.CreateDirectory(runtimeDir);
            var configPath = Path.Combine(runtimeDir, $"sing-box-{Guid.NewGuid():N}.json");
            await File.WriteAllTextAsync(configPath, configJson);
            var requestedMode = string.IsNullOrWhiteSpace(mode) ? "full" : mode;
            var binaryPath = FindSingBoxExecutable();

            snapshot = new TunnelStatusSnapshot
            {
                connected = false,
                connecting = true,
                mode = requestedMode,
                backend = "system-proxy",
                lastError = null,
                activeConfigPath = configPath,
                binaryPath = binaryPath,
                proxyHost = "127.0.0.1",
                proxyPort = 2080
            };

            try
            {
                await StopTunnelProcessAsync(clearProxy: false);
                tunnelProcess = StartSingBox(runtimeDir, configPath, binaryPath);
                activeConfigPath = configPath;
                await WaitForTcpPortAsync("127.0.0.1", 2080, TimeSpan.FromSeconds(8));
                TrySetSystemProxySettings("127.0.0.1", 2080);

                snapshot.connected = true;
                snapshot.connecting = false;
                snapshot.lastConnectedAt = DateTimeOffset.UtcNow.ToString("O");
                snapshot.lastError = null;
            }
            catch (Exception error)
            {
                await StopTunnelProcessAsync(clearProxy: true);
                snapshot.connected = false;
                snapshot.connecting = false;
                snapshot.lastError = error.Message;
            }

            return snapshot;
        }

        public async Task StopAsync()
        {
            await StopTunnelProcessAsync(clearProxy: true);
            snapshot.connected = false;
            snapshot.connecting = false;
            snapshot.proxyHost = null;
            snapshot.proxyPort = null;
            snapshot.backend = null;
        }

        public Task<TunnelStatusSnapshot> GetStatusAsync()
        {
            return Task.FromResult(snapshot);
        }

        public async Task<TunnelHttpLatencyResult> TestServerConnectionAsync(string nodeJson)
        {
            using var document = JsonDocument.Parse(nodeJson);
            var root = document.RootElement;

            if (root.TryGetProperty("probeConfigJson", out var probeConfig) &&
                probeConfig.ValueKind == JsonValueKind.String &&
                !string.IsNullOrWhiteSpace(probeConfig.GetString()))
            {
                var probePort = root.TryGetProperty("probePort", out var portElement) &&
                    portElement.ValueKind == JsonValueKind.Number &&
                    portElement.TryGetInt32(out var parsedPort)
                        ? parsedPort
                        : Random.Shared.Next(45000, 46000);

                var latencyMs = await TestProxyHttpProbeAsync(probeConfig.GetString()!, probePort);
                return new TunnelHttpLatencyResult
                {
                    message = $"Reached HTTP probe in {latencyMs}ms",
                    latencyMs = latencyMs
                };
            }

            var node = root.TryGetProperty("node", out var nestedNode) && nestedNode.ValueKind == JsonValueKind.Object
                ? nestedNode
                : root;
            var server = ReadString(node, "server") ?? throw new InvalidOperationException("Node server is missing.");
            var port = node.TryGetProperty("port", out var fallbackPort) && fallbackPort.TryGetInt32(out var directPort)
                ? directPort
                : 443;
            var startedAt = Stopwatch.StartNew();

            using var client = new TcpClient();
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await client.ConnectAsync(server, port, cancellation.Token);

            return new TunnelHttpLatencyResult
            {
                message = $"Connected in {Math.Max((int)startedAt.ElapsedMilliseconds, 1)}ms",
                latencyMs = Math.Max((int)startedAt.ElapsedMilliseconds, 1)
            };
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

        private static async Task<int> TestProxyHttpProbeAsync(string configJson, int proxyPort)
        {
            var runtimeDir = Path.Combine(Path.GetTempPath(), "v2dex-probe-runtime");
            Directory.CreateDirectory(runtimeDir);
            var configPath = Path.Combine(runtimeDir, $"sing-box-probe-{Guid.NewGuid():N}.json");
            await File.WriteAllTextAsync(configPath, configJson);

            Process? process = null;
            try
            {
                process = StartSingBox(runtimeDir, configPath);
                await WaitForTcpPortAsync("127.0.0.1", proxyPort, TimeSpan.FromSeconds(5));
                return await ProbeHttpLatencyAsync(proxyPort);
            }
            finally
            {
                try
                {
                    if (process is { HasExited: false })
                    {
                        process.Kill(entireProcessTree: true);
                        await process.WaitForExitAsync();
                    }
                }
                catch
                {
                }

                try
                {
                    File.Delete(configPath);
                }
                catch
                {
                }
            }
        }

        private static Process StartSingBox(string runtimeDir, string configPath)
        {
            return StartSingBox(runtimeDir, configPath, FindSingBoxExecutable());
        }

        private static Process StartSingBox(string runtimeDir, string configPath, string binaryPath)
        {
            var process = new Process();
            process.StartInfo.FileName = binaryPath;
            process.StartInfo.Arguments = $"run -c \"{configPath}\"";
            process.StartInfo.WorkingDirectory = runtimeDir;
            process.StartInfo.RedirectStandardOutput = true;
            process.StartInfo.RedirectStandardError = true;
            process.StartInfo.CreateNoWindow = true;
            process.StartInfo.UseShellExecute = false;

            if (!process.Start())
            {
                throw new InvalidOperationException("Could not start sing-box.");
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.WhenAll(
                        process.StandardOutput.ReadToEndAsync(),
                        process.StandardError.ReadToEndAsync()
                    );
                }
                catch
                {
                }
            });

            return process;
        }

        private async Task StopTunnelProcessAsync(bool clearProxy)
        {
            try
            {
                if (tunnelProcess is { HasExited: false })
                {
                    tunnelProcess.Kill(entireProcessTree: true);
                    await tunnelProcess.WaitForExitAsync();
                }
            }
            catch
            {
            }
            finally
            {
                tunnelProcess?.Dispose();
                tunnelProcess = null;
            }

            if (clearProxy)
            {
                TryClearSystemProxySettings();
            }

            var staleConfig = activeConfigPath;
            activeConfigPath = null;
            if (!string.IsNullOrWhiteSpace(staleConfig))
            {
                try
                {
                    File.Delete(staleConfig);
                }
                catch
                {
                }
            }
        }

        private static async Task<int> ProbeHttpLatencyAsync(int proxyPort)
        {
            var endpoints = new[]
            {
                "https://www.youtube.com/generate_204",
                "https://www.google.com/generate_204"
            };
            Exception? lastError = null;

            foreach (var endpoint in endpoints)
            {
                try
                {
                    var startedAt = Stopwatch.StartNew();
                    using var client = CreateProxyHttpClient(proxyPort);
                    using var request = new HttpRequestMessage(HttpMethod.Get, $"{endpoint}?t={DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}");
                    request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
                    request.Headers.Pragma.ParseAdd("no-cache");
                    request.Headers.UserAgent.ParseAdd("V2Dex/1.0");

                    using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
                    if ((int)response.StatusCode < 200 || (int)response.StatusCode > 399)
                    {
                        throw new InvalidOperationException($"HTTP probe failed with status {(int)response.StatusCode}.");
                    }

                    return Math.Max((int)startedAt.ElapsedMilliseconds, 1);
                }
                catch (Exception error)
                {
                    lastError = error;
                }
            }

            throw new InvalidOperationException(lastError?.Message ?? "HTTP probe timed out.");
        }

        private static async Task WaitForTcpPortAsync(string host, int port, TimeSpan timeout)
        {
            var deadline = DateTimeOffset.UtcNow + timeout;
            Exception? lastError = null;

            while (DateTimeOffset.UtcNow < deadline)
            {
                try
                {
                    using var client = new TcpClient();
                    using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(250));
                    await client.ConnectAsync(host, port, cancellation.Token);
                    return;
                }
                catch (Exception error)
                {
                    lastError = error;
                    await Task.Delay(100);
                }
            }

            throw new InvalidOperationException(lastError?.Message ?? $"Proxy port {port} did not open.");
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
            return CreateProxyHttpClient(2080);
        }

        private static HttpClient CreateProxyHttpClient(int proxyPort)
        {
            var handler = new HttpClientHandler
            {
                Proxy = new WebProxy($"http://127.0.0.1:{proxyPort}"),
                UseProxy = true
            };
            return new HttpClient(handler)
            {
                Timeout = TimeSpan.FromSeconds(15)
            };
        }

        private static string FindSingBoxExecutable()
        {
            var configured = Environment.GetEnvironmentVariable("V2DEX_SING_BOX_PATH");
            var candidates = new[]
            {
                configured,
                Path.Combine(AppContext.BaseDirectory, "sing-box.exe"),
                Path.Combine(AppContext.BaseDirectory, "Resources", "sing-box.exe"),
                Path.Combine(Directory.GetCurrentDirectory(), ".local", "bin", "sing-box.exe"),
                "sing-box.exe"
            };

            foreach (var candidate in candidates)
            {
                if (!string.IsNullOrWhiteSpace(candidate) &&
                    (File.Exists(candidate) || candidate.Equals("sing-box.exe", StringComparison.OrdinalIgnoreCase)))
                {
                    return candidate;
                }
            }

            throw new FileNotFoundException("sing-box Windows binary was not found.");
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

        private static void TrySetSystemProxySettings(string host, int port)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                    writable: true
                );

                key?.SetValue("ProxyEnable", 1, RegistryValueKind.DWord);
                key?.SetValue("ProxyServer", $"{host}:{port}", RegistryValueKind.String);
                key?.SetValue("ProxyOverride", "<local>", RegistryValueKind.String);
                key?.DeleteValue("AutoConfigURL", throwOnMissingValue: false);
            }
            catch
            {
            }

            try
            {
                var process = new Process();
                process.StartInfo.FileName = "netsh";
                process.StartInfo.Arguments = $"winhttp set proxy {host}:{port} \"<local>\"";
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
