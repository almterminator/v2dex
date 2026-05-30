export type TunnelMode = 'full' | 'per-app';

export type ProxyProtocol =
  | 'vless'
  | 'vmess'
  | 'trojan'
  | 'socks5'
  | 'http'
  | 'https'
  | 'hysteria2'
  | 'tuic';

export interface ProxyNode {
  id: string;
  name: string;
  protocol: ProxyProtocol;
  server: string;
  port: number;
  username?: string;
  security?: 'reality' | 'tls' | 'none';
  transport?: 'tcp' | 'ws' | 'grpc' | 'httpupgrade';
  flow?: 'vision';
  sni?: string;
  path?: string;
  uuid?: string;
  password?: string;
  wsHost?: string;
  udpOverTCP?: boolean;
  allowInsecure?: boolean;
  publicKey?: string;
  shortId?: string;
  fingerprint?: string;
  alpn?: string[];
  alterId?: number;
  vmessCipher?: string;
  latencyMs?: number;
  rawUri?: string;
}

export interface SubscriptionProfile {
  id: string;
  title: string;
  source: 'clipboard' | 'uri' | 'subscription' | 'manual';
  sourceValue: string;
  updatedAt: string;
  trafficUsedGB?: number;
  trafficTotalGB?: number;
  usage?: {
    uploadBytes?: number;
    downloadBytes?: number;
    totalBytes?: number;
    usedBytes?: number;
    remainingBytes?: number;
    expiresAt?: string;
  };
  nodes: ProxyNode[];
}

export interface AppRouteRule {
  bundleId: string;
  name: string;
  icon?: string;
  enabled: boolean;
  processName: string;
}

export interface TunnelStatus {
  connected: boolean;
  connecting: boolean;
  activeProfileId?: string;
  activeNodeId?: string;
  mode: TunnelMode;
  backend?: 'system-proxy' | 'app-proxy' | 'vpn';
  lastConnectedAt?: string;
  lastError?: string;
  dnsLeakProtection: boolean;
  binaryPath?: string;
  activeConfigPath?: string;
  proxyHost?: string;
  proxyPort?: number;
  pingMs?: number;
  pingTimedOut?: boolean;
  exitIp?: string;
  exitCountry?: string;
  exitCountryCode?: string;
}
