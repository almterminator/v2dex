import {buildSingboxConfig} from './singboxBuilder';
import {Platform} from 'react-native';
import {buildXrayConfig} from './xrayBuilder';
import {buildNodeFromUri, extractNodeUris} from './configParser';
import {getDesktopBridge, getDesktopBridgeIssue} from '../native/V2DexDesktopBridge';
import {ImportedProfilePayload} from '../native/V2DexBridge';
import {AppRouteRule, ProxyNode, TunnelMode} from '../types/proxy';

export async function importNodesFromUri(uri: string): Promise<ProxyNode[]> {
  const payload = await importProfileFromUri(uri);
  return payload.nodes;
}

export async function importProfileFromUri(uri: string): Promise<{
  nodes: ProxyNode[];
  usage?: ImportedProfilePayload['usage'];
}> {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return importSubscriptionWithFetch(uri);
  }

  try {
    const raw = await bridge.importFromUri(uri);
    const payload = JSON.parse(raw) as ImportedProfilePayload;
    const nodes = payload.nodes as ProxyNode[];
    if (nodes.length > 0) {
      return {
        nodes,
        usage: payload.usage,
      };
    }
  } catch (error) {
    if (!isHttpUrl(uri)) {
      throw error;
    }
  }

  return importSubscriptionWithFetch(uri);
}

export async function discoverInstalledApps(): Promise<AppRouteRule[]> {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return [];
  }

  return bridge.discoverInstalledApplications();
}

export async function loadPersistedAppState(): Promise<string> {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return '';
  }

  return bridge.loadAppState();
}

export async function savePersistedAppState(stateJson: string) {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return;
  }

  await bridge.saveAppState(stateJson);
}

export async function importClipboardText() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return '';
  }

  return bridge.importFromClipboard();
}

export async function copyTextToClipboard(value: string) {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  await bridge.copyToClipboard(value);
}

export async function scanQrFromCamera() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  return bridge.scanQrFromCamera();
}

export async function scanQrFromGallery() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  return bridge.scanQrFromGallery();
}

export async function testProfileDownload(sourceValue: string) {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  return bridge.testProfileDownload(sourceValue);
}

export async function testServerConnection(node: ProxyNode) {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  if (Platform.OS === 'android') {
    const probePort = 44000 + Math.floor(Math.random() * 1000);
    return bridge.testServerConnection(JSON.stringify({
      node,
      probePort,
      probeConfigJson: JSON.stringify(buildXrayConfig({node, localSocksPort: probePort}), null, 2),
    }));
  }

  if (Platform.OS === 'windows') {
    const probePort = 45000 + Math.floor(Math.random() * 1000);
    return bridge.testServerConnection(JSON.stringify({
      node,
      probePort,
      probeConfigJson: JSON.stringify(buildSingboxConfig({
        node,
        mode: 'full',
        appRules: [],
        localProxyPort: probePort,
      }), null, 2),
    }));
  }

  return bridge.testServerConnection(JSON.stringify(node));
}

export async function testTunnelHttpLatency() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  const probeUrls = [
    'https://www.youtube.com/generate_204',
    'https://www.google.com/generate_204',
  ];
  let lastError: unknown;

  for (const url of probeUrls) {
    try {
      return await bridge.testTunnelHttpLatency(url);
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError instanceof Error ? lastError : new Error('Tunnel ping timed out.');
}

export async function getTunnelIpInfo() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  return bridge.getTunnelIpInfo();
}

export async function startNativeTunnel(input: {
  node: ProxyNode;
  mode: TunnelMode;
  appRules: AppRouteRule[];
}) {
  const bridge = getDesktopBridge();
  if (!bridge) {
    throw new Error(getDesktopBridgeIssue() ?? 'Native bridge is unavailable on this platform.');
  }

  const config = Platform.OS === 'android' ? buildXrayConfig(input) : buildSingboxConfig(input);
  return bridge.startTunnel(JSON.stringify(config, null, 2), input.mode, JSON.stringify(input.appRules));
}

export async function getNativeTunnelStatus() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return undefined;
  }

  return bridge.getTunnelStatus();
}

export async function stopNativeTunnel() {
  const bridge = getDesktopBridge();
  if (!bridge) {
    return;
  }

  await bridge.stopTunnel();
}

async function importSubscriptionWithFetch(uri: string): Promise<{
  nodes: ProxyNode[];
  usage?: ImportedProfilePayload['usage'];
}> {
  if (!isHttpUrl(uri)) {
    return {nodes: []};
  }

  const response = await fetch(uri, {
    headers: {
      Accept: 'text/plain, application/octet-stream, */*',
      'User-Agent': 'V2Dex/1.0',
    },
  });

  if (!response.ok) {
    throw new Error(`Subscription download failed with status ${response.status}.`);
  }

  const raw = await response.text();
  const decoded = decodeSubscriptionBody(raw);
  const decodedEntries = extractNodeUris(decoded);
  const entries = decodedEntries.length > 0 ? decodedEntries : extractNodeUris(raw);

  if (entries.length === 0) {
    throw new Error('No supported configs were found in this subscription.');
  }

  const nodes = entries.map(buildNodeFromUri);
  const usageFromHeaders = parseSubscriptionUserInfo(response.headers.get('subscription-userinfo'));
  const remainingBytes = usageFromHeaders?.remainingBytes
    ?? entries.map(parseRemainingBytesFromUri).find((value): value is number => typeof value === 'number');

  return {
    nodes,
    usage: usageFromHeaders ?? (typeof remainingBytes === 'number' ? {remainingBytes} : undefined),
  };
}

function isHttpUrl(value: string) {
  return /^https?:\/\//i.test(value.trim());
}

function parseSubscriptionUserInfo(value: string | null): ImportedProfilePayload['usage'] | undefined {
  if (!value) {
    return undefined;
  }

  const pairs = value.split(';').map(part => part.trim().split('=', 2));
  const values = new Map(
    pairs
      .map(([key, raw]) => [key?.toLowerCase(), Number(raw)] as const)
      .filter(([key, amount]) => Boolean(key) && Number.isFinite(amount)),
  );
  const uploadBytes = values.get('upload') ?? 0;
  const downloadBytes = values.get('download') ?? 0;
  const usedBytes = uploadBytes + downloadBytes;
  const totalBytes = values.get('total');
  const expire = values.get('expire');

  return {
    uploadBytes,
    downloadBytes,
    usedBytes,
    totalBytes,
    remainingBytes: typeof totalBytes === 'number' ? Math.max(totalBytes - usedBytes, 0) : undefined,
    expiresAt: typeof expire === 'number' ? new Date(expire * 1000).toISOString() : undefined,
  };
}

function decodeSubscriptionBody(value: string) {
  const compact = value.trim().replace(/\s+/g, '');
  if (!compact || /:\/\//.test(value)) {
    return value;
  }

  try {
    const normalized = compact.replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
    const binary = decodeBase64ToBinary(padded);
    return decodeUtf8Binary(binary);
  } catch {
    return value;
  }
}

function decodeBase64ToBinary(value: string) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let output = '';
  let buffer = 0;
  let bits = 0;

  for (const char of value) {
    if (char === '=') {
      break;
    }

    const next = alphabet.indexOf(char);
    if (next < 0) {
      throw new Error('Invalid base64 character.');
    }

    buffer = (buffer << 6) | next;
    bits += 6;

    if (bits >= 8) {
      bits -= 8;
      output += String.fromCharCode((buffer >> bits) & 0xff);
    }
  }

  return output;
}

function decodeUtf8Binary(binary: string) {
  const bytes = Array.from(binary, char => char.charCodeAt(0));
  let output = '';

  for (let index = 0; index < bytes.length; index += 1) {
    const byte = bytes[index];
    if (byte < 0x80) {
      output += String.fromCharCode(byte);
    } else if (byte >= 0xc0 && byte < 0xe0) {
      output += String.fromCharCode(((byte & 0x1f) << 6) | (bytes[++index] & 0x3f));
    } else if (byte >= 0xe0 && byte < 0xf0) {
      output += String.fromCharCode(
        ((byte & 0x0f) << 12) | ((bytes[++index] & 0x3f) << 6) | (bytes[++index] & 0x3f),
      );
    } else {
      const codePoint =
        ((byte & 0x07) << 18) |
        ((bytes[++index] & 0x3f) << 12) |
        ((bytes[++index] & 0x3f) << 6) |
        (bytes[++index] & 0x3f);
      output += String.fromCodePoint(codePoint);
    }
  }

  return output;
}

function parseRemainingBytesFromUri(uri: string) {
  try {
    const name = decodePercentEncodingRepeatedly(new URL(uri).hash.replace(/^#/, ''));
    const match = name.match(/(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB|B)/i);
    if (!match) {
      return undefined;
    }

    const amount = Number(match[1]);
    const unit = match[2].toUpperCase();
    const multiplier =
      unit === 'TB'
        ? 1024 ** 4
        : unit === 'GB'
          ? 1024 ** 3
          : unit === 'MB'
            ? 1024 ** 2
            : unit === 'KB'
              ? 1024
              : 1;

    return Math.round(amount * multiplier);
  } catch {
    return undefined;
  }
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
