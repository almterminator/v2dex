# V2Dex

High-performance desktop proxy client scaffold built around a shared React Native frontend, `sing-box`, and native platform backends.

## Scope of this scaffold

This repository provides:

- Shared React Native desktop UI in `src/`
- macOS-oriented native tunnel scaffolding in Swift
- premium desktop-oriented glassmorphism shell
- profile import, node selection, per-app routing selection, and config preview
- `sing-box` config generation layer
- macOS `.app` and `.dmg` packaging scripts for the current native prototype

This is still a starter foundation, not a production-ready signed VPN app. The shared frontend is in place, and the current macOS path runs `sing-box` as a local user-space proxy that toggles the macOS system proxy. Signed Network Extension wiring and the Windows native backend still need to be completed.

## Architecture

- `src/`
  - shared React Native desktop UI
  - app state, models, services, and screen composition
- `native/V2DexCore/`
  - Swift package for parsing/import/config generation and tunnel orchestration
- `native/V2DexNetworkExtension/`
- `PacketTunnelProvider` skeleton for a future TUN mode build
- `Sources/V2DexApp/`
  - native macOS prototype app kept for local packaging and exploration
- `docs/`
  - implementation notes and next steps

## Key design decisions

- local-only macOS operation uses a user-space proxy plus macOS system proxy toggling
- Routing rules are modeled around full tunnel and per-application process rules
- UI state is isolated from tunnel/session state so reconnect logic can be native-driven
- `sing-box` JSON generation is centralized to reduce config drift across the JS and Swift layers

## Frontend direction

The preferred product direction is now:

- React Native frontend shared between macOS and Windows
- native tunnel backend per platform
- `sing-box` as the common networking core

See [desktop-bootstrap.md](/Users/alirezamotamed/Desktop/v2dex/docs/desktop-bootstrap.md) for the desktop bootstrap flow.
See [installers-status.md](/Users/alirezamotamed/Desktop/v2dex/docs/installers-status.md) for the exact current installer state.

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

Current artifacts are written to:

- `.build-artifacts/V2Dex.app`
- `.build-artifacts/V2Dex.dmg`

The Release app embeds the React Native bundle. If `V2DEX_SINGBOX_PATH` is set, or `.local/bin/sing-box` exists, the packaging script also copies `sing-box` into the app bundle so end users do not need a terminal or Metro.

These are still unsigned prototype artifacts, not final notarized installers.

## Next steps

1. Bootstrap the actual React Native macOS and Windows host projects.
2. Keep `src/` as the single shared desktop frontend.
3. Replace the demo launcher path with bundled `sing-box` binaries per platform.
4. Complete macOS signing and `Network Extension` wiring for true VPN/TUN mode.
5. Implement the Windows native tunnel backend and installer path.
6. Only after end-to-end tunnel validation, produce signed macOS and Windows installers.
