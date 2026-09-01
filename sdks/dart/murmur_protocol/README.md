# murmur_protocol

Pure-Dart models and conformance helpers for the versioned `murmur.v1` voice
protocol. The package has no Flutter dependency and works in Flutter apps,
Dart services, CLIs, and tests.

```dart
import 'package:murmur_protocol/murmur_protocol.dart';

final event = RuntimeEvent.fromJsonString(message);
```

The package source and pub.dev metadata are in place. It remains unpublished
while the initial public protocol is reviewed against the shared fixtures in
`conformance/`.

Licensed under Apache-2.0. See the repository root for the license text.
