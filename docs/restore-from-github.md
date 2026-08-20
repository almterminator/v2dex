# Restore From GitHub

This repository is the source of truth for continuing V2Dex development after
removing the local working copy from the Mac.

## Clone

```bash
cd ~/Desktop
git clone https://github.com/almterminator/v2dex.git
cd v2dex
```

## Recreate JavaScript Dependencies

`node_modules/` is intentionally not committed. Reinstall it after cloning:

```bash
npm install
```

## Validate The Native macOS Swift App

The Swift package build verifies the native macOS prototype sources:

```bash
swift build
```

## Validate The React Native Frontend

After installing Node dependencies:

```bash
npm run typecheck
```

## Android Monitor APK Build

The Android monitor build needs the Android SDK, NDK, and JDK. Native ARMv7
assets and the JNI wrapper source are committed. Rebuild the wrapper first when
changing `android/app/src/main/cpp/hev_jni_wrapper.c`:

```bash
android/build-hev-jni-wrapper.sh
cd android
ANDROID_HOME="$HOME/Library/Android/sdk" \
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" \
./gradlew --init-script gradle-repositories.init.gradle :app:assembleRelease \
  -PreactNativeArchitectures=armeabi-v7a \
  -PhermesEnabled=true
```

## Local-Only Files

These directories and build outputs are intentionally excluded and can be
deleted/recreated:

- `node_modules/`
- `.build/`
- `android/.gradle/`
- `android/build/`
- `android/app/build/`
- `macos/Pods/`
- `macos/DerivedData/`

Do not delete system-installed apps or release APK/DMG files unless a separate
backup exists.
