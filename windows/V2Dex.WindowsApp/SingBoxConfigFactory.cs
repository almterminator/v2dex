using System.Text.Json;

namespace V2Dex.WindowsApp;

public static class SingBoxConfigFactory
{
    public static string Build(ProxyNode node)
    {
        var config = new Dictionary<string, object?>
        {
            ["log"] = new Dictionary<string, object?> { ["level"] = "warn" },
            ["dns"] = new Dictionary<string, object?>
            {
                ["servers"] = new object[] { new Dictionary<string, object?> { ["tag"] = "local", ["type"] = "local" } },
                ["final"] = "local",
                ["strategy"] = "prefer_ipv4"
            },
            ["inbounds"] = new object[]
            {
                new Dictionary<string, object?>
                {
                    ["type"] = "mixed",
                    ["tag"] = "mixed-in",
                    ["listen"] = "127.0.0.1",
                    ["listen_port"] = 2080,
                    ["set_system_proxy"] = false
                }
            },
            ["outbounds"] = new object[]
            {
                BuildProxyOutbound(node),
                new Dictionary<string, object?> { ["tag"] = "direct", ["type"] = "direct" }
            },
            ["route"] = new Dictionary<string, object?>
            {
                ["auto_detect_interface"] = true,
                ["final"] = "proxy",
                ["rules"] = new object[]
                {
                    new Dictionary<string, object?> { ["ip_is_private"] = true, ["action"] = "route", ["outbound"] = "direct" }
                }
            }
        };

        return JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true });
    }

    private static Dictionary<string, object?> BuildProxyOutbound(ProxyNode node)
    {
        return node.protocol switch
        {
            "vless" => BuildVlessOutbound(node),
            "socks5" => new Dictionary<string, object?>
            {
                ["tag"] = "proxy",
                ["type"] = "socks",
                ["server"] = node.server,
                ["server_port"] = node.port,
                ["username"] = node.username,
                ["password"] = node.password
            },
            "http" or "https" => new Dictionary<string, object?>
            {
                ["tag"] = "proxy",
                ["type"] = "http",
                ["server"] = node.server,
                ["server_port"] = node.port,
                ["username"] = node.username,
                ["password"] = node.password
            },
            _ => BuildVlessOutbound(node)
        };
    }

    private static Dictionary<string, object?> BuildVlessOutbound(ProxyNode node)
    {
        var outbound = new Dictionary<string, object?>
        {
            ["tag"] = "proxy",
            ["type"] = "vless",
            ["server"] = node.server,
            ["server_port"] = node.port,
            ["uuid"] = node.uuid,
            ["flow"] = string.IsNullOrWhiteSpace(node.flow) ? null : node.flow,
            ["tls"] = BuildTls(node),
            ["transport"] = BuildTransport(node)
        };

        return outbound.Where(pair => pair.Value != null).ToDictionary(pair => pair.Key, pair => pair.Value);
    }

    private static Dictionary<string, object?>? BuildTls(ProxyNode node)
    {
        if (!string.Equals(node.security, "tls", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(node.security, "reality", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var tls = new Dictionary<string, object?>
        {
            ["enabled"] = true,
            ["server_name"] = string.IsNullOrWhiteSpace(node.sni) ? node.wsHost : node.sni,
            ["insecure"] = node.allowInsecure == true,
            ["utls"] = string.IsNullOrWhiteSpace(node.fingerprint)
                ? null
                : new Dictionary<string, object?> { ["enabled"] = true, ["fingerprint"] = node.fingerprint }
        };

        return tls.Where(pair => pair.Value != null).ToDictionary(pair => pair.Key, pair => pair.Value);
    }

    private static Dictionary<string, object?>? BuildTransport(ProxyNode node)
    {
        if (string.Equals(node.transport, "ws", StringComparison.OrdinalIgnoreCase))
        {
            return new Dictionary<string, object?>
            {
                ["type"] = "ws",
                ["path"] = string.IsNullOrWhiteSpace(node.path) ? "/" : node.path,
                ["headers"] = string.IsNullOrWhiteSpace(node.wsHost)
                    ? null
                    : new Dictionary<string, object?> { ["Host"] = node.wsHost }
            }.Where(pair => pair.Value != null).ToDictionary(pair => pair.Key, pair => pair.Value);
        }

        if (string.Equals(node.transport, "grpc", StringComparison.OrdinalIgnoreCase))
        {
            return new Dictionary<string, object?>
            {
                ["type"] = "grpc",
                ["service_name"] = (node.path ?? "grpc").TrimStart('/')
            };
        }

        return null;
    }
}
