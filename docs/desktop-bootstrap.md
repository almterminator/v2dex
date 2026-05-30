# React Native Desktop Bootstrap

This repository now treats React Native as the shared desktop frontend for:

- macOS via `react-native-macos`
- Windows via `react-native-windows`

## Current status

- Shared TypeScript desktop UI exists in `src/`
- Native macOS tunnel scaffolding exists in `native/`
- Windows native bridge and tunnel backend are not implemented yet
- Installer output is **not** ready for Windows or production macOS distribution

## Recommended bootstrap flow

The current React Native versions in this repo are aligned around the 0.76 generation.

### macOS host app

```bash
npm install
npm run bootstrap:macos
npm run macos
```

### Windows host app

Run this on a Windows machine with Visual Studio and the React Native Windows prerequisites installed:

```bash
npm install
npm run bootstrap:windows
npm run windows
```

## Native split

### macOS

- `PacketTunnelProvider`
- `NETunnelProviderManager`
- bundled `sing-box`
- entitlement and signing flow

### Windows

- Wintun or equivalent TUN integration
- Windows service or elevated helper for tunnel lifecycle
- desktop app process routing implementation
- `sing-box` Windows binary bundling

## Packaging targets

### macOS

- development build: `.app`
- user distribution: signed `.dmg`

### Windows

- development build: unpackaged app or MSBuild output
- user distribution: `MSIX` or signed installer

Do not treat either installer as ready until:

1. native tunnel works end-to-end
2. subscription import works against real configs
3. latency and reconnect are validated
4. installers are signed and launch cleanly on target machines
