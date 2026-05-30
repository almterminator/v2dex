import React, {PropsWithChildren} from 'react';
import {Platform, StyleProp, View, ViewStyle} from 'react-native';
import LinearGradient from 'react-native-linear-gradient';

type Point = {
  x: number;
  y: number;
};

type AppGradientProps = PropsWithChildren<{
  colors: string[];
  style?: StyleProp<ViewStyle>;
  start?: Point;
  end?: Point;
}>;

export function AppGradient({children, colors, style, start, end}: AppGradientProps) {
  if (Platform.OS === 'macos') {
    return <View style={[{backgroundColor: colors[colors.length - 1] ?? colors[0]}, style]}>{children}</View>;
  }

  return (
    <LinearGradient colors={colors} style={style} start={start} end={end}>
      {children}
    </LinearGradient>
  );
}
