# Native Integration Checklist

## Required Xcode work

- Create a React Native macOS host app target
- Add a Packet Tunnel Network Extension target
- Enable `Network Extensions` capability
- Enable App Groups for host app + extension
- Embed `V2DexCore` into the app target
- Bundle `sing-box` in app resources or helper container
- Apply the entitlement templates from `templates/macos/`

## Recommended bridge split

- React Native side only requests actions and receives normalized status events
- Swift side performs:
  - application discovery
  - config assembly
  - preference persistence
  - tunnel start/stop/reconnect
  - traffic and health reporting

## Important production gaps

- replace hard-coded `providerBundleIdentifier`
- replace hard-coded `sing-box` executable path
- pass file descriptor or app-group config path to extension
- implement structured stderr parsing and restart policy
- move credentials and secrets to Keychain
- replace temporary file handoff with app-group based config sharing
