import {AppRouteRule, SubscriptionProfile, TunnelStatus} from '../types/proxy';

export const mockProfiles: SubscriptionProfile[] = [
  {
    id: 'profile-primary',
    title: 'Primary Reality Cluster',
    source: 'subscription',
    sourceValue: 'https://example.invalid/subscription',
    updatedAt: '2026-05-21T12:00:00Z',
    trafficUsedGB: 128,
    trafficTotalGB: 300,
    nodes: [
      {
        id: 'node-1',
        name: 'Tokyo Low-Latency',
        protocol: 'vless',
        server: 'tokyo-01.example.invalid',
        port: 443,
        security: 'reality',
        transport: 'grpc',
        flow: 'vision',
        latencyMs: 48
      },
      {
        id: 'node-2',
        name: 'Frankfurt Fallback',
        protocol: 'hysteria2',
        server: 'fra-02.example.invalid',
        port: 8443,
        security: 'tls',
        latencyMs: 96
      }
    ]
  }
];

export const mockAppRules: AppRouteRule[] = [
  {
    bundleId: 'com.google.Chrome',
    name: 'Google Chrome',
    enabled: true,
    processName: 'Google Chrome'
  },
  {
    bundleId: 'ru.keepcoder.Telegram',
    name: 'Telegram',
    enabled: true,
    processName: 'Telegram'
  },
  {
    bundleId: 'com.microsoft.VSCode',
    name: 'Visual Studio Code',
    enabled: false,
    processName: 'Code'
  },
  {
    bundleId: 'com.valvesoftware.steam',
    name: 'Steam',
    enabled: false,
    processName: 'steam_osx'
  }
];

export const mockTunnelStatus: TunnelStatus = {
  connected: false,
  connecting: false,
  mode: 'full',
  backend: 'system-proxy',
  dnsLeakProtection: true,
  proxyHost: '127.0.0.1',
  proxyPort: 2081
};
