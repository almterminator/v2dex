# V2Dex

V2Dex is a cross-platform proxy client for Android and macOS, built around an Xray-compatible core, native platform backends, and a shared React Native interface.

The app focuses on practical per-app routing: users can import proxy profiles, select nodes, and route selected applications through the tunnel while keeping the rest of the system on the normal network path.

## Highlights

- Xray/V2Ray-style profile parsing and config generation
- Android VPNService integration for per-app routing
- macOS native bridge and desktop packaging
- Shared React Native UI for node selection, status, routing controls, and config preview
- Installer artifacts for Android APK and macOS DMG releases
- Native backend experiments for macOS Network Extension and desktop proxy control

This repository contains an active prototype. The Android and macOS builds are usable development artifacts, while production distribution still needs final signing, notarization, and release hardening.

## Architecture

- `src/`
  - shared React Native UI
  - app state, models, services, and screen composition
- `android/`
  - Android host app, VPNService, bridge module, and bundled native tunnel assets
- `native/V2DexCore/`
  - Swift package for parsing/import/config generation and tunnel orchestration
- `native/V2DexNetworkExtension/`
- `PacketTunnelProvider` skeleton for macOS packet tunnel mode
- `Sources/V2DexApp/`
  - native macOS prototype app kept for local packaging and exploration
- `macos/`
  - React Native macOS host project and native bridge wiring
- `docs/`
  - implementation notes and next steps

## Key design decisions

- Routing is designed around full-tunnel and per-application modes.
- Android uses platform VPN APIs to control which apps enter the tunnel.
- macOS keeps native tunnel/proxy control separated from the shared UI.
- Core config generation is centralized to reduce drift between platforms.
- The frontend stays platform-neutral while tunnel lifecycle and permissions remain native.

## Release Artifacts

Published releases include:

- `app-release.apk` for Android
- `V2Dex.dmg` for macOS

See [desktop-bootstrap.md](docs/desktop-bootstrap.md) for the desktop bootstrap flow.
See [installers-status.md](docs/installers-status.md) for the exact current installer state.

## Current build output

To generate a self-contained macOS app bundle and DMG for end users:

```bash
zsh scripts/build_dmg.sh
```

To sign the app and notarize the DMG for distribution:

```bash
V2DEX_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
zsh scripts/sign_app.sh

V2DEX_NOTARY_PROFILE="your-notarytool-profile" \
zsh scripts/notarize_dmg.sh
```

Current macOS artifacts are written to:

- `.build-artifacts/V2Dex.app`
- `.build-artifacts/V2Dex.dmg`

These are still unsigned prototype artifacts, not final notarized installers.

## Next steps

1. Complete production signing and notarization for macOS.
2. Harden Android release signing and distribution metadata.
3. Finish macOS Network Extension integration for true packet tunnel mode.
4. Expand per-app routing validation across Android and macOS.
5. Add automated release builds for APK and DMG artifacts.
