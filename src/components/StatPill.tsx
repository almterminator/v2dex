import React from 'react';
import {Pressable, StyleSheet, Text, View} from 'react-native';
import {colors, radii} from '../theme/tokens';

export function StatPill({
  label,
  value,
  onPress,
  fillPercent,
  fullWidth = false,
  minWidth,
  rtl = false,
}: {
  label: string;
  value: string;
  onPress?: () => void;
  fillPercent?: number;
  fullWidth?: boolean;
  minWidth?: number;
  rtl?: boolean;
}) {
  const normalizedFill =
    typeof fillPercent === 'number' && Number.isFinite(fillPercent)
      ? Math.max(0, Math.min(fillPercent, 1))
      : undefined;
  const content = (
    <View style={styles.contentRow}>
      <View style={styles.copy}>
        <Text numberOfLines={1} style={[styles.label, rtl && styles.rtlText]}>{label}</Text>
        <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.86} style={[styles.value, rtl && styles.rtlText]}>{value}</Text>
      </View>
      {typeof normalizedFill === 'number' ? (
        <View style={styles.ringTrack}>
          <View style={[styles.ringFill, {height: `${normalizedFill * 100}%`}]} />
          <View style={styles.ringCore} />
        </View>
      ) : null}
    </View>
  );
  const containerStyle = [styles.container, typeof minWidth === 'number' && {minWidth}, fullWidth && styles.containerFullWidth];

  if (onPress) {
    return (
      <Pressable style={({pressed}) => [...containerStyle, pressed && styles.containerPressed]} onPress={onPress}>
        {content}
      </Pressable>
    );
  }

  return (
    <View style={containerStyle}>
      {content}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: radii.md,
    backgroundColor: colors.panelStrong,
    borderColor: colors.border,
    borderWidth: 1,
    minWidth: 140
  },
  containerFullWidth: {
    width: '100%',
  },
  containerPressed: {
    opacity: 0.82
  },
  contentRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  copy: {
    flex: 1,
    minWidth: 0,
  },
  label: {
    color: colors.textSecondary,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 1.2
  },
  value: {
    color: colors.textPrimary,
    fontSize: 18,
    fontWeight: '700',
    marginTop: 6
  },
  ringTrack: {
    width: 34,
    height: 34,
    borderRadius: 17,
    overflow: 'hidden',
    backgroundColor: 'rgba(108, 184, 255, 0.18)',
    borderWidth: 1,
    borderColor: 'rgba(108, 184, 255, 0.46)',
    justifyContent: 'flex-end',
  },
  ringFill: {
    width: '100%',
    backgroundColor: colors.info,
    alignSelf: 'stretch',
  },
  ringCore: {
    position: 'absolute',
    left: 8,
    top: 8,
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: colors.panelStrong,
  },
  rtlText: {
    writingDirection: 'rtl',
    textAlign: 'right',
    textTransform: 'none',
    letterSpacing: 0,
  }
});
