import { NativeModule, requireNativeModule } from 'expo';

export type MurmurNativeCapabilities = {
  microphone: boolean;
  bluetoothLowEnergy: boolean;
};

declare class MurmurReactNativeModule extends NativeModule {
  getCapabilities(): MurmurNativeCapabilities;
  requestPermissions(): Promise<boolean>;
}

export default requireNativeModule<MurmurReactNativeModule>(
  'MurmurReactNative'
);
