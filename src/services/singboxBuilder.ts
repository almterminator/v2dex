import {AppRouteRule, ProxyNode, TunnelMode} from '../types/proxy';

interface BuildOptions {
  node: ProxyNode;
  mode: TunnelMode;
  appRules: AppRouteRule[];
}

export function buildSingboxConfig({node, mode, appRules}: BuildOptions) {
  const ruleSet = mode === 'per-app' ? buildPerAppRuleSet(appRules) : [];
  const useTun = mode === 'full' || (mode === 'per-app' && requiresTun(appRules));
  const finalOutbound = mode === 'per-app' && useTun ? 'direct' : 'proxy';

  return {
    log: {
      level: 'info'
    },
    inbounds: buildInbounds(useTun),
    outbounds: [
      buildProxyOutbound(node),
      {
        tag: 'direct',
        type: 'direct'
      }
    ],
    route: {
      auto_detect_interface: true,
      final: finalOutbound,
      rules: ruleSet
    }
  };
}

function requiresTun(appRules: AppRouteRule[]) {
  return appRules.some(
    rule =>
      rule.enabled &&
      (rule.bundleId === 'ru.keepcoder.Telegram' || rule.bundleId === 'com.tdesktop.Telegram'),
  );
}

function buildInbounds(useTun: boolean) {
  const inbounds = [];

  if (useTun) {
    inbounds.push({
      type: 'tun',
      tag: 'tun-in',
      address: ['172.19.0.1/30'],
      auto_route: true,
      strict_route: true,
      stack: 'system',
    });
  }

  inbounds.push({
    type: 'mixed',
    tag: 'mixed-in',
    listen: '127.0.0.1',
    listen_port: 2080,
    set_system_proxy: false
  });

  return inbounds;
}

function buildPerAppRuleSet(appRules: AppRouteRule[]) {
  const rules = [];

  for (const rule of appRules.filter(item => item.enabled)) {
    const processNames = Array.from(new Set(expandProcessNames(rule)));
    if (processNames.length > 0) {
      rules.push({
        process_name: processNames,
        outbound: 'proxy'
      });
    }

    const pathRegexes = knownProcessPathRegexes(rule.bundleId);
    if (pathRegexes.length > 0) {
      rules.push({
        process_path_regex: pathRegexes,
        outbound: 'proxy'
      });
    }
  }

  return rules;
}

function expandProcessNames(rule: AppRouteRule) {
  const names = new Set<string>();
  const candidates = [rule.processName, rule.name].map(value => value.trim()).filter(Boolean);

  for (const candidate of candidates) {
    names.add(candidate);
    names.add(`${candidate} Helper`);
    names.add(`${candidate} Helper (GPU)`);
    names.add(`${candidate} Helper (Renderer)`);
    names.add(`${candidate}Helper`);
  }

  for (const alias of knownProcessAliases(rule.bundleId)) {
    names.add(alias);
  }

  return Array.from(names);
}

function knownProcessAliases(bundleId: string) {
  switch (bundleId) {
    case 'com.google.Chrome':
      return [
        'Google Chrome',
        'Google Chrome Helper',
        'Google Chrome Helper (GPU)',
        'Google Chrome Helper (Renderer)',
      ];
    case 'com.openai.codex':
      return [
        'Codex',
        'Codex Helper',
        'Codex Helper (GPU)',
        'Codex Helper (Renderer)',
        'codex',
        'node_repl',
      ];
    case 'com.openai.chat':
      return [
        'ChatGPT',
        'ChatGPTHelper',
        'ChatGPT Helper',
        'ChatGPT Helper (GPU)',
        'ChatGPT Helper (Renderer)',
      ];
    case 'ru.keepcoder.Telegram':
    case 'com.tdesktop.Telegram':
      return [
        'Telegram',
        'Telegram Desktop',
        'telegram-desktop',
        'TelegramUpdater',
        'Telegram Helper',
        'Telegram Helper (GPU)',
        'Telegram Helper (Renderer)',
      ];
    case 'com.apple.Safari':
      return [
        'Safari',
        'com.apple.WebKit.Networking',
        'com.apple.WebKit.WebContent',
        'com.apple.WebKit.GPU',
        'com.apple.Safari.SearchHelper',
      ];
    case 'com.microsoft.VSCode':
    case 'com.microsoft.VSCodeInsiders':
      return [
        'Code',
        'Code Helper',
        'Code Helper (GPU)',
        'Code Helper (Renderer)',
      ];
    default:
      return [];
  }
}

function knownProcessPathRegexes(bundleId: string) {
  switch (bundleId) {
    case 'com.openai.codex':
      return [
        '^/.*/Codex\\.app/Contents/MacOS/Codex$',
        '^/.*/Codex\\.app/Contents/Resources/codex$',
        '^/.*/Codex\\.app/Contents/Resources/node_repl$',
        '^/.*/Codex\\.app/Contents/Frameworks/Codex Helper(?: \\(GPU\\)| \\(Renderer\\))?\\.app/Contents/MacOS/Codex Helper(?: \\(GPU\\)| \\(Renderer\\))?$',
      ];
    case 'com.openai.chat':
      return [
        '^/.*/ChatGPT\\.app/Contents/MacOS/ChatGPT$',
        '^/.*/ChatGPT\\.app/Contents/Resources/ChatGPTHelper$',
        '^/.*/ChatGPT\\.app/Contents/Frameworks/ChatGPT Helper(?: \\(GPU\\)| \\(Renderer\\))?\\.app/Contents/MacOS/ChatGPT Helper(?: \\(GPU\\)| \\(Renderer\\))?$',
      ];
    case 'ru.keepcoder.Telegram':
    case 'com.tdesktop.Telegram':
      return [
        '^/.*/Telegram\\.app/Contents/MacOS/Telegram$',
        '^/.*/Telegram Desktop\\.app/Contents/MacOS/Telegram Desktop$',
        '^/.*/Telegram.*\\.app/Contents/MacOS/(?:Telegram|Telegram Desktop|telegram-desktop)$',
      ];
    case 'com.google.Chrome':
      return [
        '^/.*/Google Chrome\\.app/Contents/MacOS/Google Chrome$',
        '^/.*/Google Chrome\\.app/Contents/Frameworks/Google Chrome Framework\\.framework/.*/Helpers/Google Chrome Helper(?: \\(GPU\\)| \\(Renderer\\))?\\.app/Contents/MacOS/Google Chrome Helper(?: \\(GPU\\)| \\(Renderer\\))?$',
      ];
    case 'com.apple.Safari':
      return [
        '^/.*/Safari\\.app/Contents/MacOS/Safari$',
        '^/.*/WebKit\\.framework/.*/XPCServices/com\\.apple\\.WebKit\\.(?:Networking|WebContent|GPU)\\.xpc/Contents/MacOS/com\\.apple\\.WebKit\\.(?:Networking|WebContent|GPU)$',
        '^/.*/SafariShared\\.framework/.*/XPCServices/com\\.apple\\.Safari\\.SearchHelper\\.xpc/Contents/MacOS/com\\.apple\\.Safari\\.SearchHelper$',
      ];
    default:
      return [];
  }
}

function buildProxyOutbound(node: ProxyNode) {
  const tls =
    node.security && node.security !== 'none'
      ? {
          enabled: true,
          server_name: node.sni,
          insecure: node.allowInsecure,
          alpn: node.alpn,
          utls: node.fingerprint ? {enabled: true, fingerprint: node.fingerprint} : undefined,
          reality:
            node.security === 'reality'
              ? {
                  enabled: true,
                  public_key: node.publicKey,
                  short_id: node.shortId
                }
              : undefined
        }
      : undefined;

  const common = {
    tag: 'proxy',
    server: node.server,
    server_port: node.port
  };

  switch (node.protocol) {
    case 'vless':
      return {
        ...common,
        type: 'vless',
        uuid: node.uuid,
        flow: node.flow,
        tls,
        transport: buildTransport(node),
        udp_over_tcp: node.udpOverTCP ? {enabled: true} : undefined
      };
    case 'vmess':
      return {
        ...common,
        type: 'vmess',
        uuid: node.uuid,
        alter_id: node.alterId,
        security: node.vmessCipher ?? 'auto',
        tls,
        transport: buildTransport(node)
      };
    case 'hysteria2':
      return {
        ...common,
        type: 'hysteria2',
        password: node.password,
        tls
      };
    case 'tuic':
      return {
        ...common,
        type: 'tuic',
        uuid: node.uuid,
        password: node.password,
        tls
      };
    case 'trojan':
      return {
        ...common,
        type: 'trojan',
        password: node.password,
        tls,
        transport: buildTransport(node)
      };
    case 'http':
    case 'https':
      return {
        ...common,
        type: 'http',
        username: node.username,
        password: node.password,
        tls,
      };
    case 'socks5':
      return {
        ...common,
        type: 'socks',
        version: '5',
        username: node.username,
        password: node.password,
      };
    default:
      return {
        ...common,
        type: node.protocol,
        tls,
        transport: buildTransport(node)
      };
  }
}

function buildTransport(node: ProxyNode) {
  if (node.transport === 'ws') {
    return {
      type: 'ws',
      path: node.path ?? '/',
      headers: node.wsHost ? {Host: node.wsHost} : undefined
    };
  }

  if (node.transport === 'grpc') {
    return {type: 'grpc', service_name: node.path ?? 'grpc'};
  }

  if (node.transport === 'httpupgrade') {
    return {
      type: 'httpupgrade',
      path: node.path ?? '/',
      host: node.wsHost
    };
  }

  return undefined;
}
