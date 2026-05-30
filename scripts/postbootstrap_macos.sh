#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_DIR="${1:-$ROOT_DIR/macos}"
BRIDGE_DIR="$ROOT_DIR/native/V2DexMacBridge"
ENTITLEMENTS_DIR="$ROOT_DIR/templates/macos"

if [[ ! -d "$MACOS_DIR" ]]; then
  echo "macOS host directory not found: $MACOS_DIR"
  echo "Run this after the react-native-macos host project has been generated."
  exit 1
fi

mkdir -p "$MACOS_DIR/V2DexBridge"
cp "$BRIDGE_DIR/V2DexBridge.swift" "$MACOS_DIR/V2DexBridge/"
cp "$BRIDGE_DIR/V2DexBridge.m" "$MACOS_DIR/V2DexBridge/"

mkdir -p "$MACOS_DIR/Templates"
cp "$ENTITLEMENTS_DIR/"*.entitlements "$MACOS_DIR/Templates/" 2>/dev/null || true
cp "$ENTITLEMENTS_DIR/NetworkExtension-Info.template.plist" "$MACOS_DIR/Templates/" 2>/dev/null || true

cat <<EOF
Copied React Native macOS bridge sources into:
  $MACOS_DIR/V2DexBridge

Copied entitlement templates into:
  $MACOS_DIR/Templates

Next manual Xcode steps:
1. Add the local Swift package: native/V2DexCore
2. Add V2DexBridge.swift and V2DexBridge.m to the app target
3. Create a Packet Tunnel Extension target
4. Replace its provider file with native/V2DexNetworkExtension/PacketTunnelProvider.swift
5. Apply the entitlement templates and update bundle identifiers/app group values
EOF
