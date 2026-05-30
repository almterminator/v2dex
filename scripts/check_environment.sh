#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

function check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[ok] $name: $(command -v "$name")"
  else
    echo "[missing] $name"
  fi
}

echo "V2Dex environment check"
echo "repo: $ROOT_DIR"
echo

check_cmd node
check_cmd npm
check_cmd swift
check_cmd xcodebuild
check_cmd xcrun
check_cmd hdiutil
check_cmd sing-box
if [[ -x "$ROOT_DIR/.local/bin/sing-box" ]]; then
  echo "[ok] local sing-box: $ROOT_DIR/.local/bin/sing-box"
fi

echo
echo "xcode-select:"
xcode-select -p 2>/dev/null || echo "not configured"

echo
echo "swift:"
swift --version 2>/dev/null || true

echo
echo "xcodebuild:"
xcodebuild -version 2>/dev/null || echo "full Xcode is not active"

echo
echo "npm registry probe:"
curl -I https://registry.npmjs.org/react-native --max-time 10 2>/dev/null | head -n 1 || echo "registry probe failed"

echo
echo "artifacts:"
ls -la "$ROOT_DIR/.build-artifacts" 2>/dev/null || echo "no build artifacts yet"
