# @october-dev/murmur-react-native

Native Murmur bindings for Expo and React Native apps on iOS and Android. This
is a mobile package, not a web SDK.

```sh
npm install @october-dev/murmur-protocol @october-dev/murmur-react-native
```

Add the config plugin to an Expo app:

```json
{
  "expo": {
    "plugins": ["@october-dev/murmur-react-native"]
  }
}
```

Then create a development build with `npx expo prebuild` and
`npx expo run:ios` or `npx expo run:android`. Native BLE and microphone code is
not available in Expo Go.

Bare React Native apps can use the same package after installing Expo Modules;
they do not need to adopt Expo's managed workflow.

```ts
import {
  getCapabilities,
  requestPermissions,
} from '@october-dev/murmur-react-native';

const capabilities = getCapabilities();
const granted = await requestPermissions();
```

The package currently exposes native capability checks and permission
configuration. Capture and Omi connector implementations are not included yet.
The source scaffold is not published to npm yet.
