import {create} from 'zustand';
import {Platform} from 'react-native';
import {importProfileFromRaw} from '../services/configParser';
import {measureTunnelLatency} from '../services/latency';
import {
  discoverInstalledApps,
  copyTextToClipboard,
  getTunnelIpInfo,
  getNativeTunnelStatus,
  importClipboardText,
  importProfileFromUri,
  loadPersistedAppState,
  savePersistedAppState,
  scanQrFromCamera as scanNativeQrFromCamera,
  scanQrFromGallery as scanNativeQrFromGallery,
  startNativeTunnel,
  stopNativeTunnel,
  testProfileDownload as runProfileDownloadTest,
  testServerConnection as runServerConnectionTest,
  testTunnelHttpLatency as runTunnelHttpLatencyTest,
} from '../services/nativeBackend';
import {AppRouteRule, ProxyNode, SubscriptionProfile, TunnelMode, TunnelStatus} from '../types/proxy';

const defaultTunnel: TunnelStatus = {
  connected: false,
  connecting: false,
  mode: 'full',
  backend: 'system-proxy',
  dnsLeakProtection: true,
  proxyHost: Platform.OS === 'android' ? '0.0.0.0' : '127.0.0.1',
  proxyPort: Platform.OS === 'android' ? 43080 : 2080,
};

const delay = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));

const priorityAppBundleIds = new Set([
  'com.openai.codex',
  'com.google.Chrome',
  'ru.keepcoder.Telegram',
  'com.tdesktop.Telegram',
  'com.openai.chat',
  'com.microsoft.VSCode',
  'org.telegram.messenger',
  'org.thunderdog.challegram',
  'com.android.chrome',
  'com.chrome.beta',
  'com.chrome.dev',
  'com.chrome.canary',
  'com.google.android.googlequicksearchbox',
  'com.google.android.apps.bard',
  'com.openai.chatgpt',
]);

const noisySystemPackagePrefixes = [
  'android.',
  'com.android.',
  'com.google.android.adservices',
  'com.google.android.ext.',
  'com.google.android.ondevicepersonalization',
  'com.google.android.permission',
  'com.google.android.scheduling',
  'com.google.android.setupwizard',
  'com.google.android.tzdata',
  'com.samsung.android.',
];

const defaultDesktopAppRules: AppRouteRule[] = Platform.OS === 'macos'
  ? [
      {
        bundleId: 'com.openai.codex',
        name: 'Codex',
        enabled: true,
        processName: 'Codex',
      },
      {
        bundleId: 'com.google.Chrome',
        name: 'Google Chrome',
        enabled: true,
        processName: 'Google Chrome',
      },
      {
        bundleId: 'ru.keepcoder.Telegram',
        name: 'Telegram',
        enabled: true,
        processName: 'Telegram',
      },
    ]
  : [];

async function measureTunnelLatencyWithRetry(attempts = 3): Promise<number> {
  let lastError: unknown;

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await measureTunnelLatency();
    } catch (error) {
      lastError = error;
      if (attempt < attempts - 1) {
        await delay(1200 * (attempt + 1));
      }
    }
  }

  throw lastError instanceof Error ? lastError : new Error('Latency probe failed.');
}

interface PersistedAppState {
  profiles: SubscriptionProfile[];
  appRules: AppRouteRule[];
  activeProfileId?: string;
  activeNodeId?: string;
  importDraft: string;
  mode: TunnelMode;
}

interface AppState {
  hydrated: boolean;
  profiles: SubscriptionProfile[];
  appRules: AppRouteRule[];
  tunnel: TunnelStatus;
  importDraft: string;
  activeProfile?: SubscriptionProfile;
  activeNode?: ProxyNode;
  hydrate: () => Promise<void>;
  selectNode: (profileId: string, nodeId: string) => void;
  selectProfile: (profileId: string) => void;
  setMode: (mode: TunnelMode) => void;
  toggleAppRule: (bundleId: string) => void;
  setImportDraft: (value: string) => void;
  setConnecting: (connecting: boolean) => void;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  importProfile: (profile: SubscriptionProfile) => Promise<void>;
  importFromClipboard: (text?: string) => Promise<void>;
  importFromUri: (uri: string) => Promise<void>;
  importQrFromCamera: () => Promise<void>;
  importQrFromGallery: () => Promise<void>;
  removeProfile: (profileId: string) => Promise<void>;
  renameProfile: (profileId: string, title: string) => Promise<void>;
  discoverApps: () => Promise<void>;
  refreshSubscriptions: () => Promise<void>;
  refreshTunnelStatus: () => Promise<void>;
  refreshExitIpInfo: () => Promise<void>;
  testProfileDownload: (profileId: string) => Promise<string>;
  testServerConnection: (profileId: string) => Promise<string>;
  pingAllProfiles: () => Promise<Record<string, number | 'TO'>>;
  copyActiveProfileLink: () => Promise<void>;
  copyProfileLink: (profileId: string) => Promise<void>;
  copyLocalProxyCommand: (host: string, port: number) => Promise<void>;
  refreshPing: () => Promise<void>;
}

function pickActiveProfile(
  profiles: SubscriptionProfile[],
  activeProfileId?: string,
): SubscriptionProfile | undefined {
  return profiles.find(item => item.id === activeProfileId) ?? profiles[0];
}

function pickActiveNode(
  profile: SubscriptionProfile | undefined,
  activeNodeId?: string,
): ProxyNode | undefined {
  if (!profile) {
    return undefined;
  }
  return profile.nodes.find(item => item.id === activeNodeId) ?? profile.nodes[0];
}

function mergeAppRules(current: AppRouteRule[], incoming: AppRouteRule[]) {
  const currentByBundle = new Map(current.map(rule => [rule.bundleId, rule]));
  return incoming.filter(isVisibleAppRule).map(rule => {
    const existing = currentByBundle.get(rule.bundleId);
    return existing ? {...rule, enabled: existing.enabled} : rule;
  }).sort((a, b) => {
    const priorityDelta =
      Number(!priorityAppBundleIds.has(a.bundleId)) - Number(!priorityAppBundleIds.has(b.bundleId));
    return priorityDelta || a.name.localeCompare(b.name);
  });
}

function withDefaultDesktopAppRules(appRules: AppRouteRule[]) {
  if (defaultDesktopAppRules.length === 0) {
    return appRules;
  }

  const rulesByBundle = new Map(appRules.map(rule => [rule.bundleId, rule]));
  for (const rule of defaultDesktopAppRules) {
    const existing = rulesByBundle.get(rule.bundleId);
    if (existing && rule.bundleId === 'com.openai.codex') {
      rulesByBundle.set(rule.bundleId, {...existing, enabled: true});
    } else if (!existing) {
      rulesByBundle.set(rule.bundleId, rule);
    }
  }

  return mergeAppRules(Array.from(rulesByBundle.values()), Array.from(rulesByBundle.values()));
}

function isVisibleAppRule(rule: AppRouteRule) {
  if (priorityAppBundleIds.has(rule.bundleId) || rule.enabled) {
    return true;
  }

  return !noisySystemPackagePrefixes.some(prefix => rule.bundleId.startsWith(prefix));
}

function serializeState(state: AppState): PersistedAppState {
  return {
    profiles: state.profiles,
    appRules: state.appRules,
    activeProfileId: state.activeProfile?.id,
    activeNodeId: state.activeNode?.id,
    importDraft: state.importDraft,
    mode: state.tunnel.mode,
  };
}

async function persistStateSnapshot(state: AppState) {
  await savePersistedAppState(JSON.stringify(serializeState(state)));
}

async function measurePingButtonLatency(
  state: AppState,
  node: ProxyNode,
  profileId?: string,
): Promise<number> {
  const shouldTestActiveTunnel =
    state.tunnel.connected &&
    state.tunnel.proxyPort &&
    (!profileId || profileId === state.activeProfile?.id);
  const latencyMs = shouldTestActiveTunnel
    ? Platform.OS === 'android'
      ? (await runTunnelHttpLatencyTest()).latencyMs
      : await measureTunnelLatencyWithRetry()
    : (await runServerConnectionTest(node)).latencyMs;

  if (typeof latencyMs !== 'number') {
    throw new Error('Ping test did not return a latency.');
  }

  return latencyMs;
}

function mergeImportedProfileData(
  currentProfile: SubscriptionProfile,
  next: {nodes: ProxyNode[]; usage?: SubscriptionProfile['usage']},
): SubscriptionProfile {
  const latencyByNodeId = new Map(currentProfile.nodes.map(node => [node.id, node.latencyMs]));

  return {
    ...currentProfile,
    updatedAt: new Date().toISOString(),
    usage: next.usage ?? currentProfile.usage,
    trafficUsedGB:
      typeof next.usage?.usedBytes === 'number'
        ? next.usage.usedBytes / (1024 ** 3)
        : currentProfile.trafficUsedGB,
    trafficTotalGB:
      typeof next.usage?.totalBytes === 'number'
        ? next.usage.totalBytes / (1024 ** 3)
        : currentProfile.trafficTotalGB,
    title: currentProfile.title,
    nodes: next.nodes.map(node => ({
      ...node,
      latencyMs: latencyByNodeId.get(node.id) ?? node.latencyMs,
    })),
  };
}

function buildImportedProfile(
  sourceValue: string,
  payload: {nodes: ProxyNode[]; usage?: SubscriptionProfile['usage']},
): SubscriptionProfile {
  const title = payload.nodes[0]?.name?.trim() || (sourceValue.startsWith('http') ? 'Imported Subscription' : 'Imported URI');
  return {
    id: `profile-${Date.now()}`,
    title,
    source: sourceValue.startsWith('http') ? 'subscription' : 'uri',
    sourceValue,
    updatedAt: new Date().toISOString(),
    trafficUsedGB:
      typeof payload.usage?.usedBytes === 'number' ? payload.usage.usedBytes / (1024 ** 3) : undefined,
    trafficTotalGB:
      typeof payload.usage?.totalBytes === 'number' ? payload.usage.totalBytes / (1024 ** 3) : undefined,
    usage: payload.usage,
    nodes: payload.nodes,
  };
}

export const useAppStore = create<AppState>((set, get) => ({
  hydrated: false,
  profiles: [],
  appRules: [],
  tunnel: defaultTunnel,
  importDraft: '',
  activeProfile: undefined,
  activeNode: undefined,
  hydrate: async () => {
    if (get().hydrated) {
      return;
    }

    try {
      const raw = await loadPersistedAppState();
      if (raw) {
        const parsed = JSON.parse(raw) as PersistedAppState;
        const appRules = withDefaultDesktopAppRules((parsed.appRules ?? []).filter(isVisibleAppRule));
        const activeProfile = pickActiveProfile(parsed.profiles ?? [], parsed.activeProfileId);
        const activeNode = pickActiveNode(activeProfile, parsed.activeNodeId);

        set(state => ({
          ...state,
          hydrated: true,
          profiles: parsed.profiles ?? [],
          appRules,
          importDraft: parsed.importDraft ?? '',
          activeProfile,
          activeNode,
          tunnel: {
            ...state.tunnel,
            mode: parsed.mode ?? state.tunnel.mode,
            activeProfileId: activeProfile?.id,
            activeNodeId: activeNode?.id,
          },
        }));
      } else {
        set({hydrated: true, appRules: withDefaultDesktopAppRules([])});
      }
    } catch {
      set({hydrated: true});
    }
  },
  selectNode: (profileId, nodeId) => {
    const profile = get().profiles.find(item => item.id === profileId);
    const node = profile?.nodes.find(item => item.id === nodeId);
    if (!profile || !node) {
      return;
    }

    set(state => ({
      activeProfile: profile,
      activeNode: node,
      tunnel: {
        ...state.tunnel,
        activeProfileId: profile.id,
        activeNodeId: node.id,
      },
    }));
    void persistStateSnapshot(get());
  },
  selectProfile: profileId => {
    const profile = get().profiles.find(item => item.id === profileId);
    if (!profile) {
      return;
    }

    set(state => ({
      activeProfile: profile,
      activeNode: profile.nodes[0],
      tunnel: {
        ...state.tunnel,
        activeProfileId: profile.id,
        activeNodeId: profile.nodes[0]?.id,
      },
    }));
    void persistStateSnapshot(get());
  },
  setMode: mode => {
    set(state => ({
      tunnel: {
        ...state.tunnel,
        mode,
      },
    }));
    void persistStateSnapshot(get());
  },
  toggleAppRule: bundleId => {
    set(state => ({
      appRules: state.appRules.map(rule =>
        rule.bundleId === bundleId ? {...rule, enabled: !rule.enabled} : rule,
      ),
    }));
    void persistStateSnapshot(get());
  },
  setImportDraft: value => {
    set({importDraft: value});
    void persistStateSnapshot(get());
  },
  setConnecting: connecting => {
    set(state => ({
      tunnel: {
        ...state.tunnel,
        connecting,
      },
    }));
  },
  connect: async () => {
    const state = get();
    if (!state.activeNode) {
      set(current => ({
        tunnel: {
          ...current.tunnel,
          lastError: 'No active node selected.',
        },
      }));
      return;
    }

    if (state.tunnel.mode === 'per-app' && !state.appRules.some(rule => rule.enabled)) {
      set(current => ({
        tunnel: {
          ...current.tunnel,
          lastError: 'Select at least one app for per-app proxy mode.',
        },
      }));
      return;
    }

    set(current => ({
      tunnel: {
        ...current.tunnel,
        connecting: true,
        lastError: undefined,
      },
    }));

    try {
      const snapshot = await startNativeTunnel({
        node: state.activeNode,
        mode: state.tunnel.mode,
        appRules: state.appRules,
      });
      set(current => ({
        tunnel: {
          ...current.tunnel,
          connected: snapshot.connected,
          connecting: snapshot.connecting,
          mode: snapshot.mode,
          backend: snapshot.backend,
          lastError: snapshot.lastError,
          lastConnectedAt: snapshot.lastConnectedAt,
          binaryPath: snapshot.binaryPath,
          activeConfigPath: snapshot.activeConfigPath,
          proxyHost: snapshot.proxyHost,
          proxyPort: snapshot.proxyPort,
          pingTimedOut: false,
          activeProfileId: current.activeProfile?.id,
          activeNodeId: current.activeNode?.id,
        },
      }));
      await delay(state.tunnel.mode === 'full' ? 1500 : 800);
      await get().refreshTunnelStatus();

      if (get().tunnel.connected) {
        await get().refreshPing();
        void get().refreshExitIpInfo();
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Native tunnel start failed.';
      set(current => ({
        tunnel: {
          ...current.tunnel,
          connected: false,
          connecting: false,
          lastError: message,
        },
      }));
    }
  },
  disconnect: async () => {
    try {
      await stopNativeTunnel();
    } catch {}

    set(state => ({
      tunnel: {
        ...state.tunnel,
        connected: false,
        connecting: false,
        backend: undefined,
        proxyHost: undefined,
        proxyPort: undefined,
        activeConfigPath: undefined,
        exitIp: undefined,
        exitCountry: undefined,
        exitCountryCode: undefined,
      },
    }));
  },
  importProfile: async profile => {
    set(state => ({
      profiles: [profile, ...state.profiles.filter(item => item.id !== profile.id)],
      activeProfile: profile,
      activeNode: profile.nodes[0],
      importDraft: '',
      tunnel: {
        ...state.tunnel,
        activeProfileId: profile.id,
        activeNodeId: profile.nodes[0]?.id,
      },
    }));
    await persistStateSnapshot(get());
  },
  importFromClipboard: async text => {
    const source = text ?? (await importClipboardText());
    const cleaned = source.trim();
    if (!cleaned) {
      return;
    }

    try {
      const payload = await importProfileFromUri(cleaned);
      if (payload.nodes.length > 0) {
        await get().importProfile(buildImportedProfile(cleaned, payload));
        return;
      }
    } catch (error) {
      if (!(error instanceof Error)) {
        set(state => ({
          tunnel: {
            ...state.tunnel,
            lastError: 'Clipboard import failed.',
          },
        }));
        return;
      }
    }

    try {
      const profile = importProfileFromRaw(cleaned);
      await get().importProfile(profile);
    } catch (error) {
      set(state => ({
        tunnel: {
          ...state.tunnel,
          lastError: error instanceof Error ? error.message : 'Clipboard import failed.',
        },
      }));
    }
  },
  importFromUri: async uri => {
    const cleaned = uri.trim();
    if (!cleaned) {
      return;
    }

    try {
      const payload = await importProfileFromUri(cleaned);
      if (payload.nodes.length > 0) {
        await get().importProfile(buildImportedProfile(cleaned, payload));
        return;
      }
    } catch (error) {
      set(state => ({
        tunnel: {
          ...state.tunnel,
          lastError: error instanceof Error ? error.message : 'Import failed.',
        },
      }));
      return;
    }

    try {
      const profile = importProfileFromRaw(cleaned);
      await get().importProfile(profile);
    } catch (error) {
      set(state => ({
        tunnel: {
          ...state.tunnel,
          lastError: error instanceof Error ? error.message : 'Import failed.',
        },
      }));
    }
  },
  importQrFromCamera: async () => {
    const value = await scanNativeQrFromCamera();
    await get().importFromUri(value);
  },
  importQrFromGallery: async () => {
    const value = await scanNativeQrFromGallery();
    await get().importFromUri(value);
  },
  removeProfile: async profileId => {
    set(state => {
      const profiles = state.profiles.filter(item => item.id !== profileId);
      const activeProfile = state.activeProfile?.id === profileId ? profiles[0] : state.activeProfile;
      const activeNode =
        state.activeProfile?.id === profileId ? activeProfile?.nodes[0] : pickActiveNode(activeProfile, state.activeNode?.id);

      return {
        profiles,
        activeProfile,
        activeNode,
        tunnel: {
          ...state.tunnel,
          activeProfileId: activeProfile?.id,
          activeNodeId: activeNode?.id,
        },
      };
    });
    await persistStateSnapshot(get());
  },
  renameProfile: async (profileId, title) => {
    const nextTitle = title.trim();
    if (!nextTitle) {
      return;
    }

    set(state => {
      const profiles = state.profiles.map(profile =>
        profile.id === profileId ? {...profile, title: nextTitle} : profile,
      );
      const activeProfile = state.activeProfile?.id === profileId
        ? profiles.find(profile => profile.id === profileId)
        : state.activeProfile;

      return {
        profiles,
        activeProfile,
      };
    });
    await persistStateSnapshot(get());
  },
  discoverApps: async () => {
    try {
      const apps = await discoverInstalledApps();
      if (apps.length > 0) {
        set(state => ({
          appRules: mergeAppRules(state.appRules, apps),
        }));
        await persistStateSnapshot(get());
      }
    } catch {}
  },
  refreshSubscriptions: async () => {
    const subscriptionProfiles = get().profiles.filter(profile => profile.source === 'subscription');
    if (subscriptionProfiles.length === 0) {
      return;
    }

    const nextProfiles = await Promise.all(
      subscriptionProfiles.map(async profile => {
        try {
          const payload = await importProfileFromUri(profile.sourceValue);
          if (payload.nodes.length === 0) {
            return null;
          }

          return {
            id: profile.id,
            profile: mergeImportedProfileData(profile, payload),
          };
        } catch {
          return null;
        }
      }),
    );

    const updates = new Map(
      nextProfiles
        .filter((item): item is {id: string; profile: SubscriptionProfile} => item !== null)
        .map(item => [item.id, item.profile]),
    );

    if (updates.size === 0) {
      return;
    }

    set(state => {
      const profiles = state.profiles.map(profile => updates.get(profile.id) ?? profile);
      const activeProfile = state.activeProfile
        ? profiles.find(profile => profile.id === state.activeProfile?.id)
        : undefined;
      const activeNode = pickActiveNode(activeProfile, state.activeNode?.id);

      return {
        profiles,
        activeProfile,
        activeNode,
        tunnel: {
          ...state.tunnel,
          activeProfileId: activeProfile?.id,
          activeNodeId: activeNode?.id,
        },
      };
    });
    await persistStateSnapshot(get());
  },
  refreshTunnelStatus: async () => {
    try {
      const status = await getNativeTunnelStatus();
      if (!status) {
        return;
      }

      set(state => ({
        tunnel: {
          ...state.tunnel,
          connected: status.connected,
          connecting: status.connecting,
          mode: status.connected || status.connecting ? status.mode : state.tunnel.mode,
          backend: status.backend,
          lastError: status.lastError,
          lastConnectedAt: status.lastConnectedAt,
          binaryPath: status.binaryPath,
          activeConfigPath: status.activeConfigPath,
          proxyHost: status.proxyHost,
          proxyPort: status.proxyPort,
          pingMs: status.proxyPort ? state.tunnel.pingMs : undefined,
          exitIp: status.connected ? state.tunnel.exitIp : undefined,
          exitCountry: status.connected ? state.tunnel.exitCountry : undefined,
          exitCountryCode: status.connected ? state.tunnel.exitCountryCode : undefined,
        },
      }));
    } catch {}
  },
  refreshExitIpInfo: async () => {
    const state = get();
    if (!state.tunnel.connected || !state.tunnel.proxyPort) {
      return;
    }

    try {
      const info = await getTunnelIpInfo();
      set(current => ({
        tunnel: {
          ...current.tunnel,
          exitIp: info.ip,
          exitCountry: info.country,
          exitCountryCode: info.countryCode?.toUpperCase(),
        },
      }));
    } catch {}
  },
  testProfileDownload: async profileId => {
    const profile = get().profiles.find(item => item.id === profileId);
    if (!profile) {
      throw new Error('Profile not found.');
    }

    if (profile.source !== 'subscription') {
      return 'This config is not a subscription link.';
    }

    return runProfileDownloadTest(profile.sourceValue);
  },
  testServerConnection: async profileId => {
    const profile = get().profiles.find(item => item.id === profileId);
    const node = profile?.nodes[0];
    if (!node) {
      throw new Error('No node found for this profile.');
    }

    const result = await runServerConnectionTest(node);
    return result.message;
  },
  pingAllProfiles: async () => {
    const profiles = get().profiles;
    const results: Record<string, number | 'TO'> = {};

    await Promise.all(
      profiles.map(async profile => {
        const node = profile.nodes[0];
        if (!node) {
          results[profile.id] = 'TO';
          return;
        }

        try {
          results[profile.id] = await measurePingButtonLatency(get(), node, profile.id);
        } catch {
          results[profile.id] = 'TO';
        }
      }),
    );

    set(state => {
      const profilesWithLatency = state.profiles.map(profile => {
        const latency = results[profile.id];
        if (typeof latency !== 'number') {
          return profile;
        }

        return {
          ...profile,
          nodes: profile.nodes.map((node, index) =>
            index === 0 ? {...node, latencyMs: latency} : node,
          ),
        };
      });
      const activeProfile = state.activeProfile
        ? profilesWithLatency.find(profile => profile.id === state.activeProfile?.id)
        : undefined;
      const activeNode = pickActiveNode(activeProfile, state.activeNode?.id);

      return {
        profiles: profilesWithLatency,
        activeProfile,
        activeNode,
      };
    });
    await persistStateSnapshot(get());

    return results;
  },
  copyActiveProfileLink: async () => {
    const profile = get().activeProfile;
    await get().copyProfileLink(profile?.id ?? '');
  },
  copyProfileLink: async profileId => {
    const profile = get().profiles.find(item => item.id === profileId);
    const link = profile?.nodes.find(node => node.rawUri)?.rawUri
      ?? (profile?.sourceValue.match(/^(vless|hysteria2|tuic):\/\//i) ? profile.sourceValue : undefined)
      ?? profile?.sourceValue;

    if (!link) {
      throw new Error('No config link is available to copy.');
    }

    await copyTextToClipboard(link);
  },
  copyLocalProxyCommand: async (host, port) => {
    const command = `autossh -M 0 -N \\
  -o ExitOnForwardFailure=yes \\
  -o ServerAliveInterval=30 \\
  -o ServerAliveCountMax=3 \\
  -R ${host}:${port} \\
  root@5.160.218.99`;
    await copyTextToClipboard(command);
  },
  refreshPing: async () => {
    const state = get();
    if (!state.activeNode) {
      return;
    }

    try {
      const latencyMs = await measurePingButtonLatency(state, state.activeNode);

      set(current => ({
        activeNode: current.activeNode
          ? {...current.activeNode, latencyMs}
          : current.activeNode,
        profiles: current.profiles.map(profile =>
          profile.id !== current.activeProfile?.id
            ? profile
            : {
                ...profile,
                nodes: profile.nodes.map(node =>
                  node.id === current.activeNode?.id
                    ? {...node, latencyMs}
                    : node,
                ),
              },
        ),
        tunnel: {
          ...current.tunnel,
          pingMs: latencyMs,
          pingTimedOut: false,
          lastError: undefined,
        },
      }));
      await persistStateSnapshot(get());
    } catch (error) {
      set(current => ({
        tunnel: {
          ...current.tunnel,
          pingMs: undefined,
          pingTimedOut: true,
          lastError: error instanceof Error ? error.message : 'Ping failed.',
        },
      }));
    }
  },
}));
