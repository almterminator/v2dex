import {ProxyNode, SubscriptionProfile} from '../types/proxy';

export function buildNodeFromUri(uri: string): ProxyNode {
  if (uri.startsWith('vless://')) {
    return parseVlessUri(uri);
  }
  if (uri.startsWith('hysteria2://')) {
    return parseHysteria2Uri(uri);
  }
  if (uri.startsWith('tuic://')) {
    return parseTuicUri(uri);
  }

  throw new Error('Unsupported config format.');
}

function parseVlessUri(uri: string): ProxyNode {
  const compactId = Array.from(uri)
    .reduce((acc, char) => (acc * 31 + char.charCodeAt(0)) >>> 0, 7)
    .toString(16);

  const parsed = new URL(uri);
  const security = parsed.searchParams.get('security') || 'none';
  const type = parsed.searchParams.get('type') || 'tcp';
  const path = parsed.searchParams.get('path') || '/';
  const wsHost = parsed.searchParams.get('host') || undefined;
  const sni = parsed.searchParams.get('sni') || wsHost;
  const flow = parsed.searchParams.get('flow') || undefined;
  const allowInsecure = ['1', 'true'].includes(
    (parsed.searchParams.get('allowInsecure') || '').toLowerCase(),
  );
  const publicKey = parsed.searchParams.get('pbk') || parsed.searchParams.get('publicKey') || undefined;
  const shortId = parsed.searchParams.get('sid') || parsed.searchParams.get('shortId') || undefined;
  const fingerprint = parsed.searchParams.get('fp') || parsed.searchParams.get('fingerprint') || undefined;
  const alpn = parsed.searchParams.get('alpn')?.split(',').map(item => item.trim()).filter(Boolean);

  return {
    id: `node-${compactId}`,
    name: decodePercentEncodingRepeatedly(parsed.hash.replace(/^#/, '')) || `VLESS ${parsed.hostname}`,
    protocol: 'vless',
    server: parsed.hostname,
    port: Number(parsed.port || 443),
    security: security as ProxyNode['security'],
    transport: type as ProxyNode['transport'],
    path,
    sni,
    wsHost,
    flow: flow as ProxyNode['flow'],
    uuid: decodeURIComponent(parsed.username),
    allowInsecure,
    publicKey,
    shortId,
    fingerprint,
    alpn: alpn?.length ? alpn : undefined,
    rawUri: uri,
  };
}

function parseHysteria2Uri(uri: string): ProxyNode {
  const parsed = new URL(uri);
  const alpn = parsed.searchParams.get('alpn')?.split(',').map(item => item.trim()).filter(Boolean);
  return {
    id: `node-${hashString(uri)}`,
    name: decodePercentEncodingRepeatedly(parsed.hash.replace(/^#/, '')) || `Hysteria2 ${parsed.hostname}`,
    protocol: 'hysteria2',
    server: parsed.hostname,
    port: Number(parsed.port || 443),
    security: 'tls',
    password: decodeURIComponent(parsed.username),
    sni: parsed.searchParams.get('sni') || undefined,
    allowInsecure: ['1', 'true'].includes((parsed.searchParams.get('insecure') || '').toLowerCase()),
    alpn: alpn?.length ? alpn : undefined,
    rawUri: uri,
  };
}

function parseTuicUri(uri: string): ProxyNode {
  const parsed = new URL(uri);
  const alpn = parsed.searchParams.get('alpn')?.split(',').map(item => item.trim()).filter(Boolean);
  return {
    id: `node-${hashString(uri)}`,
    name: decodePercentEncodingRepeatedly(parsed.hash.replace(/^#/, '')) || `TUIC ${parsed.hostname}`,
    protocol: 'tuic',
    server: parsed.hostname,
    port: Number(parsed.port || 443),
    security: 'tls',
    uuid: decodeURIComponent(parsed.username),
    password: decodeURIComponent(parsed.password),
    sni: parsed.searchParams.get('sni') || undefined,
    allowInsecure: ['1', 'true'].includes((parsed.searchParams.get('allowInsecure') || '').toLowerCase()),
    alpn: alpn?.length ? alpn : undefined,
    rawUri: uri,
  };
}

function hashString(value: string) {
  return Array.from(value)
    .reduce((acc, char) => (acc * 31 + char.charCodeAt(0)) >>> 0, 7)
    .toString(16);
}

function decodePercentEncodingRepeatedly(value: string) {
  let decoded = value;

  for (let index = 0; index < 5; index += 1) {
    try {
      const next = decodeURIComponent(decoded);
      if (next === decoded) {
        return decoded;
      }
      decoded = next;
    } catch {
      return decoded;
    }
  }

  return decoded;
}

export function importProfileFromRaw(sourceValue: string): SubscriptionProfile {
  const entries = extractNodeUris(sourceValue);

  const nodes = entries.length > 0 ? entries.map(buildNodeFromUri) : [buildNodeFromUri(sourceValue)];

  return {
    id: `profile-${Date.now()}`,
    title: nodes[0]?.name ?? 'Imported Profile',
    source: 'clipboard',
    sourceValue,
    updatedAt: new Date().toISOString(),
    nodes
  };
}

export function extractNodeUris(sourceValue: string) {
  return sourceValue
    .split(/[\r\n\s]+/)
    .map(line => line.trim())
    .filter(Boolean)
    .filter(line => /^(vless|hysteria2|tuic):\/\//i.test(line));
}

export function buildManualProfile(input: {
  protocol: 'http' | 'https' | 'socks5';
  host: string;
  port: number;
  username?: string;
  password?: string;
  name?: string;
}): SubscriptionProfile {
  const node: ProxyNode = {
    id: `node-${hashString(`${input.protocol}:${input.host}:${input.port}:${input.username ?? ''}`)}`,
    name:
      input.name?.trim() ||
      `${input.protocol.toUpperCase()} ${input.host}:${input.port}`,
    protocol: input.protocol,
    server: input.host.trim(),
    port: input.port,
    username: input.username?.trim() || undefined,
    password: input.password?.trim() || undefined,
    security: input.protocol === 'https' ? 'tls' : 'none',
  };

  return {
    id: `profile-${Date.now()}`,
    title: node.name,
    source: 'manual',
    sourceValue: `${input.protocol}://${input.host}:${input.port}`,
    updatedAt: new Date().toISOString(),
    nodes: [node],
  };
}
