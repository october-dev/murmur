# murmur_flutter

Flutter bindings for Murmur. The plugin exposes native capability checks and
re-exports the versioned contracts from `murmur_protocol`, so Flutter apps can
add microphone, wearable, transcription, and remote-action adapters behind one
API.

```dart
import 'package:murmur_flutter/murmur_flutter.dart';

final capabilities = await MurmurFlutter.getCapabilities();
```

The native channel is scaffolded for iOS and Android. It does not capture audio
or request permissions yet. Omi support remains in the reference app while its
connector is extracted behind the public interface.

Licensed under Apache-2.0. See the repository root for the license text.
