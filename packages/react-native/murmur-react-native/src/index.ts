export type {
  ProtocolVersion,
  RuntimeEvent,
  RuntimePayload,
  RuntimePayloadKind,
  VoiceSource,
  VoiceSourceTransport,
} from '@october-dev/murmur-protocol';

export {
  parseRuntimeEvent,
  parseRuntimeEventJson,
  runtimeEventToJson,
  runtimePayloadKinds,
  voiceSourceTransports,
} from '@october-dev/murmur-protocol';

import MurmurReactNativeModule, {
  type MurmurNativeCapabilities,
} from './MurmurReactNativeModule';

export type { MurmurNativeCapabilities };

export function getCapabilities(): MurmurNativeCapabilities {
  return MurmurReactNativeModule.getCapabilities();
}

export function requestPermissions(): Promise<boolean> {
  return MurmurReactNativeModule.requestPermissions();
}
