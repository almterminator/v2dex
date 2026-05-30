import React from 'react';
import {
  Alert,
  Image,
  Modal,
  Platform,
  TextInput,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  useWindowDimensions,
  View
} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {AppGradient} from '../components/AppGradient';
import {GlassCard} from '../components/GlassCard';
import {Sidebar} from '../components/Sidebar';
import {StatPill} from '../components/StatPill';
import {buildManualProfile} from '../services/configParser';
import {colors, radii, spacing} from '../theme/tokens';
import {useAppStore} from '../state/appStore';

export function DashboardScreen() {
  const {width} = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const isCompact = width < 760;
  const isDesktop = Platform.OS === 'macos' || Platform.OS === 'windows';
  const [language, setLanguage] = React.useState<'en' | 'fa'>('en');
  const isPersian = language === 'fa';
  const textDirectionStyle = isPersian ? styles.rtlText : styles.ltrText;
  const t = React.useCallback((key: TranslationKey) => translations[language][key], [language]);
  const {
    activeProfile,
    activeNode,
    appRules,
    connect,
    disconnect,
    discoverApps,
    hydrate,
    importProfile,
    importDraft,
    importFromClipboard,
    importFromUri,
    importQrFromCamera,
    profiles,
    refreshPing,
    refreshSubscriptions,
    refreshTunnelStatus,
    renameProfile,
    removeProfile,
    pingAllProfiles,
    copyProfileLink,
    copyLocalProxyCommand,
    selectProfile,
    setImportDraft,
    setMode,
    toggleAppRule,
    tunnel
  } = useAppStore();
  const [contextMenu, setContextMenu] = React.useState<
    | {
        kind: 'profile';
        profileId: string;
        x: number;
        y: number;
      }
    | {
        kind: 'import';
        x: number;
        y: number;
      }
    | null
  >(null);
  const [renameDialog, setRenameDialog] = React.useState<{
    profileId: string;
    value: string;
  } | null>(null);
  const [importDialogOpen, setImportDialogOpen] = React.useState(false);
  const [manualDialogOpen, setManualDialogOpen] = React.useState(false);
  const [manualProtocol, setManualProtocol] = React.useState<'http' | 'https' | 'socks5'>('http');
  const [manualName, setManualName] = React.useState('');
  const [manualHost, setManualHost] = React.useState('');
  const [manualPort, setManualPort] = React.useState('');
  const [manualUsername, setManualUsername] = React.useState('');
  const [manualPassword, setManualPassword] = React.useState('');
  const [refreshingTraffic, setRefreshingTraffic] = React.useState(false);
  const [discoveringApps, setDiscoveringApps] = React.useState(false);
  const [pingingAll, setPingingAll] = React.useState(false);
  const [appSearchQuery, setAppSearchQuery] = React.useState('');
  const [profilePingResults, setProfilePingResults] = React.useState<Record<string, number | 'TO'> | null>(null);
  const clearPingResultsRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const statusColor = tunnel.connecting ? colors.danger : tunnel.connected ? colors.success : colors.info;
  const statusTintSoft = withAlpha(statusColor, 0.1);
  const statusTint = withAlpha(statusColor, 0.14);
  const statusBorder = withAlpha(statusColor, 0.4);

  React.useEffect(() => {
    void hydrate();
    const timeout = setTimeout(() => {
      void refreshTunnelStatus();
    }, 600);

    return () => clearTimeout(timeout);
  }, [hydrate, refreshTunnelStatus]);

  React.useEffect(() => {
    const interval = setInterval(() => {
      void refreshTunnelStatus();
    }, 6000);

    return () => clearInterval(interval);
  }, [refreshTunnelStatus]);

  React.useEffect(() => {
    const interval = setInterval(() => {
      void refreshSubscriptions();
    }, 60_000);

    return () => clearInterval(interval);
  }, [refreshSubscriptions]);

  const parsedTrafficFromTitle = parseRemainingTrafficLabel(activeProfile?.title);
  const trafficFillPercent = getTrafficFillPercent(activeProfile);
  const remainingTraffic =
    typeof activeProfile?.usage?.remainingBytes === 'number'
      ? formatBytes(activeProfile.usage.remainingBytes)
      : parsedTrafficFromTitle ??
        (typeof activeProfile?.trafficTotalGB === 'number' &&
        typeof activeProfile?.trafficUsedGB === 'number'
          ? `${Math.max(activeProfile.trafficTotalGB - activeProfile.trafficUsedGB, 0).toFixed(1)} GB`
          : 'N/A');
  const socksHost = tunnel.proxyHost && tunnel.proxyHost !== '0.0.0.0' ? tunnel.proxyHost : '0.0.0.0';
  const socksPort = tunnel.proxyPort ?? 43080;
  const filteredAppRules = React.useMemo(() => {
    const query = appSearchQuery.trim().toLowerCase();
    const visibleRules = query
      ? appRules.filter(rule =>
          [rule.name, rule.processName, rule.bundleId].some(value => value.toLowerCase().includes(query)),
        )
      : appRules;

    return visibleRules
      .map((rule, index) => ({rule, index}))
      .sort((a, b) => Number(b.rule.enabled) - Number(a.rule.enabled) || a.index - b.index)
      .map(item => item.rule);
  }, [appRules, appSearchQuery]);

  React.useEffect(
    () => () => {
      if (clearPingResultsRef.current) {
        clearTimeout(clearPingResultsRef.current);
      }
    },
    [],
  );

  const handleDiscoverApps = React.useCallback(async () => {
    if (discoveringApps) {
      return;
    }

    setDiscoveringApps(true);
    try {
      await discoverApps();
    } finally {
      setDiscoveringApps(false);
    }
  }, [discoverApps, discoveringApps]);

  const handleRefreshTraffic = React.useCallback(async () => {
    if (refreshingTraffic || activeProfile?.source !== 'subscription') {
      return;
    }

    setRefreshingTraffic(true);

    try {
      await refreshSubscriptions();
    } finally {
      setRefreshingTraffic(false);
    }
  }, [activeProfile?.source, refreshSubscriptions, refreshingTraffic]);

  const openRenameDialog = React.useCallback(
    (profileId: string) => {
      const profile = profiles.find(item => item.id === profileId);
      if (!profile) {
        return;
      }
      setRenameDialog({
        profileId,
        value: profile.title,
      });
    },
    [profiles],
  );

  const closeManualDialog = React.useCallback(() => {
    setManualDialogOpen(false);
    setManualProtocol('http');
    setManualName('');
    setManualHost('');
    setManualPort('');
    setManualUsername('');
    setManualPassword('');
  }, []);

  const handleImportSubmit = React.useCallback(async () => {
    await importFromUri(importDraft);
    setImportDialogOpen(false);
  }, [importDraft, importFromUri]);

  const handleClipboardImport = React.useCallback(async () => {
    await importFromClipboard();
    setImportDialogOpen(false);
  }, [importFromClipboard]);

  const handleQrCameraImport = React.useCallback(async () => {
    try {
      await importQrFromCamera();
      setImportDialogOpen(false);
    } catch (error) {
      const message = error instanceof Error ? error.message : t('unknownError');
      if (!/cancel/i.test(message)) {
        Alert.alert(t('operationFailed'), message);
      }
    }
  }, [importQrFromCamera, t]);

  const handleRoutingModeToggle = React.useCallback(
    async (enabled: boolean) => {
      const nextMode: 'per-app' | 'full' = enabled ? 'per-app' : 'full';
      if (nextMode === tunnel.mode) {
        return;
      }

      setMode(nextMode);
      if (tunnel.connected) {
        await disconnect();
        await connect();
      }
    },
    [connect, disconnect, setMode, tunnel.connected, tunnel.mode],
  );

  const handleAppRuleToggle = React.useCallback(
    async (bundleId: string) => {
      toggleAppRule(bundleId);
      if (tunnel.connected && tunnel.mode === 'per-app') {
        await disconnect();
        await connect();
      }
    },
    [connect, disconnect, toggleAppRule, tunnel.connected, tunnel.mode],
  );

  const handlePingAllProfiles = React.useCallback(async () => {
    if (pingingAll) {
      return;
    }

    setPingingAll(true);
    try {
      const results = await pingAllProfiles();
      setProfilePingResults(results);
      if (clearPingResultsRef.current) {
        clearTimeout(clearPingResultsRef.current);
      }
      clearPingResultsRef.current = setTimeout(() => {
        setProfilePingResults(null);
        clearPingResultsRef.current = null;
      }, 10_000);
    } catch (error) {
      Alert.alert(t('operationFailed'), error instanceof Error ? error.message : t('unknownError'));
    } finally {
      setPingingAll(false);
    }
  }, [pingAllProfiles, pingingAll, t]);

  const handleProfileMenuAction = React.useCallback(
    async (action: 'copy' | 'rename' | 'delete', profileId: string) => {
      setContextMenu(null);

      try {
        if (action === 'rename') {
          openRenameDialog(profileId);
          return;
        }

        if (action === 'copy') {
          await copyProfileLink(profileId);
          Alert.alert(t('copied'), t('configLinkCopied'));
          return;
        }

        await removeProfile(profileId);
      } catch (error) {
        Alert.alert(
          t('operationFailed'),
          error instanceof Error ? error.message : t('unknownError'),
        );
      }
    },
    [copyProfileLink, openRenameDialog, removeProfile, t],
  );

  const handleCopyLocalProxyCommand = React.useCallback(async () => {
    try {
      await copyLocalProxyCommand(socksHost, socksPort);
      Alert.alert(t('copied'), t('autosshCopied'));
    } catch (error) {
      Alert.alert(t('operationFailed'), error instanceof Error ? error.message : t('unknownError'));
    }
  }, [copyLocalProxyCommand, socksHost, socksPort, t]);

  const handleRenameSubmit = React.useCallback(async () => {
    if (!renameDialog) {
      return;
    }

    const title = renameDialog.value.trim();
    if (!title) {
      Alert.alert(t('editName'), t('nameCannotBeEmpty'));
      return;
    }

    await renameProfile(renameDialog.profileId, title);
    setRenameDialog(null);
  }, [renameDialog, renameProfile, t]);

  const handleManualImport = React.useCallback(async () => {
    const host = manualHost.trim();
    const port = Number(manualPort);

    if (!host) {
      Alert.alert(t('manualConfig'), t('addressRequired'));
      return;
    }

    if (!Number.isFinite(port) || port <= 0 || port > 65535) {
      Alert.alert(t('manualConfig'), t('portRange'));
      return;
    }

    await importProfile(
      buildManualProfile({
        protocol: manualProtocol,
        host,
        port,
        username: manualUsername,
        password: manualPassword,
        name: manualName,
      }),
    );
    closeManualDialog();
  }, [
    closeManualDialog,
    importProfile,
    manualHost,
    manualName,
    manualPassword,
    manualPort,
    manualProtocol,
    manualUsername,
    t,
  ]);

  return (
    <AppGradient
      colors={[colors.backgroundTop, colors.backgroundBottom]}
      style={styles.background}>
      <View style={styles.glowA} />
      <View style={[styles.glowB, {backgroundColor: statusTintSoft}]} />

      <View
        style={[
          styles.shell,
          isCompact && styles.shellCompact,
          isCompact && {paddingTop: spacing.md + insets.top},
        ]}>
        {!isCompact ? (
          <Sidebar
            language={language}
            onToggleLanguage={() => setLanguage(current => (current === 'en' ? 'fa' : 'en'))}
          />
        ) : null}

        <ScrollView
          style={styles.contentScroll}
          contentContainerStyle={[
            styles.content,
            isCompact && styles.contentCompact,
          ]}>
          {isCompact ? (
            <View style={styles.mobileTopBar}>
              <View style={styles.mobileTopCopy}>
                <View style={styles.mobileTitleRow}>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel={t('languageToggle')}
                    onPress={() => setLanguage(current => (current === 'en' ? 'fa' : 'en'))}
                    style={styles.languageButton}>
                    <Text style={styles.languageFlag}>{isPersian ? '🇮🇷' : '🇬🇧'}</Text>
                  </Pressable>
                  <Text style={[styles.mobileTitle, textDirectionStyle]}>V2DEX</Text>
                </View>
                <Text style={[styles.mobileMeta, textDirectionStyle]}>
                  {activeProfile?.title ?? t('noConfigSelected')}
                </Text>
              </View>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={t('importProfile')}
                onPress={() => setImportDialogOpen(true)}
                style={[styles.addButton, {borderColor: statusBorder, backgroundColor: statusTint}]}>
                <Text style={styles.addButtonText}>+</Text>
              </Pressable>
            </View>
          ) : null}

          <View style={[styles.heroRow, isCompact && styles.heroRowCompact]}>
            <GlassCard>
              <View style={styles.heroCard}>
                <View style={[styles.heroHeader, isCompact && styles.heroHeaderCompact]}>
                  <View style={[styles.heroHeaderMain, isCompact && styles.heroHeaderMainCompact]}>
                    <Text style={[styles.eyebrow, textDirectionStyle, {color: statusColor}]}>{t('tunnelState')}</Text>
                    <View style={[styles.heroTitleRow, isPersian && styles.heroTitleRowRtl]}>
                      <Text style={[styles.heroTitle, isCompact && styles.heroTitleCompact, {color: statusColor}]}>
                        {tunnel.connecting ? t('connecting') : tunnel.connected ? t('connected') : t('disconnected')}
                      </Text>
                      {tunnel.connected && tunnel.exitCountryCode ? (
                        <Text
                          accessibilityLabel={tunnel.exitCountry ?? tunnel.exitCountryCode}
                          style={[styles.exitFlag, isCompact && styles.exitFlagCompact]}>
                          {countryCodeToFlag(tunnel.exitCountryCode)}
                        </Text>
                      ) : null}
                    </View>
                    <Text style={[styles.heroSubtitle, isCompact && styles.heroSubtitleCompact, textDirectionStyle]}>
                      {activeNode?.name ?? t('noNodeSelected')} · {tunnel.mode === 'full' ? t('systemProxy') : t('perAppProxy')}
                    </Text>
                  </View>

                  {!isCompact ? (
                    <Pressable onPress={() => void refreshPing()} style={styles.heroPingCard}>
                      <Text style={[styles.sectionTitle, textDirectionStyle]}>{t('connectionPing')}</Text>
                      <Text style={[styles.heroPingValue, pingColorStyle(tunnel.pingMs)]}>
                        {typeof tunnel.pingMs === 'number' ? `${tunnel.pingMs} ms` : t('tapToTest')}
                      </Text>
                      <Text style={[styles.heroPingMeta, textDirectionStyle]}>
                        {tunnel.connected
                          ? 'www.youtube.com'
                          : `${activeNode?.server ?? t('noServer')}:${activeNode?.port ?? '--'}`}
                      </Text>
                    </Pressable>
                  ) : null}
                </View>

                <View style={[styles.pillRow, isCompact && styles.pillRowCompact]}>
                  {!isCompact ? (
                    <StatPill label={t('latency')} value={`${activeNode?.latencyMs ?? '--'} ms`} rtl={isPersian} />
                  ) : null}
                  <StatPill
                    label={t('trafficLeft')}
                    value={refreshingTraffic ? t('refreshing') : remainingTraffic}
                    onPress={activeProfile?.source === 'subscription' ? () => void handleRefreshTraffic() : undefined}
                    fillPercent={trafficFillPercent}
                    fullWidth={isCompact}
                    minWidth={!isCompact && isDesktop ? 210 : undefined}
                    rtl={isPersian}
                  />
                </View>

                {!isCompact ? (
                  <View style={styles.ctaRow}>
                    <Pressable
                      onPress={() => {
                        if (tunnel.connected) {
                          void disconnect();
                          return;
                        }

                        void connect();
                      }}
                      style={[styles.primaryButton, {backgroundColor: statusColor}]}>
                      <Text style={[styles.primaryButtonText, isPersian && styles.rtlButtonText]}>
                        {tunnel.connecting ? t('connectingEllipsis') : tunnel.connected ? t('disconnect') : t('connect')}
                      </Text>
                    </Pressable>

                    <Pressable
                      onPress={() => setMode(tunnel.mode === 'full' ? 'per-app' : 'full')}
                      style={styles.secondaryButton}>
                      <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>
                        {tunnel.mode === 'full' ? t('switchToPerApp') : t('switchToFullTunnel')}
                      </Text>
                    </Pressable>
                  </View>
                ) : null}

                {tunnel.lastError ? (
                  <Text style={styles.errorText}>{tunnel.lastError}</Text>
                ) : null}
              </View>
            </GlassCard>
          </View>

          <GlassCard>
            <Text style={[styles.sectionTitle, textDirectionStyle]}>{t('savedConfigs')}</Text>

            <View style={styles.ruleList}>
              {profiles.length === 0 ? (
                <Text style={[styles.metaText, textDirectionStyle]}>{t('noImportedConfig')}</Text>
              ) : (
                profiles.map(profile => (
                  <Pressable
                    key={profile.id}
                    onPress={() => selectProfile(profile.id)}
                    onLongPress={event =>
                      setContextMenu({
                        kind: 'profile',
                        profileId: profile.id,
                        x: event.nativeEvent.pageX,
                        y: event.nativeEvent.pageY,
                      })
                    }
                    onPressIn={event => {
                      if (isSecondaryClick(event.nativeEvent)) {
                        setContextMenu({
                          kind: 'profile',
                          profileId: profile.id,
                          x: event.nativeEvent.pageX,
                          y: event.nativeEvent.pageY,
                        });
                        return;
                      }
                    }}
                    style={[
                      styles.profileRow,
                      activeProfile?.id === profile.id && styles.profileRowActive,
                      activeProfile?.id === profile.id && {
                        borderColor: statusBorder,
                        backgroundColor: statusTintSoft,
                      },
                    ]}>
                    <View style={styles.profileMeta}>
                      <Text style={[styles.ruleTitle, textDirectionStyle]}>{profile.title}</Text>
                      <Text style={[styles.ruleMeta, textDirectionStyle]}>
                        {translateProfileSource(profile.source, language)} · {profile.nodes.length} {profile.nodes.length > 1 ? t('nodes') : t('node')}
                      </Text>
                    </View>
                    <Text style={styles.profileStamp}>
                      {formatProfileStamp(
                        profile.id,
                        profile.updatedAt,
                        profilePingResults,
                        profile.nodes[0]?.latencyMs,
                      )}
                    </Text>
                  </Pressable>
                ))
              )}
            </View>

            {activeProfile ? (
              <View style={styles.profileActionRow}>
                <Pressable
                  onPress={() => void handlePingAllProfiles()}
                  style={[styles.secondaryButtonCompact, styles.profilePingButton]}>
                  <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>
                    {pingingAll ? t('pingingAll') : t('pingAll')}
                  </Text>
                </Pressable>
              </View>
            ) : null}
          </GlassCard>

          <GlassCard>
            <View style={[styles.proxyInfoRow, isCompact && styles.proxyInfoRowCompact]}>
              <View style={styles.proxyInfoCopy}>
                <Text numberOfLines={1} style={[styles.sectionTitle, styles.proxyTitle, textDirectionStyle]}>
                  {t('localSocksProxy')}
                </Text>
                <Text
                  numberOfLines={1}
                  ellipsizeMode="clip"
                  adjustsFontSizeToFit
                  minimumFontScale={0.72}
                  style={[styles.proxyAddress, textDirectionStyle]}>
                  {socksHost}:{socksPort}
                </Text>
              </View>
              <View style={styles.proxyActionStack}>
                <Pressable onPress={() => void handleCopyLocalProxyCommand()} style={styles.proxyCopyButton}>
                  <Text style={[styles.proxyCopyText, isPersian && styles.rtlButtonText]}>{t('copy')}</Text>
                </Pressable>
                <View style={[styles.proxyStatusPill, tunnel.connected && styles.proxyStatusPillActive]}>
                  <Text style={[styles.proxyStatusText, tunnel.connected && styles.proxyStatusTextActive, isPersian && styles.rtlButtonText]}>
                    {tunnel.connected ? t('active') : t('standby')}
                  </Text>
                </View>
              </View>
            </View>
          </GlassCard>

          <GlassCard
            style={tunnel.mode === 'per-app' ? styles.appRoutingCardActive : undefined}
            innerStyle={tunnel.mode === 'per-app' ? styles.appRoutingCardInnerActive : undefined}>
            <View style={[styles.sectionHeaderRow, isCompact && styles.sectionHeaderRowCompact]}>
              <View style={[styles.sectionHeaderCopy, isCompact && styles.sectionHeaderCopyCompact]}>
                <View style={[styles.sectionTitleToggleRow, isPersian && styles.sectionTitleToggleRowRtl]}>
                  <Text style={[styles.sectionTitle, textDirectionStyle]}>{t('appRoutingPreview')}</Text>
                  <View style={[styles.routingModeToggle, tunnel.mode === 'per-app' && styles.routingModeToggleActive]}>
                    <Text
                      style={[
                        styles.routingModeLabel,
                        tunnel.mode === 'per-app' && styles.routingModeLabelActive,
                        isPersian && styles.rtlButtonText,
                      ]}>
                      {tunnel.mode === 'per-app' ? t('perAppMode') : t('fullTunnelMode')}
                    </Text>
                    <Switch
                      value={tunnel.mode === 'per-app'}
                      onValueChange={value => void handleRoutingModeToggle(value)}
                      trackColor={{false: 'rgba(255,255,255,0.20)', true: 'rgba(57,217,138,0.45)'}}
                      thumbColor={tunnel.mode === 'per-app' ? colors.success : colors.textSecondary}
                    />
                  </View>
                </View>
                {!isCompact ? (
                  <Text style={[styles.sectionLead, textDirectionStyle]}>
                    {t('appRoutingLead')}
                  </Text>
                ) : null}
              </View>
              <Pressable onPress={() => void handleDiscoverApps()} style={[styles.secondaryButtonCompact, isCompact && styles.actionButtonCompact]}>
                <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>
                  {discoveringApps ? t('discoveringApps') : t('discoverApps')}
                </Text>
              </Pressable>
            </View>

            <TextInput
              placeholder={t('searchApps')}
              placeholderTextColor="rgba(244,247,249,0.42)"
              style={[styles.appSearchInput, textDirectionStyle]}
              value={appSearchQuery}
              onChangeText={setAppSearchQuery}
              autoCapitalize="none"
              autoCorrect={false}
              clearButtonMode="while-editing"
            />

            <View style={styles.ruleList}>
              {filteredAppRules.length === 0 ? (
                <Text style={[styles.emptySearchText, textDirectionStyle]}>{t('noMatchingApps')}</Text>
              ) : filteredAppRules.map(rule => (
                <View key={rule.bundleId} style={styles.ruleRow}>
                  <View>
                    <Text style={[styles.ruleTitle, textDirectionStyle]}>{rule.name}</Text>
                    <Text style={[styles.ruleMeta, textDirectionStyle]}>{rule.processName}</Text>
                  </View>
                  <Switch value={rule.enabled} onValueChange={() => void handleAppRuleToggle(rule.bundleId)} />
                </View>
              ))}
            </View>
          </GlassCard>
        </ScrollView>

        {isCompact ? (
          <View style={[styles.fixedActionBar, {marginBottom: insets.bottom}]}>
            <View
              accessibilityRole="button"
              accessibilityLabel={tunnel.connected ? t('disconnect') : t('connect')}
              onStartShouldSetResponder={() => true}
              onTouchStart={() => {
                if (tunnel.connected) {
                  void disconnect();
                  return;
                }

                void connect();
              }}
              style={[styles.fixedConnectButton, {backgroundColor: statusColor}]}>
              <Text style={[styles.primaryButtonText, isPersian && styles.rtlButtonText]}>
                {tunnel.connecting ? t('connecting') : tunnel.connected ? t('disconnect') : t('connect')}
              </Text>
            </View>

            <View
              accessibilityRole="button"
              accessibilityLabel={mobilePingLabel(tunnel.pingMs, tunnel.pingTimedOut)}
              onStartShouldSetResponder={() => true}
              onTouchStart={() => void refreshPing()}
              style={styles.fixedPingButton}>
              <Text style={[styles.fixedPingText, mobilePingColorStyle(tunnel.pingMs, tunnel.pingTimedOut)]}>
                {mobilePingLabel(tunnel.pingMs, tunnel.pingTimedOut)}
              </Text>
            </View>
          </View>
        ) : null}

        {contextMenu ? (
          <View style={styles.contextMenuLayer} pointerEvents="box-none">
            <Pressable style={styles.contextMenuDismiss} onPress={() => setContextMenu(null)} />
            <View
              style={[
                styles.contextMenu,
                {
                  left: Math.min(Math.max(contextMenu.x - 220, spacing.md), Math.max(width - 220 - spacing.md, spacing.md)),
                  top: contextMenu.y - 12,
                },
              ]}>
              {contextMenu.kind === 'profile' ? (
                <>
                  <Pressable
                    style={styles.contextMenuItem}
                    onPress={() => void handleProfileMenuAction('rename', contextMenu.profileId)}>
                    <Text style={[styles.contextMenuText, textDirectionStyle]}>{t('editName')}</Text>
                  </Pressable>
                  <Pressable
                    style={styles.contextMenuItem}
                    onPress={() => void handleProfileMenuAction('copy', contextMenu.profileId)}>
                    <Text style={[styles.contextMenuText, textDirectionStyle]}>{t('copy')}</Text>
                  </Pressable>
                  <Pressable
                    style={[styles.contextMenuItem, styles.contextMenuItemDanger]}
                    onPress={() => void handleProfileMenuAction('delete', contextMenu.profileId)}>
                    <Text style={[styles.contextMenuText, textDirectionStyle, styles.contextMenuTextDanger]}>{t('deleteConfig')}</Text>
                  </Pressable>
                </>
              ) : (
                <Pressable
                  style={[styles.contextMenuItem, styles.contextMenuItemDanger]}
                  onPress={() => {
                    setContextMenu(null);
                    setManualDialogOpen(true);
                  }}>
                  <Text style={[styles.contextMenuText, textDirectionStyle]}>{t('manualConfig')}</Text>
                </Pressable>
              )}
            </View>
          </View>
        ) : null}

        <Modal transparent visible={renameDialog !== null} animationType="fade" onRequestClose={() => setRenameDialog(null)}>
          <View style={styles.modalLayer}>
            <Pressable style={styles.modalBackdrop} onPress={() => setRenameDialog(null)} />
            <View style={styles.modalCard}>
              <Text style={[styles.modalTitle, textDirectionStyle]}>{t('editConfigName')}</Text>
              <TextInput
                placeholder={t('newName')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={renameDialog?.value ?? ''}
                onChangeText={value =>
                  setRenameDialog(current => (current ? {...current, value} : current))
                }
              />
              <View style={styles.modalActions}>
                <Pressable onPress={() => setRenameDialog(null)} style={styles.secondaryButtonCompact}>
                  <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>{t('cancel')}</Text>
                </Pressable>
                <Pressable onPress={() => void handleRenameSubmit()} style={styles.primaryButton}>
                  <Text style={[styles.primaryButtonText, isPersian && styles.rtlButtonText]}>{t('save')}</Text>
                </Pressable>
              </View>
            </View>
          </View>
        </Modal>

        <Modal transparent visible={importDialogOpen} animationType="fade" onRequestClose={() => setImportDialogOpen(false)}>
          <View style={styles.modalLayer}>
            <Pressable style={styles.modalBackdrop} onPress={() => setImportDialogOpen(false)} />
            <View style={styles.modalCard}>
              <Text style={[styles.modalTitle, textDirectionStyle]}>{t('importProfile')}</Text>
              <TextInput
                placeholder={t('importPlaceholder')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={importDraft}
                onChangeText={setImportDraft}
                autoCapitalize="none"
                multiline
              />
              <View style={styles.importOptionRow}>
                <Pressable
                  onPress={() => {
                    setImportDialogOpen(false);
                    setManualDialogOpen(true);
                  }}
                  style={styles.importOptionButton}>
                  <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>{t('manual')}</Text>
                </Pressable>
                <Pressable onPress={() => void handleClipboardImport()} style={styles.importOptionButton}>
                  <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>{t('clipboard')}</Text>
                </Pressable>
                <Pressable
                  accessibilityLabel={t('scanQr')}
                  onPress={() => void handleQrCameraImport()}
                  style={styles.importIconButton}>
                  <Image
                    source={require('../assets/qrcode_white.png')}
                    style={styles.importIconImage}
                    resizeMode="contain"
                  />
                </Pressable>
              </View>
              <Pressable onPress={() => void handleImportSubmit()} style={styles.importSubmitButton}>
                <Text style={[styles.primaryButtonText, isPersian && styles.rtlButtonText]}>{t('import')}</Text>
              </Pressable>
            </View>
          </View>
        </Modal>

        <Modal transparent visible={manualDialogOpen} animationType="fade" onRequestClose={closeManualDialog}>
          <View style={styles.modalLayer}>
            <Pressable style={styles.modalBackdrop} onPress={closeManualDialog} />
            <View style={styles.modalCard}>
              <Text style={[styles.modalTitle, textDirectionStyle]}>{t('manualConfig')}</Text>
              <View style={styles.protocolRow}>
                {(['http', 'https', 'socks5'] as const).map(protocol => (
                  <Pressable
                    key={protocol}
                    onPress={() => setManualProtocol(protocol)}
                    style={[
                      styles.protocolButton,
                      manualProtocol === protocol && styles.protocolButtonActive,
                      manualProtocol === protocol && {
                        borderColor: statusColor,
                        backgroundColor: statusTint,
                      },
                    ]}>
                    <Text style={styles.protocolButtonText}>{protocol.toUpperCase()}</Text>
                  </Pressable>
                ))}
              </View>
              <TextInput
                placeholder={t('displayNameOptional')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={manualName}
                onChangeText={setManualName}
              />
              <TextInput
                placeholder={t('address')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={manualHost}
                onChangeText={setManualHost}
                autoCapitalize="none"
              />
              <TextInput
                placeholder={t('port')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={manualPort}
                onChangeText={setManualPort}
                keyboardType="number-pad"
              />
              <TextInput
                placeholder={t('usernameOptional')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={manualUsername}
                onChangeText={setManualUsername}
                autoCapitalize="none"
              />
              <TextInput
                placeholder={t('passwordOptional')}
                placeholderTextColor="rgba(244,247,249,0.40)"
                style={[styles.input, textDirectionStyle]}
                value={manualPassword}
                onChangeText={setManualPassword}
                autoCapitalize="none"
                secureTextEntry
              />
              <View style={styles.modalActions}>
                <Pressable onPress={closeManualDialog} style={styles.secondaryButtonCompact}>
                  <Text style={[styles.secondaryButtonText, isPersian && styles.rtlButtonText]}>{t('cancel')}</Text>
                </Pressable>
                <Pressable onPress={() => void handleManualImport()} style={styles.primaryButton}>
                  <Text style={[styles.primaryButtonText, isPersian && styles.rtlButtonText]}>{t('addConfig')}</Text>
                </Pressable>
              </View>
            </View>
          </View>
        </Modal>
      </View>
    </AppGradient>
  );
}

const styles = StyleSheet.create({
  background: {
    flex: 1
  },
  glowA: {
    position: 'absolute',
    width: 520,
    height: 520,
    borderRadius: 260,
    backgroundColor: 'rgba(108, 184, 255, 0.14)',
    top: -120,
    right: -80
  },
  glowB: {
    position: 'absolute',
    width: 440,
    height: 440,
    borderRadius: 220,
    backgroundColor: 'rgba(111, 232, 197, 0.10)',
    bottom: -80,
    left: -120
  },
  shell: {
    flex: 1,
    flexDirection: 'row',
    padding: spacing.xl,
    gap: spacing.lg,
    backgroundColor: 'rgba(6, 10, 16, 0.96)'
  },
  shellCompact: {
    flexDirection: 'column',
    padding: spacing.md,
    gap: spacing.md,
  },
  contentScroll: {
    flex: 1,
    minWidth: 0
  },
  content: {
    flexGrow: 1,
    gap: spacing.lg,
    paddingBottom: spacing.xxl
  },
  contentCompact: {
    paddingBottom: spacing.md,
  },
  mobileTopBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
  },
  mobileTopCopy: {
    flex: 1,
    minWidth: 0,
  },
  mobileTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  languageButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
  },
  languageFlag: {
    fontSize: 18,
  },
  mobileTitle: {
    color: colors.textPrimary,
    fontSize: 22,
    fontWeight: '800',
    letterSpacing: 1.4,
  },
  mobileMeta: {
    color: colors.textSecondary,
    marginTop: 3,
    fontSize: 13,
  },
  addButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  addButtonText: {
    color: colors.textPrimary,
    fontSize: 30,
    lineHeight: 34,
    fontWeight: '500',
  },
  heroRow: {
    minHeight: 280
  },
  heroRowCompact: {
    minHeight: 0,
  },
  heroCard: {
    gap: spacing.md
  },
  heroHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: spacing.lg,
  },
  heroHeaderCompact: {
    flexDirection: 'column',
    gap: spacing.md,
  },
  heroHeaderMain: {
    flex: 1,
    minWidth: 0,
  },
  heroHeaderMainCompact: {
    flex: 0,
    width: '100%',
  },
  eyebrow: {
    color: colors.accent,
    textTransform: 'uppercase',
    letterSpacing: 1.4,
    fontSize: 11,
    fontWeight: '700'
  },
  heroTitle: {
    color: colors.textPrimary,
    fontSize: 52,
    fontWeight: '800'
  },
  heroTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  heroTitleRowRtl: {
    flexDirection: 'row-reverse',
    justifyContent: 'flex-end',
  },
  heroTitleCompact: {
    fontSize: 34,
  },
  exitFlag: {
    fontSize: 36,
    lineHeight: 44,
  },
  exitFlagCompact: {
    fontSize: 28,
    lineHeight: 34,
  },
  heroSubtitle: {
    color: colors.textSecondary,
    fontSize: 16
  },
  heroSubtitleCompact: {
    fontSize: 14,
  },
  heroPingCard: {
    minWidth: 220,
    padding: spacing.md,
    borderRadius: radii.lg,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    backgroundColor: 'rgba(255,255,255,0.04)',
    alignItems: 'flex-end',
  },
  heroPingCardCompact: {
    minWidth: 0,
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 64,
  },
  heroPingValue: {
    marginTop: spacing.xs,
    fontSize: 28,
    fontWeight: '800',
  },
  heroPingMeta: {
    marginTop: spacing.xs,
    color: colors.textSecondary,
    fontSize: 12,
  },
  pillRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
    marginTop: spacing.sm
  },
  pillRowCompact: {
    flexDirection: 'column',
    flexWrap: 'nowrap',
  },
  ctaRow: {
    flexDirection: 'row',
    gap: spacing.md,
    marginTop: spacing.sm
  },
  ctaRowCompact: {
    flexDirection: 'column',
    gap: spacing.sm,
  },
  actionButtonCompact: {
    width: '100%',
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: colors.accent,
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 48,
  },
  primaryButtonText: {
    color: '#041118',
    fontWeight: '800',
    fontSize: 15,
    lineHeight: 20,
    textAlign: 'center',
    includeFontPadding: false,
    textAlignVertical: 'center',
  },
  secondaryButton: {
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 48,
  },
  secondaryButtonText: {
    color: colors.textPrimary,
    fontWeight: '700',
    fontSize: 15,
    lineHeight: 20,
    textAlign: 'center',
    includeFontPadding: false,
    textAlignVertical: 'center',
  },
  secondaryButtonCompact: {
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 44,
  },
  secondaryButtonDanger: {
    borderColor: 'rgba(255,93,93,0.35)',
  },
  grid: {
    flexDirection: 'row',
    gap: spacing.lg,
    flexWrap: 'wrap'
  },
  sectionTitle: {
    color: colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1.2,
    fontSize: 11,
    fontWeight: '700'
  },
  sectionTitleToggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
  },
  sectionTitleToggleRowRtl: {
    flexDirection: 'row-reverse',
  },
  routingModeToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    paddingLeft: 12,
    paddingRight: 4,
    paddingVertical: 4,
    minHeight: 42,
  },
  routingModeToggleActive: {
    borderColor: 'rgba(57,217,138,0.48)',
    backgroundColor: 'rgba(57,217,138,0.13)',
  },
  routingModeLabel: {
    color: colors.textSecondary,
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '800',
    textAlign: 'center',
    includeFontPadding: false,
    textAlignVertical: 'center',
  },
  routingModeLabelActive: {
    color: colors.success,
  },
  appRoutingCardActive: {
    borderColor: 'rgba(57,217,138,0.55)',
  },
  appRoutingCardInnerActive: {
    backgroundColor: 'rgba(57,217,138,0.10)',
  },
  sectionLead: {
    color: colors.textPrimary,
    fontSize: 24,
    fontWeight: '700',
    marginTop: spacing.sm
  },
  metaText: {
    color: colors.textSecondary,
    marginTop: 8,
    fontSize: 14
  },
  input: {
    marginTop: spacing.md,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: 'rgba(255,255,255,0.06)',
    color: colors.textPrimary,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 14
  },
  appSearchInput: {
    marginTop: spacing.md,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.16)',
    backgroundColor: 'rgba(255,255,255,0.08)',
    color: colors.textPrimary,
    paddingHorizontal: 16,
    paddingVertical: 12,
    minHeight: 46,
    fontSize: 14,
  },
  emptySearchText: {
    color: colors.textSecondary,
    fontSize: 14,
    paddingVertical: spacing.sm,
  },
  ruleList: {
    marginTop: spacing.lg,
    gap: spacing.md
  },
  ruleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)'
  },
  profileRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    backgroundColor: 'rgba(255,255,255,0.03)'
  },
  profileRowActive: {
    borderColor: 'rgba(111, 232, 197, 0.40)',
    backgroundColor: 'rgba(111, 232, 197, 0.08)'
  },
  profileMeta: {
    flex: 1,
    paddingRight: spacing.md
  },
  profileStamp: {
    color: colors.textSecondary,
    fontSize: 12
  },
  profileActionRow: {
    marginTop: spacing.lg,
    flexDirection: 'row',
    gap: spacing.md,
  },
  profilePingButton: {
    flex: 1,
  },
  proxyInfoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
  },
  proxyInfoRowCompact: {
    alignItems: 'flex-start',
  },
  proxyInfoCopy: {
    flex: 1,
    minWidth: 0,
  },
  proxyTitle: {
    flexShrink: 1,
  },
  proxyAddress: {
    color: colors.textPrimary,
    fontSize: 18,
    fontWeight: '800',
    lineHeight: 22,
    marginTop: spacing.sm,
    flexShrink: 1,
    includeFontPadding: false,
  },
  proxyStatusPill: {
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    paddingHorizontal: 12,
    paddingVertical: 8,
    minHeight: 34,
    alignItems: 'center',
    justifyContent: 'center',
  },
  proxyStatusPillActive: {
    borderColor: 'rgba(57,217,138,0.45)',
    backgroundColor: 'rgba(57,217,138,0.12)',
  },
  proxyActionStack: {
    alignItems: 'flex-end',
    gap: spacing.sm,
  },
  proxyCopyButton: {
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    paddingHorizontal: 14,
    paddingVertical: 9,
    minWidth: 72,
    minHeight: 38,
    alignItems: 'center',
    justifyContent: 'center',
  },
  proxyCopyText: {
    color: colors.textPrimary,
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '800',
    textAlign: 'center',
    includeFontPadding: false,
    textAlignVertical: 'center',
  },
  proxyStatusText: {
    color: colors.textSecondary,
    fontSize: 12,
    lineHeight: 16,
    fontWeight: '800',
    textAlign: 'center',
    includeFontPadding: false,
    textAlignVertical: 'center',
  },
  proxyStatusTextActive: {
    color: colors.success,
  },
  ruleTitle: {
    color: colors.textPrimary,
    fontSize: 16,
    fontWeight: '600'
  },
  ruleMeta: {
    color: colors.textSecondary,
    marginTop: 4
  },
  errorText: {
    color: colors.warning,
    marginTop: spacing.sm,
    fontSize: 13,
    fontWeight: '600'
  },
  contextMenuLayer: {
    ...StyleSheet.absoluteFillObject
  },
  contextMenuDismiss: {
    ...StyleSheet.absoluteFillObject
  },
  contextMenu: {
    position: 'absolute',
    width: 220,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: 'rgba(8, 15, 24, 0.98)',
    overflow: 'hidden'
  },
  contextMenuItem: {
    paddingHorizontal: spacing.md,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)'
  },
  contextMenuItemDanger: {
    borderBottomWidth: 0
  },
  contextMenuText: {
    color: colors.textPrimary,
    fontSize: 14,
    fontWeight: '600'
  },
  contextMenuTextDanger: {
    color: colors.danger
  },
  sectionHeaderRow: {
    flexDirection: 'row',
    gap: spacing.md,
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  sectionHeaderRowCompact: {
    flexDirection: 'column',
  },
  sectionHeaderCopy: {
    flex: 1,
    minWidth: 0,
  },
  sectionHeaderCopyCompact: {
    width: '100%',
  },
  modalLayer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.xl,
  },
  modalBackdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.45)',
  },
  modalCard: {
    width: '100%',
    maxWidth: 520,
    borderRadius: radii.lg,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: 'rgba(8, 15, 24, 0.98)',
    padding: spacing.lg,
  },
  modalTitle: {
    color: colors.textPrimary,
    fontSize: 24,
    fontWeight: '800',
  },
  modalActions: {
    marginTop: spacing.lg,
    flexDirection: 'row',
    justifyContent: 'flex-end',
    flexWrap: 'wrap',
    gap: spacing.md,
  },
  importOptionRow: {
    marginTop: spacing.lg,
    flexDirection: 'row',
    gap: spacing.sm,
    alignItems: 'center',
  },
  importOptionButton: {
    flex: 1,
    minWidth: 0,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 46,
  },
  importIconButton: {
    width: 48,
    height: 46,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    alignItems: 'center',
    justifyContent: 'center',
  },
  importIconImage: {
    width: 26,
    height: 26,
  },
  importSubmitButton: {
    width: '100%',
    marginTop: spacing.md,
    backgroundColor: colors.accent,
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 48,
  },
  protocolRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginTop: spacing.md,
  },
  protocolButton: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
  },
  protocolButtonActive: {
    borderColor: colors.accent,
    backgroundColor: 'rgba(111, 232, 197, 0.14)',
  },
  protocolButtonText: {
    color: colors.textPrimary,
    fontWeight: '700',
    fontSize: 13,
  },
  pingCardButton: {
    minWidth: 280
  },
  pingValue: {
    marginTop: spacing.sm,
    fontSize: 34,
    fontWeight: '800'
  },
  fixedActionBar: {
    flexDirection: 'row',
    gap: spacing.sm,
    padding: spacing.sm,
    borderRadius: radii.lg,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: 'rgba(8, 15, 24, 0.96)',
    flexShrink: 0,
  },
  fixedConnectButton: {
    flex: 1,
    minHeight: 50,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.sm,
  },
  fixedPingButton: {
    flex: 1,
    minHeight: 50,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.sm,
  },
  fixedPingText: {
    color: colors.textPrimary,
    fontSize: 17,
    fontWeight: '800',
    lineHeight: 22,
    includeFontPadding: false,
    textAlign: 'center',
    textAlignVertical: 'center',
  },
  centerText: {
    textAlign: 'center',
  },
  rtlText: {
    writingDirection: 'rtl',
    textAlign: 'right',
    textTransform: 'none',
    letterSpacing: 0,
  },
  rtlButtonText: {
    writingDirection: 'rtl',
    textAlign: 'center',
    textTransform: 'none',
    letterSpacing: 0,
  },
  ltrText: {
    writingDirection: 'ltr',
    textAlign: 'left',
  },
});

function withAlpha(hex: string, alpha: number) {
  const normalized = hex.replace('#', '');
  if (normalized.length !== 6) {
    return hex;
  }

  const red = parseInt(normalized.slice(0, 2), 16);
  const green = parseInt(normalized.slice(2, 4), 16);
  const blue = parseInt(normalized.slice(4, 6), 16);
  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}

function isSecondaryClick(event: unknown) {
  return (
    typeof event === 'object' &&
    event !== null &&
    'button' in event &&
    (event as {button?: unknown}).button === 2
  );
}

function pingColorStyle(pingMs?: number) {
  if (typeof pingMs !== 'number') {
    return {color: colors.textPrimary};
  }

  if (pingMs < 150) {
    return {color: '#39d98a'};
  }

  if (pingMs <= 700) {
    return {color: '#ff9f43'};
  }

  return {color: '#ff5d5d'};
}

function mobilePingLabel(pingMs?: number, timedOut?: boolean) {
  if (timedOut) {
    return 'TO';
  }

  if (typeof pingMs === 'number') {
    return `${pingMs}ms`;
  }

  return 'ping';
}

function mobilePingColorStyle(pingMs?: number, timedOut?: boolean) {
  if (timedOut) {
    return {color: colors.danger};
  }

  return pingColorStyle(pingMs);
}

function countryCodeToFlag(countryCode: string) {
  const normalized = countryCode.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(normalized)) {
    return normalized;
  }

  return Array.from(normalized)
    .map(char => String.fromCodePoint(0x1f1e6 + char.charCodeAt(0) - 65))
    .join('');
}

function formatBytes(value: number) {
  if (value <= 0) {
    return '0 B';
  }

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let unitIndex = 0;
  let size = value;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  const digits = unitIndex >= 3 ? 2 : unitIndex >= 2 ? 1 : 0;
  return `${size.toFixed(digits)} ${units[unitIndex]}`;
}

function parseRemainingTrafficLabel(value?: string) {
  const match = value?.match(/(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB|B)/i);
  if (!match) {
    return undefined;
  }

  const amount = Number(match[1]);
  const unit = match[2].toUpperCase();
  if (!Number.isFinite(amount)) {
    return undefined;
  }

  return `${amount.toFixed(unit === 'B' || unit === 'KB' ? 0 : 2)} ${unit}`;
}

function formatProfileStamp(
  profileId: string,
  updatedAt: string,
  pingResults: Record<string, number | 'TO'> | null,
  latencyMs?: number,
) {
  const ping = pingResults?.[profileId];
  if (typeof ping === 'number') {
    return `${ping}ms`;
  }
  if (ping === 'TO') {
    return 'TO';
  }
  if (typeof latencyMs === 'number') {
    return `${latencyMs}ms`;
  }

  return new Date(updatedAt).toLocaleDateString();
}

function getTrafficFillPercent(profile?: {
  trafficTotalGB?: number;
  trafficUsedGB?: number;
  usage?: {
    totalBytes?: number;
    usedBytes?: number;
    remainingBytes?: number;
  };
}) {
  const totalBytes =
    typeof profile?.usage?.totalBytes === 'number'
      ? profile.usage.totalBytes
      : typeof profile?.trafficTotalGB === 'number'
        ? profile.trafficTotalGB * 1024 ** 3
        : undefined;
  const remainingBytes =
    typeof profile?.usage?.remainingBytes === 'number'
      ? profile.usage.remainingBytes
      : typeof totalBytes === 'number' && typeof profile?.usage?.usedBytes === 'number'
        ? totalBytes - profile.usage.usedBytes
        : typeof profile?.trafficTotalGB === 'number' && typeof profile?.trafficUsedGB === 'number'
          ? (profile.trafficTotalGB - profile.trafficUsedGB) * 1024 ** 3
          : undefined;

  if (
    typeof totalBytes !== 'number' ||
    typeof remainingBytes !== 'number' ||
    !Number.isFinite(totalBytes) ||
    !Number.isFinite(remainingBytes) ||
    totalBytes <= 0
  ) {
    return undefined;
  }

  return remainingBytes / totalBytes;
}

const translations = {
  en: {
    addConfig: 'Add Config',
    address: 'Address',
    addressRequired: 'Address is required.',
    appRoutingLead: 'Full tunnel uses the local Xray runtime. Per-app controls are prepared for Android app selection.',
    appRoutingPreview: 'App routing preview',
    active: 'Active',
    cancel: 'Cancel',
    clipboard: 'Clipboard',
    configLabel: 'config',
    configLinkCopied: 'Config link copied.',
    connect: 'Connect',
    connected: 'Connected',
    connecting: 'Connecting',
    connectingEllipsis: 'Connecting...',
    connectionPing: 'Connection Ping',
    copied: 'Copied',
    copy: 'Copy',
    autosshCopied: 'autossh command copied.',
    delete: 'Delete',
    deleteConfig: 'Delete Config',
    disconnect: 'Disconnect',
    disconnected: 'Disconnected',
    discoverApps: 'Discover Apps',
    discoveringApps: 'Discovering...',
    displayNameOptional: 'Display name (optional)',
    editConfigName: 'Edit Config Name',
    editName: 'Edit Name',
    fullTunnelMode: 'Full',
    import: 'Import',
    importPlaceholder: 'vless://... or https://subscription...',
    importProfile: 'Import profile',
    languageToggle: 'Toggle language',
    latency: 'Latency',
    localSocksProxy: 'Local SOCKS proxy',
    manual: 'Manual',
    manualConfig: 'Manual Config',
    nameCannotBeEmpty: 'Name cannot be empty.',
    newName: 'New name',
    noConfigSelected: 'No config selected',
    noImportedConfig: 'No imported config yet.',
    noMatchingApps: 'No matching apps found.',
    noNodeSelected: 'No node selected',
    noServer: 'No server',
    node: 'node',
    nodes: 'nodes',
    operationFailed: 'Operation Failed',
    passwordOptional: 'Password (optional)',
    perAppMode: 'Per-app',
    perAppProxy: 'Per-app proxy',
    pingAll: 'Ping All',
    pingingAll: 'Pinging...',
    port: 'Port',
    portRange: 'Port must be between 1 and 65535.',
    refreshing: 'Refreshing...',
    save: 'Save',
    savedConfigs: 'Saved configs',
    savedConfigsLead: 'Imported configs stay available after reopening the app.',
    scanQr: 'Scan QR',
    searchApps: 'Search apps',
    serverConnection: 'Server Connection',
    standby: 'Standby',
    chooseQrImage: 'Choose QR image',
    switchToFullTunnel: 'Switch to Full Tunnel',
    switchToPerApp: 'Switch to Per-App',
    systemProxy: 'System proxy',
    tapToTest: 'Tap To Test',
    testConnectionToServer: 'Test Connection To Server',
    testDownload: 'Test Download',
    testServer: 'Test Server',
    trafficLeft: 'Traffic left',
    tunnelState: 'Tunnel state',
    unknownError: 'Unknown error.',
    usernameOptional: 'Username (optional)',
  },
  fa: {
    addConfig: 'افزودن کانفیگ',
    address: 'آدرس',
    addressRequired: 'آدرس الزامی است.',
    appRoutingLead: 'فول تانل از هسته محلی Xray استفاده می‌کند. کنترل‌های پر اپ برای انتخاب اپ‌های اندروید آماده شده‌اند.',
    appRoutingPreview: 'پیش‌نمایش روتینگ اپ‌ها',
    active: 'فعال',
    cancel: 'لغو',
    clipboard: 'کلیپ‌بورد',
    configLabel: 'کانفیگ',
    configLinkCopied: 'لینک کانفیگ کپی شد.',
    connect: 'اتصال',
    connected: 'وصل',
    connecting: 'در حال اتصال',
    connectingEllipsis: 'در حال اتصال...',
    connectionPing: 'پینگ اتصال',
    copied: 'کپی شد',
    copy: 'کپی',
    autosshCopied: 'دستور autossh کپی شد.',
    delete: 'حذف',
    deleteConfig: 'حذف کانفیگ',
    disconnect: 'قطع اتصال',
    disconnected: 'قطع',
    discoverApps: 'پیدا کردن اپ‌ها',
    discoveringApps: 'در حال پیدا کردن...',
    displayNameOptional: 'نام نمایشی (اختیاری)',
    editConfigName: 'ویرایش نام کانفیگ',
    editName: 'ویرایش نام',
    fullTunnelMode: 'فول',
    import: 'ایمپورت',
    importPlaceholder: 'vless://... یا https://subscription...',
    importProfile: 'ایمپورت پروفایل',
    languageToggle: 'تغییر زبان',
    latency: 'تاخیر',
    localSocksProxy: 'پراکسی SOCKS محلی',
    manual: 'دستی',
    manualConfig: 'کانفیگ دستی',
    nameCannotBeEmpty: 'نام نمی‌تواند خالی باشد.',
    newName: 'نام جدید',
    noConfigSelected: 'هیچ کانفیگی انتخاب نشده',
    noImportedConfig: 'هنوز کانفیگی ایمپورت نشده.',
    noMatchingApps: 'اپی با این جستجو پیدا نشد.',
    noNodeSelected: 'هیچ نودی انتخاب نشده',
    noServer: 'بدون سرور',
    node: 'نود',
    nodes: 'نود',
    operationFailed: 'عملیات ناموفق بود',
    passwordOptional: 'رمز عبور (اختیاری)',
    perAppMode: 'پر اپ',
    perAppProxy: 'پراکسی پر اپ',
    pingAll: 'پینگ همه',
    pingingAll: 'در حال پینگ...',
    port: 'پورت',
    portRange: 'پورت باید بین ۱ تا ۶۵۵۳۵ باشد.',
    refreshing: 'در حال بروزرسانی...',
    save: 'ذخیره',
    savedConfigs: 'کانفیگ‌های ذخیره‌شده',
    savedConfigsLead: 'کانفیگ‌های ایمپورت‌شده بعد از باز کردن دوباره اپ باقی می‌مانند.',
    scanQr: 'اسکن QR',
    searchApps: 'جستجوی اپ‌ها',
    serverConnection: 'اتصال به سرور',
    standby: 'آماده',
    chooseQrImage: 'انتخاب عکس QR',
    switchToFullTunnel: 'تغییر به فول تانل',
    switchToPerApp: 'تغییر به پر اپ',
    systemProxy: 'پراکسی سیستم',
    tapToTest: 'برای تست بزنید',
    testConnectionToServer: 'تست اتصال به سرور',
    testDownload: 'تست دانلود',
    testServer: 'تست سرور',
    trafficLeft: 'ترافیک باقی‌مانده',
    tunnelState: 'وضعیت تانل',
    unknownError: 'خطای ناشناخته.',
    usernameOptional: 'نام کاربری (اختیاری)',
  },
} as const;

type Language = keyof typeof translations;
type TranslationKey = keyof typeof translations.en;

function translateProfileSource(source: string, language: Language) {
  if (language === 'en') {
    return source;
  }

  switch (source) {
    case 'clipboard':
      return 'کلیپ‌بورد';
    case 'uri':
      return 'لینک';
    case 'subscription':
      return 'سابسکریپشن';
    case 'manual':
      return 'دستی';
    default:
      return source;
  }
}
