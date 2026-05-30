import {Platform} from 'react-native';
import {V2DexBridge, V2DexNativeModule} from './V2DexBridge';

export function getDesktopBridge(): V2DexNativeModule | undefined {
  if (Platform.OS === 'macos' || Platform.OS === 'windows' || Platform.OS === 'android') {
    return V2DexBridge;
  }

  return undefined;
}

export function getDesktopBridgeIssue(): string | undefined {
  if (Platform.OS !== 'macos' && Platform.OS !== 'windows' && Platform.OS !== 'android') {
    return `Unsupported platform: ${Platform.OS}`;
  }

  if (!V2DexBridge) {
    return `Native module V2DexBridge is not linked for platform ${Platform.OS}`;
  }

  return undefined;
}

export function desktopCapabilitySummary() {
  return {
    platform: Platform.OS,
    hasNativeBridge: Boolean(getDesktopBridge()),
    supportsSystemTunnel: Platform.OS === 'android',
    supportsPerAppRouting: Platform.OS === 'macos' || Platform.OS === 'android',
    supportsSystemProxy: Platform.OS === 'macos'
  };
}
