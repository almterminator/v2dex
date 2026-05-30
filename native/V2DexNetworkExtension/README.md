# Packet Tunnel Extension Notes

Use [PacketTunnelProvider.swift](/Users/alirezamotamed/Desktop/v2dex/native/V2DexNetworkExtension/PacketTunnelProvider.swift) as the provider implementation for the macOS `Packet Tunnel Extension` target.

## Required host integration

- host app and extension must share the same App Group
- host app must set the correct `providerBundleIdentifier`
- `sing-box` binary must be bundled inside the app or copied into a reachable shared location
- final production signing must use the correct Network Extension entitlements

## Current implementation

- reads `singboxConfig` from `NETunnelProviderProtocol.providerConfiguration`
- optionally reads `singboxBinaryPath`
- configures a basic TUN interface
- launches `sing-box` as a subprocess

## Still required for production

- app-group based config handoff
- health/restart policy
- structured logging
- secure secret handling
- final DNS/routing validation on real systems
