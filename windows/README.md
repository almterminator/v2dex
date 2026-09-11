# V2Dex Windows

This folder contains the Windows desktop implementation for V2Dex.

## Components

- `V2DexWindowsBridge`
  - native C# bridge for import, tunnel start/stop, status, ping, IP lookup, and clipboard.
- `WindowsTunnelRuntime`
  - launches `sing-box.exe`, enables Windows system proxy, and clears proxy settings on stop.
- `V2Dex.WindowsApp`
  - WPF desktop app with the same compact glass UI direction as the current macOS app.

## Build

Build on Windows with .NET SDK 8.0 or newer:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\build-windows-app.ps1
```

The output is written to:

```text
windows\artifacts\V2Dex.WindowsApp-win-x64
```

Place `sing-box.exe` next to `V2Dex.exe`, or set `V2DEX_SING_BOX_PATH`.

## Current Scope

- Supports the existing user-space Windows system proxy approach.
- Connect starts `sing-box` and points Windows proxy settings at `127.0.0.1:2080`.
- Disconnect stops `sing-box` and clears Windows proxy settings.
- The WPF UI includes import, saved configs, ping all, connect/disconnect, active ping, and exit country display.
- Packet-level VPN/Wintun and real per-app routing still require a dedicated Windows tunnel/service implementation.
