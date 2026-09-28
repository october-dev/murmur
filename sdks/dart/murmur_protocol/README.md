# murmur_protocol

Pure-Dart models and conformance helpers for the versioned `murmur.v1` voice
protocol. The package has no Flutter dependency and works in Flutter apps,
Dart services, CLIs, and tests.

```dart
import 'package:murmur_protocol/murmur_protocol.dart';

final event = RuntimeEvent.fromJsonString(message);
```

Typed `AudioFormat`, `AudioFrame`, and `SessionControl` models preserve the
`murmur.v1` wire contract. Framework-neutral `VoiceConnector` and
`VoiceSession` interfaces let pure-Dart and Flutter hosts use the same explicit
discovery, connection, capture, error, and cleanup lifecycle.

`VoiceCaptureCoordinator` owns one capture generation at a time: it connects a
session, opens a `VoiceProvider`, gates and finalizes input, assembles each
utterance once, and emits ordered `murmur.v1` events. Every wait is bounded by
`CaptureTimeouts` on an injectable `Scheduler`, so hosts test lifecycle races
under `ManualScheduler` without real timers. The shared `conformance/`
scenarios freeze that behavior for every SDK.

```dart
final coordinator = VoiceCaptureCoordinator(
  connector,
  provider,
  onUtteranceFinalized: (text) => print(text),
);
try {
  await coordinator.start(source: source, mode: CaptureMode.holdToTalk);
  await coordinator.release();
  print('Dropped frames: ${coordinator.snapshot.droppedFrames}');
} finally {
  await coordinator.dispose();
}
```

`CaptureSnapshot.droppedFrames` counts frames dropped from bounded pre-roll
for the current generation and resets on a new generation. Keep the coordinator
for repeated holds; call `dispose()` when its owner is finished to stop capture
and close both streams. Disposal is idempotent; starting afterward throws.

`onUtteranceFinalized` runs synchronously. If it throws, the coordinator reports
the original error and stack trace asynchronously to the delivery zone's
uncaught-error handler (for example, `runZonedGuarded`). Capture state and
release/finalize futures are unaffected, and the callback is not retried.

The package source and pub.dev metadata are in place. It remains unpublished
while the initial public protocol is reviewed against the shared fixtures in
`conformance/`.

Licensed under Apache-2.0. See the repository root for the license text.
