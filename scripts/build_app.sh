#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${V2DEX_BUILD_DIR:-$ROOT_DIR/.build-artifacts}"
DEFAULT_DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-derived"
ALT_DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-derived-run"
DERIVED_DATA_DIR="${V2DEX_DERIVED_DATA_DIR:-$DEFAULT_DERIVED_DATA_DIR}"
APP_SOURCE="$DERIVED_DATA_DIR/Build/Products/Release/v2dex.app"
APP_DEST="$BUILD_DIR/V2Dex.app"
RELEASE_PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/Release"
SINGBOX_BIN="${V2DEX_SINGBOX_PATH:-$ROOT_DIR/.local/bin/sing-box}"
LOGO_PNG="${V2DEX_LOGO_PNG:-/Users/alirezamotamed/Desktop/v2dexlogo.png}"
ICONSET_DIR="$BUILD_DIR/app-icon.iconset"
APP_ICON_ICNS="$BUILD_DIR/AppIcon.icns"
SWIFT_CONCURRENCY_DYLIB="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/macosx/libswift_Concurrency.dylib"

mkdir -p "$BUILD_DIR"
if [[ -z "${V2DEX_DERIVED_DATA_DIR:-}" && -x "$ALT_DERIVED_DATA_DIR/Build/Products/Release/v2dex.app/Contents/MacOS/v2dex" ]]; then
  DERIVED_DATA_DIR="$ALT_DERIVED_DATA_DIR"
  APP_SOURCE="$DERIVED_DATA_DIR/Build/Products/Release/v2dex.app"
  RELEASE_PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/Release"
fi

rm -rf "$APP_DEST" "$DERIVED_DATA_DIR" "$ICONSET_DIR"
rm -f "$APP_ICON_ICNS"

cd "$ROOT_DIR"

if [[ -f "$LOGO_PNG" ]]; then
  zsh "$ROOT_DIR/scripts/generate_app_icon.sh" "$LOGO_PNG"
else
  echo "Warning: logo PNG was not found at $LOGO_PNG"
fi

xcodebuild \
  -workspace "$ROOT_DIR/macos/v2dex.xcworkspace" \
  -scheme "v2dex-macOS" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Expected app bundle was not produced: $APP_SOURCE"
  exit 1
fi

cp -R "$APP_SOURCE" "$APP_DEST"

if [[ -f "$RELEASE_PRODUCTS_DIR/main.jsbundle" && ! -f "$APP_DEST/Contents/Resources/main.jsbundle" ]]; then
  cp "$RELEASE_PRODUCTS_DIR/main.jsbundle" "$APP_DEST/Contents/Resources/main.jsbundle"
fi

if [[ -f "$SWIFT_CONCURRENCY_DYLIB" && ! -f "$APP_DEST/Contents/Frameworks/libswift_Concurrency.dylib" ]]; then
  mkdir -p "$APP_DEST/Contents/Frameworks"
  cp "$SWIFT_CONCURRENCY_DYLIB" "$APP_DEST/Contents/Frameworks/"
fi

if [[ -f "$LOGO_PNG" ]]; then
  mkdir -p "$ICONSET_DIR"
  for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
  do
    size="${spec%% *}"
    filename="${spec#* }"
    sips -z "$size" "$size" "$LOGO_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
  done

  iconutil --convert icns "$ICONSET_DIR" --output "$APP_ICON_ICNS"
  cp "$APP_ICON_ICNS" "$APP_DEST/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$APP_DEST/Contents/Info.plist"
fi

if [[ -x "$SINGBOX_BIN" ]]; then
  zsh "$ROOT_DIR/scripts/copy_singbox_into_app.sh" "$SINGBOX_BIN" "$APP_DEST"
else
  echo "Warning: sing-box binary was not bundled."
  echo "Set V2DEX_SINGBOX_PATH or place sing-box at $ROOT_DIR/.local/bin/sing-box before packaging."
fi

codesign --force --sign - --deep "$APP_DEST"

echo "Built self-contained app bundle at: $APP_DEST"
