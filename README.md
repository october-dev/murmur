```text
 __  __ _   _ ____  __  __ _   _ ____
|  \/  | | | |  _ \|  \/  | | | |  _ \
| |\/| | | | | |_) | |\/| | | | | |_) |
| |  | | |_| |  _ <| |  | | |_| |  _ <
|_|  |_|\___/|_| \_\_|  |_|\___/|_| \_\
```

# Murmur

**Your wearable. Your models. Your memory.**

Murmur is a planned open-source mobile app for connecting AI wearables to the services you already pay for. Pair a device, add your own provider keys, and turn captured audio into transcripts, summaries, memories, and actions—without being locked into an expensive subscription.

The first target is the [Omi wearable](https://github.com/BasedHardware/omi). The longer-term goal is a small, device-agnostic foundation that can support other Bluetooth voice wearables through adapters.

> [!NOTE]
> This repository is currently a product proposal and planning space. No app has been implemented yet.

## Why this project

AI wearables are useful, but their companion apps often tie the hardware to one cloud, one model, and one recurring plan. Hardware owners should be able to choose how their audio is processed and where their data lives.

Murmur aims to provide:

- **Bring your own keys** — connect transcription and AI providers you choose.
- **Hardware choice** — start with Omi and add devices behind a common interface.
- **Provider choice** — avoid coupling the experience to a single model vendor.
- **Privacy by design** — make capture visible, obtain consent, minimize retention, and keep secrets in platform-secure storage.
- **Open source** — make the client and device integrations inspectable and community-driven.
- **Useful basics** — live transcription, summaries, searchable conversations, notes, and action items without unnecessary complexity.

## Product direction

The initial experience should be deliberately small:

1. Pair an Omi device over Bluetooth Low Energy.
2. Configure a speech-to-text provider and an LLM using your own API keys.
3. Start and stop capture with an unmistakable in-app state.
4. Stream or upload audio for transcription.
5. Generate a summary, notes, and action items.
6. Search or export your own conversation history.

Omi support is the first milestone. Support for additional wearables should arrive through device adapters only after the core flow is reliable.

## Tentative architecture

```text
Wearable
   │ Bluetooth LE
   ▼
Device adapter ──► audio pipeline ──► transcription provider
                                           │
                                           ▼
Local conversation store ◄──────────── AI provider
          │
          └──► summaries, notes, actions, and export
```

Current assumptions—not final decisions:

- A cross-platform mobile client, with **Flutter** as the leading option and **React Native** still under consideration.
- Omi-compatible BLE audio as the first device adapter.
- Direct provider calls where practical, with an optional self-hosted gateway only where mobile limitations require one.
- API keys stored using iOS Keychain / Android Keystore-backed secure storage and never committed or synced by default.
- A local-first data model with explicit opt-in for any cloud synchronization.

## Possible provider support

Provider support will be decided during implementation. Likely categories include:

- Speech-to-text services
- Hosted or local language models
- Embedding and search providers
- Optional user-owned storage or sync backends

The provider layer should use small adapters so users are not forced into one vendor.

## Privacy and responsible recording

A wearable microphone can capture sensitive conversations. The app must make recording status obvious and give people control over collection, retention, deletion, and export. Users are responsible for obtaining consent and following the recording and privacy laws that apply where they live and record.

Before a production release, the project should document its threat model, key storage, data flows, retention defaults, deletion behavior, telemetry, and provider-specific privacy implications.

## Roadmap

- [ ] Validate Omi BLE pairing and audio streaming
- [ ] Choose Flutter or React Native based on a small device prototype
- [ ] Define device, transcription, and AI provider interfaces
- [ ] Build secure bring-your-own-key configuration
- [ ] Ship the basic capture → transcript → summary flow
- [ ] Add local history, search, export, and deletion
- [ ] Document a process for adding more wearable adapters
- [ ] Identify reusable fixes and contribute them upstream to Omi

## Relationship to Omi

[BasedHardware/omi](https://github.com/BasedHardware/omi) is the primary reference for the first device integration. Its open-source Flutter app, firmware, SDKs, and device protocol provide valuable prior art for understanding Omi hardware and BLE audio.

Murmur is an independent community project and is not affiliated with or endorsed by Based Hardware or Omi. We intend to respect upstream licensing, clearly attribute reused work, report relevant findings, and contribute generally useful fixes or documentation back to Omi whenever possible.

## Contributing

The project is in the design stage. Early contributions are especially useful around:

- Omi protocol and BLE behavior
- Flutter versus React Native tradeoffs for background audio and Bluetooth
- secure on-device key and conversation storage
- provider-neutral interfaces
- privacy, consent, and data-retention design
- accessibility and low-friction mobile UX

Open an issue with a focused proposal before starting a large implementation.

## License

Licensed under the [Apache License 2.0](LICENSE).
