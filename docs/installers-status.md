# Installer Status

## Current state as of 2026-05-21

### macOS

- prototype `.app`: available
- prototype `.dmg`: available
- signed production installer: not ready

Blockers:

- full Xcode host app bootstrap not completed in this environment
- Network Extension entitlement/signing not completed
- bundled `sing-box` strategy not finalized
- installer signing/notarization not completed

### Windows

- native backend scaffold: present
- React Native Windows host app: not generated here
- installer: not ready

Blockers:

- Windows build machine required
- RN Windows host app generation required
- Wintun/service backend required
- `sing-box.exe` bundling required
- signing/MSIX packaging required

## Definition of done before saying installers are ready

1. Host apps build on target platforms
2. Native bridges are wired and callable from JS
3. `sing-box` launches from the packaged app
4. Full tunnel works end-to-end
5. Per-app routing works end-to-end
6. Installers are signed and launch on clean machines
