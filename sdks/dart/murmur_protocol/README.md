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

`VoiceProvider` and `ProviderSession` define the provider-neutral streaming
transcription boundary. Create a session, subscribe to its events, await
`start`, await each `addFrame`, concatenate finals verbatim, and end with
`finalize` or `stop`. The dartdoc on `ProviderSession` is the normative
contract.

The package source and pub.dev metadata are in place. It remains unpublished
while the initial public protocol is reviewed against the shared fixtures in
`conformance/`.

## Deterministic fake connector

`package:murmur_protocol/testing.dart` provides `FakeVoiceConnector` and
`FakeVoiceSession` so hosts, providers, and apps can be developed and tested
without hardware. Discovery emits the configured sources in order, and
sessions follow `idle → starting → listening → stopped | error` without timers
or randomness.

On entering `listening`, each session produces the two synthetic frames from
`conformance/README.md`: 16 kHz mono `pcmS16le` in 10 ms frames, a 1 kHz sine
at sequence 1 and silence at sequence 2. `monotonicTimeUs` is 10000 and 20000
on a clock that is 0 when capture starts. Frames are buffered for a late or
paused consumer, never more than those two.

Tests drive the fake with `autoCompleteStart: false` plus
`session.completeStart()`, `session.fail(error)` for device loss, and the
mutable `connector.connectError`. These controls are fake-only and are not part
of `VoiceConnector` or `VoiceSession`. See `example/fake_voice_connector.dart`
for host code that consumes it.

## License

Licensed under Apache-2.0. See the repository root for the license text.
