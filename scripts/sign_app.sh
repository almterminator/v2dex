#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build-artifacts/V2Dex.app}"
IDENTITY="${V2DEX_CODESIGN_IDENTITY:-Developer ID Application}"
ENTITLEMENTS_PATH="$ROOT_DIR/macos/v2dex-macOS/v2dex.entitlements"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

codesign --force --deep --options runtime --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS_PATH" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

echo "Signed app bundle: $APP_PATH"
