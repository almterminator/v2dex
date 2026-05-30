# Bootstrap Guide

## 1. Create the host app

From this directory:

```bash
npx react-native init V2DexHost --template react-native-template-typescript
```

Then add React Native macOS support:

```bash
npx react-native-macos-init
```

Move or merge the generated host project files around this scaffold rather than replacing `src/` and `native/`.

## 2. Install JS dependencies

```bash
npm install
```

If `react-native-linear-gradient` macOS support is not acceptable for your final host setup, replace it with an `react-native-svg`-based gradient layer before production work.

## 3. Wire the Swift package

- Open the generated Xcode workspace
- Add local package:
  - `/Users/alirezamotamed/Desktop/v2dex/native/V2DexCore`
- Link it to the macOS host target
- Run:

```bash
zsh scripts/postbootstrap_macos.sh
```

after the `macos/` host app exists to copy the bridge and template files into the generated host tree.

## 4. Add the Network Extension target

- Create a new `Packet Tunnel Extension`
- Replace the generated provider with:
  - `/Users/alirezamotamed/Desktop/v2dex/native/V2DexNetworkExtension/PacketTunnelProvider.swift`
- Set the correct extension bundle identifier in `TunnelController.swift`

## 5. Build the native bridge

Expose a React Native native module named `V2DexBridge` that forwards:

- clipboard import
- URI import
- installed app discovery
- tunnel start
- tunnel stop
- tunnel status

## 6. Bundle `sing-box`

Choose one of:

- app resource bundle plus copied executable permission fix
- helper tool inside app group container
- managed external binary path for personal use

The placeholder provider currently uses `/usr/local/bin/sing-box`; that is only a development stub.

To bundle a binary into a prototype `.app`, use:

```bash
zsh scripts/copy_singbox_into_app.sh /path/to/sing-box /path/to/V2Dex.app
```
