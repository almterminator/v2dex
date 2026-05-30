# Windows Native Backend Plan

This folder is the placeholder for the React Native Windows host app and native backend.

## Intended components

- `V2DexWindowsBridge`
  - React Native Windows native module
  - import, app discovery, tunnel start/stop, status reporting
- `V2DexTunnelService`
  - service or elevated helper process
  - owns `sing-box` lifecycle
  - owns tunnel adapter lifecycle
- `V2DexCore.Win`
  - config generation and Windows-specific runtime helpers

## Recommended stack

- React Native Windows
- C# or C++/WinRT native module
- `sing-box` Windows binary
- Wintun driver
- optional Windows service for resilience and privilege separation

## Minimum milestone

1. parse URI and build config
2. launch `sing-box` in user mode
3. expose tunnel state to RN
4. add Wintun-backed full tunnel
5. add per-app routing policy
