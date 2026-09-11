using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using V2Dex.Windows;

namespace V2Dex.WindowsApp;

public partial class MainWindow : Window
{
    private readonly V2DexWindowsBridge bridge = new();
    private readonly AppState state = new();
    private readonly JsonSerializerOptions jsonOptions = new() { PropertyNameCaseInsensitive = true, WriteIndented = true };
    private readonly string statePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "V2Dex",
        "windows-state.json"
    );

    public MainWindow()
    {
        InitializeComponent();
        DataContext = state;
        Loaded += (_, _) => LoadState();
    }

    private void WindowDragMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            DragMove();
        }
    }

    private async void ImportClick(object sender, RoutedEventArgs e)
    {
        var dialog = new ImportDialog { Owner = this };
        if (dialog.ShowDialog() != true || string.IsNullOrWhiteSpace(dialog.ImportText))
        {
            return;
        }

        try
        {
            state.StatusLine = "Importing config...";
            var json = await bridge.ImportFromUri(dialog.ImportText.Trim());
            var payload = JsonSerializer.Deserialize<ImportPayload>(json, jsonOptions);
            if (payload?.nodes.Length is null or 0)
            {
                state.StatusLine = "No supported config found";
                return;
            }

            foreach (var node in payload.nodes)
            {
                var profile = new ProfileItem
                {
                    Node = node,
                    Title = string.IsNullOrWhiteSpace(node.name) ? $"{node.protocol.ToUpperInvariant()} {node.server}" : node.name,
                    CountryCode = InferCountryCode($"{node.name} {node.server}")
                };
                state.Profiles.Insert(0, profile);
            }

            SelectProfile(state.Profiles[0]);
            state.StatusLine = $"Imported {payload.nodes.Length} config(s)";
            SaveState();
        }
        catch (Exception error)
        {
            state.StatusLine = $"Import failed: {error.Message}";
        }
    }

    private async void PowerClick(object sender, RoutedEventArgs e)
    {
        if (state.Connecting)
        {
            return;
        }

        if (state.Connected)
        {
            await DisconnectAsync();
            return;
        }

        await ConnectAsync();
    }

    private async Task ConnectAsync()
    {
        if (state.ActiveProfile?.Node is not { } node)
        {
            state.StatusLine = "No config selected";
            return;
        }

        try
        {
            state.Connecting = true;
            state.StatusLine = "Starting local proxy...";
            var config = SingBoxConfigFactory.Build(node);
            var snapshot = await bridge.StartTunnel(config, "full", "[]");
            state.Connected = snapshot.connected;
            state.StatusLine = snapshot.connected ? $"Connected via {state.ActiveProfile.Title}" : snapshot.lastError ?? "Connect failed";

            if (snapshot.connected)
            {
                await RefreshExitInfoAsync();
                await PingActiveAsync();
            }
        }
        catch (Exception error)
        {
            state.Connected = false;
            state.StatusLine = $"Connect failed: {error.Message}";
        }
        finally
        {
            state.Connecting = false;
        }
    }

    private async Task DisconnectAsync()
    {
        try
        {
            state.Connecting = true;
            state.StatusLine = "Disconnecting...";
            await bridge.StopTunnel();
            state.Connected = false;
            state.CountryText = "Proxy";
            state.StatusLine = "Disconnected. Windows proxy is off.";
        }
        catch (Exception error)
        {
            state.StatusLine = $"Disconnect warning: {error.Message}";
        }
        finally
        {
            state.Connecting = false;
        }
    }

    private async void PingAllClick(object sender, RoutedEventArgs e)
    {
        if (state.Profiles.Count == 0)
        {
            state.StatusLine = "No saved configs to ping.";
            return;
        }

        state.StatusLine = "Pinging saved configs...";
        foreach (var profile in state.Profiles)
        {
            profile.Pinging = true;
        }

        foreach (var profile in state.Profiles.ToArray())
        {
            await PingProfileAsync(profile);
            SortProfilesByLatency();
        }

        state.StatusLine = "Ping all complete.";
        SaveState();
    }

    private async Task PingActiveAsync()
    {
        if (state.ActiveProfile is not { } profile)
        {
            return;
        }
        await PingProfileAsync(profile);
        state.LastPingText = profile.LatencyMs is null || profile.LatencyMs > 850 ? "TO ms" : $"{profile.LatencyMs} ms";
    }

    private async Task PingProfileAsync(ProfileItem profile)
    {
        try
        {
            profile.Pinging = true;
            var json = JsonSerializer.Serialize(profile.Node, jsonOptions);
            var result = await bridge.TestServerConnection(json);
            profile.LatencyMs = result.latencyMs;
            profile.CountryCode ??= InferCountryCode($"{profile.Title} {profile.Node.server}");
        }
        catch
        {
            profile.LatencyMs = 9999;
        }
        finally
        {
            profile.Pinging = false;
        }
    }

    private async Task RefreshExitInfoAsync()
    {
        try
        {
            var info = await bridge.GetTunnelIpInfo();
            state.CountryText = string.IsNullOrWhiteSpace(info.country) ? info.countryCode ?? "Proxy" : info.country;
            if (state.ActiveProfile is not null && !string.IsNullOrWhiteSpace(info.countryCode))
            {
                state.ActiveProfile.CountryCode = info.countryCode;
            }
        }
        catch
        {
            state.CountryText = "Proxy";
        }
    }

    private void ProfileSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (((ListBox)sender).SelectedItem is ProfileItem profile)
        {
            SelectProfile(profile);
        }
    }

    private void ConnectionClick(object sender, RoutedEventArgs e)
    {
        MessageBox.Show(
            this,
            "HTTP/SOCKS local proxy: 127.0.0.1:2080\nWindows system proxy is enabled while connected.",
            "Connection",
            MessageBoxButton.OK,
            MessageBoxImage.Information
        );
    }

    private void RouterToggleClick(object sender, RoutedEventArgs e)
    {
        RouterToggle.IsChecked = false;
        state.StatusLine = "Router SOCKS mode is not enabled in the Windows backend yet.";
    }

    private void SelectProfile(ProfileItem profile)
    {
        foreach (var item in state.Profiles)
        {
            item.Selected = item == profile;
        }

        state.ActiveProfile = profile;
        state.LastPingText = profile.LatencyMs is null || profile.LatencyMs > 850 ? "-- ms" : $"{profile.LatencyMs} ms";
        state.StatusLine = $"Selected {profile.Title}";
    }

    private void SortProfilesByLatency()
    {
        var sorted = state.Profiles
            .OrderBy(item => item.LatencyMs is null ? 8000 : item.LatencyMs > 850 ? 9999 : item.LatencyMs)
            .ToList();

        state.Profiles.Clear();
        foreach (var item in sorted)
        {
            state.Profiles.Add(item);
        }
    }

    private void LoadState()
    {
        try
        {
            if (!File.Exists(statePath))
            {
                return;
            }

            var profiles = JsonSerializer.Deserialize<ProfileItem[]>(File.ReadAllText(statePath), jsonOptions) ?? [];
            foreach (var profile in profiles)
            {
                state.Profiles.Add(profile);
            }

            if (state.Profiles.Count > 0)
            {
                SelectProfile(state.Profiles[0]);
            }
        }
        catch
        {
            state.StatusLine = "Saved configs could not be loaded";
        }
    }

    private void SaveState()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(statePath)!);
        File.WriteAllText(statePath, JsonSerializer.Serialize(state.Profiles.ToArray(), jsonOptions));
    }

    private static string? InferCountryCode(string value)
    {
        var lower = value.ToLowerInvariant();
        if (lower.Contains("usa") || lower.Contains("united states") || lower.Contains("america")) return "US";
        if (lower.Contains("canada")) return "CA";
        if (lower.Contains("germany") || lower.Contains("deutschland")) return "DE";
        if (lower.Contains("iran")) return "IR";
        if (lower.Contains("france")) return "FR";
        if (lower.Contains("turkey")) return "TR";
        if (lower.Contains("netherlands")) return "NL";
        if (lower.Contains("uk") || lower.Contains("united kingdom")) return "GB";
        return null;
    }
}

public sealed class ImportDialog : Window
{
    private readonly TextBox textBox = new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        MinHeight = 180,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        Background = System.Windows.Media.Brushes.Black,
        Foreground = System.Windows.Media.Brushes.White,
        BorderThickness = new Thickness(0),
        Padding = new Thickness(12),
        FontFamily = new System.Windows.Media.FontFamily("Consolas")
    };

    public string ImportText => textBox.Text;

    public ImportDialog()
    {
        Title = "Import Config";
        Width = 460;
        Height = 340;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(9, 10, 24));

        var root = new Grid { Margin = new Thickness(22) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        root.Children.Add(new TextBlock
        {
            Text = "Import Config",
            Foreground = System.Windows.Media.Brushes.White,
            FontSize = 24,
            FontWeight = FontWeights.Black,
            Margin = new Thickness(0, 0, 0, 14)
        });

        Grid.SetRow(textBox, 1);
        root.Children.Add(textBox);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        var cancel = new Button { Content = "Cancel", Width = 88, Height = 36, Margin = new Thickness(0, 0, 10, 0) };
        cancel.Click += (_, _) => DialogResult = false;
        var import = new Button { Content = "Import", Width = 88, Height = 36 };
        import.Click += (_, _) => DialogResult = true;
        actions.Children.Add(cancel);
        actions.Children.Add(import);
        Grid.SetRow(actions, 2);
        root.Children.Add(actions);

        Content = root;
    }
}
