using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace V2Dex.WindowsApp;

public sealed class ProxyNode
{
    public string id { get; set; } = "";
    public string name { get; set; } = "";
    [JsonPropertyName("protocol")]
    public string protocol { get; set; } = "vless";
    public string server { get; set; } = "";
    public int port { get; set; } = 443;
    public string? security { get; set; }
    public string? transport { get; set; }
    public string? sni { get; set; }
    public string? path { get; set; }
    public string? uuid { get; set; }
    public string? password { get; set; }
    public string? wsHost { get; set; }
    public string? flow { get; set; }
    public bool? allowInsecure { get; set; }
    public string? publicKey { get; set; }
    public string? shortId { get; set; }
    public string? fingerprint { get; set; }
    public string[]? alpn { get; set; }
    public string? rawUri { get; set; }
}

public sealed class ImportPayload
{
    public ProxyNode[] nodes { get; set; } = [];
}

public sealed class ProfileItem : INotifyPropertyChanged
{
    private int? latencyMs;
    private bool pinging;
    private bool selected;
    private string? countryCode;

    public string Id { get; init; } = Guid.NewGuid().ToString("N");
    public required ProxyNode Node { get; init; }
    public string Title { get; set; } = "";
    public string Endpoint => $"{Node.server}:{Node.port}";
    public string Protocol => Node.protocol.ToUpperInvariant();

    public int? LatencyMs
    {
        get => latencyMs;
        set { latencyMs = value; OnPropertyChanged(); OnPropertyChanged(nameof(LatencyText)); OnPropertyChanged(nameof(LatencyBrushKey)); }
    }

    public bool Pinging
    {
        get => pinging;
        set { pinging = value; OnPropertyChanged(); OnPropertyChanged(nameof(LatencyText)); }
    }

    public bool Selected
    {
        get => selected;
        set { selected = value; OnPropertyChanged(); }
    }

    public string? CountryCode
    {
        get => countryCode;
        set { countryCode = value; OnPropertyChanged(); OnPropertyChanged(nameof(FlagText)); }
    }

    public string FlagText => CountryCodeToFlag(CountryCode);
    public string LatencyText => Pinging ? "..." : LatencyMs is null ? "--" : LatencyMs > 850 ? "TO" : $"{LatencyMs} ms";
    public string LatencyBrushKey => LatencyMs is null ? "TextMuted" : LatencyMs < 750 ? "LatencyGood" : "LatencyWarn";

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private static string CountryCodeToFlag(string? code)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Length != 2)
        {
            return "◎";
        }

        var upper = code.ToUpperInvariant();
        return string.Concat(upper.Select(ch => char.ConvertFromUtf32(0x1F1E6 + ch - 'A')));
    }
}

public sealed class AppState : INotifyPropertyChanged
{
    private ProfileItem? activeProfile;
    private bool connected;
    private bool connecting;
    private string statusLine = "Loaded saved config";
    private string countryText = "Proxy";
    private string lastPingText = "-- ms";

    public ObservableCollection<ProfileItem> Profiles { get; } = [];

    public ProfileItem? ActiveProfile
    {
        get => activeProfile;
        set { activeProfile = value; OnPropertyChanged(); OnPropertyChanged(nameof(HeaderTitle)); }
    }

    public bool Connected
    {
        get => connected;
        set { connected = value; OnPropertyChanged(); OnPropertyChanged(nameof(PowerText)); }
    }

    public bool Connecting
    {
        get => connecting;
        set { connecting = value; OnPropertyChanged(); OnPropertyChanged(nameof(PowerText)); }
    }

    public string StatusLine
    {
        get => statusLine;
        set { statusLine = value; OnPropertyChanged(); }
    }

    public string CountryText
    {
        get => countryText;
        set { countryText = value; OnPropertyChanged(); }
    }

    public string LastPingText
    {
        get => lastPingText;
        set { lastPingText = value; OnPropertyChanged(); }
    }

    public string HeaderTitle => ActiveProfile?.Title ?? "No config selected";
    public string PowerText => Connecting ? "..." : "⏻";

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
