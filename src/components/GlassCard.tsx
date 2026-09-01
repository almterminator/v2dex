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
      ? ['rgba(15, 17, 30, 0.92)', 'rgba(15, 17, 30, 0.92)']
      : ['rgba(255,255,255,0.16)', 'rgba(255,255,255,0.055)'];

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
    overflow: 'hidden',
    shadowColor: '#7464FF',
    shadowOpacity: 0.16,
    shadowRadius: 24,
    shadowOffset: {width: 0, height: 12},
    elevation: 8,
  },
  inner: {
    backgroundColor: Platform.OS === 'macos' ? 'rgba(10, 12, 22, 0.90)' : colors.panel,
    padding: 18,
  }
});
