#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NDK_DIR="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk/27.1.12297006}}"
TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/darwin-x86_64"
SRC="$ROOT_DIR/android/app/src/main/cpp/hev_jni_wrapper.c"
OUT_DIR="$ROOT_DIR/android/app/src/main/jniLibs"

build_one() {
  local abi="$1"
  local clang="$2"
  local abi_dir="$OUT_DIR/$abi"
  local core="$abi_dir/libhev-socks5-tunnel-core.so"
  local wrapper="$abi_dir/libhev-socks5-tunnel.so"

  if [[ ! -f "$core" && -f "$wrapper" ]]; then
    mv "$wrapper" "$core"
  fi

  "$TOOLCHAIN/bin/$clang" \
    -shared \
    -fPIC \
    -O2 \
    -Wall \
    -Wextra \
    -Wl,-soname,libhev-socks5-tunnel.so \
    -Wl,--no-undefined \
    -o "$wrapper" \
    "$SRC" \
    -llog
}

build_one "armeabi-v7a" "armv7a-linux-androideabi23-clang"
build_one "arm64-v8a" "aarch64-linux-android23-clang"
