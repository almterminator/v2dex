import {NativeModules} from 'react-native';
import {AppRouteRule, TunnelMode} from '../types/proxy';

interface ImportedProfilePayload {
  nodes: unknown[];
  usage?: {
    uploadBytes?: number;
    downloadBytes?: number;
    totalBytes?: number;
    usedBytes?: number;
    remainingBytes?: number;
    expiresAt?: string;
  };
}

export interface V2DexNativeModule {
  importFromClipboard(): Promise<string>;
  copyToClipboard(value: string): Promise<void>;
  scanQrFromCamera(): Promise<string>;
  scanQrFromGallery(): Promise<string>;
  importFromUri(uri: string): Promise<string>;
  discoverInstalledApplications(): Promise<AppRouteRule[]>;
  loadAppState(): Promise<string>;
  saveAppState(stateJson: string): Promise<void>;
  testProfileDownload(sourceValue: string): Promise<string>;
  testServerConnection(nodeJson: string): Promise<{message: string; latencyMs?: number}>;
  testTunnelHttpLatency(url: string): Promise<{message: string; latencyMs?: number; url?: string}>;
  getTunnelIpInfo(): Promise<{ip?: string; country?: string; countryCode?: string}>;
  startTunnel(
    configJson: string,
    mode: TunnelMode,
    appRulesJson: string,
  ): Promise<{
    connected: boolean;
    connecting: boolean;
    mode: TunnelMode;
    backend?: 'system-proxy' | 'app-proxy' | 'vpn';
    lastError?: string;
    lastConnectedAt?: string;
    binaryPath?: string;
    activeConfigPath?: string;
    proxyHost?: string;
    proxyPort?: number;
  }>;
  stopTunnel(): Promise<void>;
  getTunnelStatus(): Promise<{
    connected: boolean;
    connecting: boolean;
    mode: TunnelMode;
    backend?: 'system-proxy' | 'app-proxy' | 'vpn';
    lastError?: string;
    lastConnectedAt?: string;
    binaryPath?: string;
    activeConfigPath?: string;
    proxyHost?: string;
    proxyPort?: number;
  }>;
}

export const V2DexBridge = NativeModules.V2DexBridge as V2DexNativeModule | undefined;

export type {ImportedProfilePayload};
