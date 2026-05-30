# macOS React Native Bridge Wiring

Add these files to the `react-native-macos` host app target:

- `native/V2DexMacBridge/V2DexBridge.swift`
- `native/V2DexMacBridge/V2DexBridge.m`

## Required target wiring

- link `React`
- link local Swift package `native/V2DexCore`
- ensure the target contains a Swift file so the generated Swift header is emitted
- if the host app has no bridging setup yet, let Xcode create the Swift bridging metadata when adding the first Swift file

## Expected JS module name

`NativeModules.V2DexBridge`

## Exposed methods

- `importFromClipboard()`
- `importFromUri(uri)`
- `discoverInstalledApplications()`
- `startTunnel(configJson, mode)`
- `stopTunnel()`
- `getTunnelStatus()`
