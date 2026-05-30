#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="${1:-$ROOT_DIR/.build-artifacts/V2Dex.dmg}"
KEYCHAIN_PROFILE="${V2DEX_NOTARY_PROFILE:-}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH"
  exit 1
fi

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
  echo "Set V2DEX_NOTARY_PROFILE to an xcrun notarytool keychain profile."
  exit 1
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Notarized DMG: $DMG_PATH"
