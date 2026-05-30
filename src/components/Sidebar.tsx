import React from 'react';
import {Platform, Pressable, StyleSheet, Text, View} from 'react-native';
import {colors, radii, spacing} from '../theme/tokens';
import {useAppStore} from '../state/appStore';

const items = ['overview', 'routing', 'subscriptions', 'latency', 'settings'] as const;

interface SidebarProps {
  compact?: boolean;
  language?: 'en' | 'fa';
  onToggleLanguage?: () => void;
}

export function Sidebar({compact = false, language = 'en', onToggleLanguage}: SidebarProps) {
  const tunnel = useAppStore(state => state.tunnel);
  const statusColor = tunnel.connecting ? colors.danger : tunnel.connected ? colors.success : colors.info;
  const statusTint = withAlpha(statusColor, 0.16);
  const isPersian = language === 'fa';

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
        {items.map((item, index) => (
          <Pressable
            key={item}
            style={[
              styles.navItem,
              compact && styles.navItemCompact,
              index === 0 && styles.navItemActive,
              index === 0 && {backgroundColor: statusTint},
            ]}>
            <Text style={[styles.navText, compact && styles.navTextCompact, index === 0 && styles.navTextActive, isPersian && styles.rtlText]}>
              {labels[language][item]}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: 220,
    padding: spacing.lg,
    borderRadius: radii.xl,
    backgroundColor: Platform.OS === 'macos' ? 'rgba(7, 12, 19, 0.96)' : 'rgba(5, 12, 19, 0.52)',
    borderColor: colors.border,
    borderWidth: 1,
    minHeight: '100%'
  },
  brandRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  languageButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.panelStrong,
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
    fontSize: 28,
    fontWeight: '800',
    letterSpacing: 2.2
  },
  caption: {
    color: colors.textSecondary,
    marginTop: 8,
    marginBottom: spacing.xl
  },
  nav: {
    gap: spacing.sm
  },
  navCompact: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs,
  },
  navItem: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderRadius: radii.md
  },
  navItemCompact: {
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  navItemActive: {
    backgroundColor: 'rgba(111, 232, 197, 0.16)'
  },
  navText: {
    color: colors.textSecondary,
    fontSize: 15,
    fontWeight: '600'
  },
  navTextCompact: {
    fontSize: 13,
  },
  navTextActive: {
    color: colors.textPrimary
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
    overview: 'Overview',
    routing: 'Routing',
    subscriptions: 'Subscriptions',
    latency: 'Latency',
    settings: 'Settings',
  },
  fa: {
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
