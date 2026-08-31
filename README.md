```text
 __  __ _   _ ____  __  __ _   _ ____
|  \/  | | | |  _ \|  \/  | | | |  _ \
| |\/| | | | | |_) | |\/| | | | | |_) |
| |  | | |_| |  _ <| |  | | |_| |  _ <
|_|  |_|\___/|_| \_\_|  |_|\___/|_| \_\
```

# Murmur

**Voice belongs everywhere.**

Murmur is an open-source voice modality layer and reference app for devices,
applications, and agents. It gives software a consistent way to discover voice
sources, capture audio, produce transcripts and structured intent, and route
approved actions—without coupling every product to one wearable, model vendor,
or cloud.

[Omi](https://github.com/BasedHardware/omi) is Murmur's flagship wearable
connector and the first real hardware integration. It is a major part of the
project, but not its boundary. Murmur is designed to accept voice from AI
wearables, the phone microphone, headsets, computers, servers, network streams,
and future hardware through adapters behind one source-neutral contract.

> [!NOTE]
> Murmur is early-stage. The current Flutter app can discover nearby Omi
> wearables, connect or disconnect over Bluetooth Low Energy, and show the live
> connection state. The generalized voice runtime, audio streaming, provider
> adapters, and additional connectors are active roadmap work—not finished
> features.

## Voice as a modality

Voice is more than a recorder screen. It is an input modality that applications
should be able to consume as predictably as touch, keyboard, pointer, or gaze.
Murmur separates that modality into reusable layers:

1. **Connect** to an available voice source.
2. **Capture** normalized audio frames with explicit session state.
3. **Transform** speech through interchangeable transcription, language, and
   text-to-speech providers.
4. **Emit** typed events such as partial transcripts, final transcripts,
   proposed intents, and action results.
5. **Act** through permissioned integrations while treating model output as
   untrusted input.

An app should not need to understand Omi BLE characteristics to receive speech,
and an Omi connector should not need to know which transcription provider or
agent consumes its audio.

## Why Murmur

Voice products are commonly built as closed vertical stacks: one microphone,
one app, one cloud, one model, and one subscription. That makes useful hardware
hard to extend and forces every app team to rebuild capture, permissions,
provider integrations, session state, and safety controls.

Murmur provides an open alternative:

- **Voice-source choice** — wearables, phones, headsets, computers, and streams
  connect through adapters.
- **Bring your own models** — use hosted or local speech, language, and voice
  providers through small interfaces.
- **Embeddable runtime** — applications consume normalized voice events instead
  of device-specific transport details.
- **Reference app** — the Flutter client proves the same public contracts used
  by other applications.
- **Remote control** — approved voice commands can reach paired computers,
  servers, and automations through a secure protocol.
- **Local-first ownership** — users control keys, recordings, transcripts,
  retention, deletion, and export.
- **Open connectors** — hardware support is inspectable, testable, and reusable
  by the community.

## Project surfaces

Murmur is one project with several cooperating surfaces:

| Surface | Purpose | Status |
| --- | --- | --- |
| Voice runtime | Source-neutral sessions, audio frames, events, and capability contracts | Planned |
| Connector SDK | A stable way to add wearables, microphones, and network sources | Planned |
| Omi connector | BLE discovery, connection, and audio transport for Omi hardware | Connection implemented; audio planned |
| Provider adapters | Transcription, language-model, embedding, and speech output integrations | Planned |
| Flutter app | Pair sources, configure providers, capture, review, search, and act | Omi connection implemented |
| Remote agent protocol | Permissioned commands and audited results across computers and servers | Design stage |

The runtime and connector contracts are intended to become an importable Dart
package. The app remains the reference implementation and end-user experience.

## Architecture

```text
 voice sources
 ┌──────────┬──────────┬──────────┬──────────┬───────────┐
 │ Omi BLE  │ phone mic│ headsets │ desktop  │ net stream│
 └────┬─────┴────┬─────┴────┬─────┴────┬─────┴─────┬─────┘
      └───────────┴───────────┼───────────┴───────────┘
                              ▼
                  connector + capability layer
                              │
                              ▼
            voice session ─► normalized audio frames
                              │
                 ┌────────────┼────────────┐
                 ▼            ▼            ▼
                VAD     transcription     local store
                              │
                              ▼
                    typed voice events
                              │
            ┌─────────────────┼──────────────────┐
            ▼                 ▼                  ▼
        host apps         AI providers      remote agents
```

Core code does not depend on a particular device, provider, UI, or remote
transport. Connectors describe their capabilities; consumers decide what to do
with the events they support. See [docs/architecture.md](docs/architecture.md)
for the proposed contracts, dependency rules, and package boundaries. The
[voice runtime design](docs/voice-runtime.md) captures the lifecycle,
endpointing, provider fallback, offline model-pack, and echo-protection patterns
already exercised in October Desktop and opens them for community development.

## First-class voice sources

The connector model covers multiple source families:

- **AI wearables** — Omi first, followed by community-supported devices with
  documented protocols and compatible licenses.
- **Phone and tablet microphones** — a zero-hardware path for development,
  accessibility, and everyday use.
- **Headsets and microphones** — operating-system audio inputs, including wired,
  Bluetooth, and USB devices where the platform exposes them.
- **Desktop and server capture** — local agents that publish permissioned audio
  sessions or voice events.
- **Network and recorded sources** — test fixtures, files, and authenticated
  streams for automation and reproducible development.

Not every connector exposes the same controls. Capability discovery keeps
battery state, hardware buttons, speaker output, codec selection, and background
capture optional instead of leaking device assumptions into the core.

## Technical direction

- A **Dart-first core contract** shared by the package and reference app.
- A **Flutter** client for iOS and Android.
- Transport-specific connectors, with Omi-compatible BLE implemented first
  through `flutter_reactive_ble`.
- Direct provider calls where practical, with an optional self-hosted gateway
  only when platform limitations require one.
- API keys stored using iOS Keychain / Android Keystore-backed secure storage
  and never committed or synchronized by default.
- A local-first data model with explicit opt-in for cloud synchronization.
- Typed events and structured commands instead of passing untrusted model text
  directly into tools.

### Stack

| Area | Choice |
| --- | --- |
| Core and mobile | Dart and Flutter |
| State | Riverpod |
| Navigation | `go_router` |
| Bluetooth LE | `flutter_reactive_ble` behind connector interfaces |
| Local data | Drift and SQLite |
| Secrets | `flutter_secure_storage` |
| Provider APIs | Dart HTTP and WebSockets |
| Remote control | Authenticated agents with an optional relay |
| Backend | None required for local capture and processing |

## Current implementation

Murmur currently targets iOS and Android and uses the application ID
`dev.october.murmur`.

Prerequisites:

- Flutter 3.35 or newer
- the iOS or Android toolchain for the platform you want to run

```bash
flutter pub get
flutter run
```

Run the Omi connection flow on a physical iOS or Android device: Bluetooth
discovery is not available in standard mobile simulators. Wake the Omi, keep it
nearby, allow Bluetooth or Nearby devices access when prompted, and tap
**Scan for Omi**. The app currently shows devices advertising Omi's BLE service.

The current milestone stops at a verified BLE connection. It does not yet
subscribe to the microphone characteristic, record audio, or send data to a
provider.

Before submitting changes:

```bash
flutter analyze
flutter test
```

## Provider model

Transcription and intelligence sit behind provider-neutral adapters. The same
voice session can be processed by a user-selected hosted service, a local model,
or a self-hosted endpoint without changing the connector.

Provider families include:

- speech-to-text and diarization
- language models and structured intent
- embeddings and search
- text-to-speech and wearable response channels
- user-owned storage or synchronization backends

Murmur does not require users to send recordings to an October-operated service.

## Remote manager

Murmur turns voice into a secure remote-management modality. A user can speak
through an Omi, phone, headset, or another connector while away from their desk
and ask a paired computer or server to check a deployment, start a backup, run
an approved automation, or report status.

```text
voice source → Murmur → transcript + structured intent → permission check
                                                        │
                                                        ▼
                                              encrypted relay or tunnel
                                                        │
                                      ┌─────────────────┴─────────────────┐
                                      ▼                                   ▼
                            agent on a computer                 agent on a server
                                      │                                   │
                                      └──────── result + audit ───────────┘
```

Remote control is opt-in and not implemented yet. Its design treats model output
as untrusted input rather than executing generated shell commands directly. It
requires:

- explicitly paired and revocable clients
- encrypted, authenticated communication
- allowlisted tools and structured commands
- confirmation for destructive or sensitive actions
- least-privilege agents on every target machine
- a durable audit log of requests, approvals, results, and failures

Users can self-host the remote agent and relay. A managed relay may be considered
later, but it is not required for local voice features.

## Privacy and responsible recording

A voice modality can capture sensitive conversations regardless of whether its
microphone is in a wearable, phone, or computer. Murmur makes recording and
streaming state explicit and gives users control over collection, providers,
retention, deletion, and export. Users are responsible for obtaining consent
and following applicable recording and privacy laws.

Before a production release, the project documents its threat model, key
storage, data flows, retention defaults, deletion behavior, telemetry, and
provider-specific privacy implications.

## Roadmap

- [x] Choose Flutter for the cross-platform reference app
- [x] Scaffold the iOS and Android app
- [x] Discover Omi hardware and show its live BLE connection state
- [ ] Define the source-neutral voice runtime and typed event contracts
- [ ] Refactor Omi behind the shared connector interface
- [ ] Add a phone-microphone reference connector
- [ ] Validate Omi BLE audio streaming and normalize its audio frames
- [ ] Add provider-neutral transcription interfaces and a deterministic fake
- [ ] Add the capture coordinator with safe cancellation, tail flushing, and
      warm push-to-talk
- [ ] Add provider selection with offline-first fallback
- [ ] Add an atomic on-device voice model-pack manager
- [ ] Add speech feedback with interruption and echo-loop protection
- [ ] Build secure bring-your-own-key configuration
- [ ] Ship the capture → transcript → summary reference flow
- [ ] Add local history, search, export, retention, and deletion
- [ ] Document and test the process for adding more voice connectors
- [ ] Design and implement the authenticated remote-agent protocol
- [ ] Package the reusable runtime for other Flutter and Dart applications
- [ ] Identify reusable fixes and contribute them upstream to Omi

## Relationship to Omi

[BasedHardware/omi](https://github.com/BasedHardware/omi) is the primary
reference for Murmur's first wearable connector. Its open-source Flutter app,
firmware, SDKs, and device protocol provide valuable prior art for understanding
Omi hardware and BLE audio.

Murmur is an independent community project and is not affiliated with or
endorsed by Based Hardware or Omi. We respect upstream licensing, clearly
attribute reused work, report relevant findings, and contribute generally useful
fixes or documentation back to Omi whenever possible.

The current device detection follows Omi's advertised BLE service and is
attributed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Contributing

Community tasks live in [GitHub Issues](https://github.com/october-dev/murmur/issues).
Issues marked `good first issue` are deliberately bounded; `help wanted` issues
benefit from domain or platform experience. Comment on an issue before starting
large work so connector and public-API decisions stay coordinated.

Contributions are especially useful around:

- core voice-session, audio-frame, capability, and event contracts
- Omi protocol behavior and BLE audio
- phone, headset, desktop, network, and wearable connectors
- reliable background capture on iOS and Android
- provider-neutral transcription and AI interfaces
- voice-session races, endpointing, model packs, and engine fallback
- accessible speech feedback and echo-loop prevention
- secure on-device keys and conversation storage
- remote-agent permissions, commands, and auditing
- privacy, consent, accessibility, and data-retention design

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

Licensed under the [Apache License 2.0](LICENSE).
