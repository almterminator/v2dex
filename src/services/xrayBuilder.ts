import {ProxyNode} from '../types/proxy';

const LOCAL_SOCKS_PORT = 43080;

interface BuildOptions {
  node: ProxyNode;
}

export function buildXrayConfig({node}: BuildOptions) {
  return {
    log: {
      loglevel: 'warning',
    },
    inbounds: [
      {
        tag: 'lan-socks',
        listen: '0.0.0.0',
        port: LOCAL_SOCKS_PORT,
        protocol: 'socks',
        settings: {
          auth: 'noauth',
          udp: true,
          ip: '0.0.0.0',
        },
        sniffing: {
          enabled: true,
          destOverride: ['http', 'tls', 'quic'],
          routeOnly: false,
        },
      },
    ],
    outbounds: [
      buildProxyOutbound(node),
      {
        tag: 'direct',
        protocol: 'freedom',
      },
      {
        tag: 'block',
        protocol: 'blackhole',
      },
    ],
    routing: {
      domainStrategy: 'IPIfNonMatch',
      rules: [
        {
          type: 'field',
          ip: [
            'geoip:private',
            '127.0.0.0/8',
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '169.254.0.0/16',
            'fc00::/7',
            'fe80::/10',
          ],
          outboundTag: 'direct',
        },
        {
          type: 'field',
          network: 'tcp,udp',
          outboundTag: 'proxy',
        },
      ],
    },
  };
}

function buildProxyOutbound(node: ProxyNode) {
  switch (node.protocol) {
    case 'vless':
      return {
        tag: 'proxy',
        protocol: 'vless',
        settings: {
          vnext: [
            {
              address: node.server,
              port: node.port,
              users: [
                {
                  id: node.uuid,
                  encryption: 'none',
                  flow: node.flow,
                },
              ],
            },
          ],
        },
        streamSettings: buildStreamSettings(node),
      };
    case 'vmess':
      return {
        tag: 'proxy',
        protocol: 'vmess',
        settings: {
          vnext: [
            {
              address: node.server,
              port: node.port,
              users: [
                {
                  id: node.uuid,
                  alterId: node.alterId ?? 0,
                  security: node.vmessCipher ?? 'auto',
                },
              ],
            },
          ],
        },
        streamSettings: buildStreamSettings(node),
      };
    case 'trojan':
      return {
        tag: 'proxy',
        protocol: 'trojan',
        settings: {
          servers: [
            {
              address: node.server,
              port: node.port,
              password: node.password,
            },
          ],
        },
        streamSettings: buildStreamSettings(node),
      };
    case 'socks5':
      return {
        tag: 'proxy',
        protocol: 'socks',
        settings: {
          servers: [
            {
              address: node.server,
              port: node.port,
              users: node.username
                ? [{user: node.username, pass: node.password ?? ''}]
                : undefined,
            },
          ],
        },
      };
    case 'http':
    case 'https':
      return {
        tag: 'proxy',
        protocol: 'http',
        settings: {
          servers: [
            {
              address: node.server,
              port: node.port,
              users: node.username
                ? [{user: node.username, pass: node.password ?? ''}]
                : undefined,
            },
          ],
        },
      };
    default:
      throw new Error(`${node.protocol.toUpperCase()} is not supported by the Android Xray runtime yet.`);
  }
}

function buildStreamSettings(node: ProxyNode) {
  const network = node.transport === 'grpc' ? 'grpc' : node.transport === 'ws' ? 'ws' : 'tcp';
  const streamSettings: Record<string, unknown> = {
    network,
    security: node.security === 'reality' ? 'reality' : node.security === 'tls' ? 'tls' : 'none',
  };

  if (node.security === 'tls') {
    streamSettings.tlsSettings = {
      serverName: node.sni,
      allowInsecure: node.allowInsecure,
      alpn: node.alpn,
      fingerprint: node.fingerprint,
    };
  }

  if (node.security === 'reality') {
    streamSettings.realitySettings = {
      serverName: node.sni,
      publicKey: node.publicKey,
      shortId: node.shortId,
      fingerprint: node.fingerprint ?? 'chrome',
    };
  }

  if (network === 'ws') {
    streamSettings.wsSettings = {
      path: node.path ?? '/',
      headers: node.wsHost ? {Host: node.wsHost} : undefined,
    };
  }

  if (network === 'grpc') {
    streamSettings.grpcSettings = {
      serviceName: node.path?.replace(/^\//, '') || undefined,
    };
  }

  return streamSettings;
}

export function getXrayLocalSocksPort() {
  return LOCAL_SOCKS_PORT;
}
