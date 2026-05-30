# Architecture Notes

## Runtime split

- React Native macOS handles UI, profile management, node selection, and user intent.
- Native Swift layer owns tunnel lifecycle, app discovery, privileged actions, and NEVPN integration.
- `PacketTunnelProvider` owns TUN setup and hands traffic to `sing-box`.

## Recommended native bridge surface

- `importFromClipboard()`
- `importFromURI(uri: String)`
- `refreshSubscriptions()`
- `discoverInstalledApplications()`
- `startTunnel(config: String, mode: String)`
- `stopTunnel()`
- `getTunnelStatus()`
- `runLatencyTest(nodeIds: [String])`

## Reliability priorities

- Keep reconnect policy native-side to avoid JS runtime dependency during recovery
- Use last-known-good generated config for fast restart
- Persist the selected node and mode atomically
- Collect health signals from `sing-box` stdout/stderr and exit status
