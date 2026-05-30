#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${V2DEX_BUILD_DIR:-$ROOT_DIR/.build-artifacts}"
APP_DIR="$BUILD_DIR/V2Dex.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/V2Dex.dmg"
RW_DMG_PATH="$BUILD_DIR/V2Dex-rw.dmg"
LOGO_PNG="${V2DEX_LOGO_PNG:-/Users/alirezamotamed/Desktop/v2dexlogo.png}"
ICONSET_DIR="$BUILD_DIR/dmg-icon.iconset"
VOLUME_ICON_PATH="$BUILD_DIR/V2DexVolumeIcon.icns"

zsh "$ROOT_DIR/scripts/build_app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
rm -f "$RW_DMG_PATH" "$VOLUME_ICON_PATH"
rm -rf "$ICONSET_DIR"

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
  iconutil --convert icns "$ICONSET_DIR" --output "$VOLUME_ICON_PATH"
fi

hdiutil create \
  -volname "V2Dex" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

if [[ -f "$VOLUME_ICON_PATH" ]]; then
  MOUNT_POINT="$(mktemp -d /tmp/v2dex-dmg.XXXXXX)"
  DEVICE="$(hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readwrite | awk '/Apple_HFS/ { print $1; exit }')"
  cp "$VOLUME_ICON_PATH" "$MOUNT_POINT/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_POINT"
  SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"
  sync
  hdiutil detach "$DEVICE"
  rmdir "$MOUNT_POINT"
fi

hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

echo "Built dmg at: $DMG_PATH"
