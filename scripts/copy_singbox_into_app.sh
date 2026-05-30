#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <path-to-sing-box-binary> <path-to-app-bundle>"
  exit 1
fi

SINGBOX_BIN="$1"
APP_BUNDLE="$2"
TARGET_DIR="$APP_BUNDLE/Contents/Resources"
TARGET_BIN="$TARGET_DIR/sing-box"

if [[ ! -f "$SINGBOX_BIN" ]]; then
  echo "sing-box binary not found: $SINGBOX_BIN"
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE"
  exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$SINGBOX_BIN" "$TARGET_BIN"
chmod +x "$TARGET_BIN"

echo "Copied sing-box to: $TARGET_BIN"
