import React from 'react';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {DashboardScreen} from './src/screens/DashboardScreen';

export default function App() {
  return (
    <SafeAreaProvider>
      <DashboardScreen />
    </SafeAreaProvider>
  );
}
