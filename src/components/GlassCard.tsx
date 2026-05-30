import React, {PropsWithChildren} from 'react';
import {Platform, StyleProp, StyleSheet, View, ViewStyle} from 'react-native';
import {AppGradient} from './AppGradient';
import {colors, radii} from '../theme/tokens';

type GlassCardProps = PropsWithChildren<{
  style?: StyleProp<ViewStyle>;
  innerStyle?: StyleProp<ViewStyle>;
}>;

export function GlassCard({children, style, innerStyle}: GlassCardProps) {
  const panelColors =
    Platform.OS === 'macos'
      ? ['rgba(12, 19, 28, 0.94)', 'rgba(12, 19, 28, 0.94)']
      : ['rgba(255,255,255,0.14)', 'rgba(255,255,255,0.04)'];

  return (
    <AppGradient
      colors={panelColors}
      start={{x: 0, y: 0}}
      end={{x: 1, y: 1}}
      style={[styles.wrapper, style]}>
      <View style={[styles.inner, innerStyle]}>{children}</View>
    </AppGradient>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    borderRadius: radii.lg,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden'
  },
  inner: {
    backgroundColor: Platform.OS === 'macos' ? 'rgba(8, 14, 22, 0.98)' : colors.panel,
    padding: 18
  }
});
