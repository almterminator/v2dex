import React from 'react';
import {Platform, Pressable, StyleSheet, Text, View} from 'react-native';
import {colors, radii, spacing} from '../theme/tokens';
import {useAppStore} from '../state/appStore';

const items = ['overview', 'routing', 'subscriptions', 'latency', 'settings'] as const;
export type SidebarItem = (typeof items)[number];

interface SidebarProps {
  activeItem?: SidebarItem;
  compact?: boolean;
  language?: 'en' | 'fa';
  onAddConfig?: () => void;
  onSelectItem?: (item: SidebarItem) => void;
  onToggleLanguage?: () => void;
}

export function Sidebar({
  activeItem = 'overview',
  compact = false,
  language = 'en',
  onAddConfig,
  onSelectItem,
  onToggleLanguage,
}: SidebarProps) {
  const tunnel = useAppStore(state => state.tunnel);
  const statusColor = tunnel.connecting ? colors.warning : tunnel.connected ? colors.success : colors.info;
  const statusTint = withAlpha(statusColor, 0.18);
  const isPersian = language === 'fa';
  const supportsSidebarImport = Platform.OS === 'windows';

  return (
    <View style={[styles.container, compact && styles.containerCompact]}>
      {!compact ? (
        <View>
          <View style={styles.brandRow}>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={isPersian ? 'تغییر زبان' : 'Toggle language'}
              onPress={onToggleLanguage}
              style={styles.languageButton}>
              <Text style={styles.languageFlag}>{isPersian ? '🇮🇷' : '🇬🇧'}</Text>
            </Pressable>
            <Text style={styles.brand}>V2DEX</Text>
          </View>
          <Text style={[styles.caption, isPersian && styles.rtlText]}>
            {isPersian ? 'کلاینت تانل پرسرعت' : 'Performance tunnel client'}
          </Text>
        </View>
      ) : null}

      <View style={[styles.nav, compact && styles.navCompact]}>
        {supportsSidebarImport && onAddConfig ? (
          <View
            accessibilityRole="button"
            accessibilityLabel={labels[language].addConfig}
            onStartShouldSetResponder={() => true}
            onResponderRelease={onAddConfig}
            style={[
              styles.addConfigButton,
              compact && styles.addConfigButtonCompact,
              {borderColor: statusColor, backgroundColor: statusTint},
            ]}>
            <Text style={[styles.navText, styles.addConfigText, compact && styles.navTextCompact, isPersian && styles.rtlText]}>
              + {labels[language].addConfig}
            </Text>
          </View>
        ) : null}
        {items.map(item => {
          const isActive = item === activeItem;
          return (
          <Pressable
            key={item}
            accessibilityRole="button"
            accessibilityLabel={labels[language][item]}
            onPress={() => onSelectItem?.(item)}
            style={({pressed}) => [
              styles.navItem,
              compact && styles.navItemCompact,
              isActive && styles.navItemActive,
              pressed && styles.buttonPressed,
              isActive && {backgroundColor: statusTint},
            ]}>
            <Text
              style={[
                styles.navText,
                compact && styles.navTextCompact,
                isActive && styles.navTextActive,
                isPersian && styles.rtlText,
              ]}>
              {labels[language][item]}
            </Text>
          </Pressable>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: 204,
    padding: spacing.md,
    borderRadius: radii.xl,
    backgroundColor: Platform.OS === 'macos' ? 'rgba(12, 13, 26, 0.82)' : 'rgba(12, 13, 26, 0.58)',
    borderColor: 'rgba(229,232,255,0.20)',
    borderWidth: 1,
    minHeight: '100%',
    position: 'relative',
    zIndex: 20,
    shadowColor: '#6F5BFF',
    shadowOpacity: 0.22,
    shadowRadius: 28,
    shadowOffset: {width: 0, height: 16},
    elevation: 10,
  },
  brandRow: {
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
    borderColor: 'rgba(255,255,255,0.20)',
    backgroundColor: 'rgba(255,255,255,0.10)',
  },
  languageFlag: {
    fontSize: 19,
  },
  containerCompact: {
    width: '100%',
    minHeight: 0,
    padding: spacing.sm,
    borderRadius: radii.lg,
  },
  brand: {
    color: colors.textPrimary,
    fontSize: 24,
    fontWeight: '800',
    letterSpacing: 0,
  },
  caption: {
    color: colors.textSecondary,
    marginTop: 7,
    marginBottom: spacing.xl,
    fontSize: 12,
    lineHeight: 16,
  },
  nav: {
    gap: spacing.sm
  },
  navCompact: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs,
  },
  addConfigButton: {
    minHeight: 44,
    paddingHorizontal: spacing.md,
    paddingVertical: 10,
    borderRadius: radii.pill,
    borderWidth: 1,
    justifyContent: 'center',
  },
  addConfigButtonCompact: {
    minHeight: 40,
    paddingHorizontal: spacing.sm,
    paddingVertical: 10,
  },
  navItem: {
    paddingHorizontal: spacing.md,
    paddingVertical: 10,
    borderRadius: radii.pill,
    minHeight: 42,
    justifyContent: 'center',
  },
  navItemCompact: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 10,
    minHeight: 38,
  },
  navItemActive: {
    backgroundColor: 'rgba(155, 140, 255, 0.18)'
  },
  navText: {
    color: colors.textSecondary,
    fontSize: 14,
    fontWeight: '700'
  },
  addConfigText: {
    color: colors.textPrimary,
    fontWeight: '800',
  },
  navTextCompact: {
    fontSize: 13,
  },
  navTextActive: {
    color: colors.textPrimary
  },
  buttonPressed: {
    opacity: 0.82,
  },
  rtlText: {
    writingDirection: 'rtl',
    textAlign: 'right',
    textTransform: 'none',
    letterSpacing: 0,
  }
});

const labels = {
  en: {
    addConfig: 'Add Config',
    overview: 'Overview',
    routing: 'Routing',
    subscriptions: 'Subscriptions',
    latency: 'Latency',
    settings: 'Settings',
  },
  fa: {
    addConfig: 'افزودن کانفیگ',
    overview: 'نمای کلی',
    routing: 'روتینگ',
    subscriptions: 'سابسکریپشن‌ها',
    latency: 'تاخیر',
    settings: 'تنظیمات',
  },
} as const;

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
