# Contributing to Murmur

Murmur welcomes focused contributions to its voice runtime, connectors,
providers, reference app, documentation, privacy model, and remote-agent design.

## Choose a task

Start with an open [GitHub issue](https://github.com/october-dev/murmur/issues).
Comment that you want to work on it and include any relevant device or platform
access. Maintainers will confirm the direction before substantial public-API or
architecture work begins.

- `good first issue` means the task is bounded and has a clear review path.
- `help wanted` means community ownership is encouraged.
- Area labels identify core, connector, provider, app, documentation, privacy,
  or remote-agent work.

Please open a focused proposal before adding a new dependency, connector family,
public contract, storage backend, or remote command.

## Development setup

Prerequisites:

- Flutter 3.35 or newer
- an iOS or Android toolchain for platform work
- a physical device for Bluetooth validation

```bash
flutter pub get
flutter analyze
flutter test
```

Standard simulators do not provide the complete BLE path. Most core, provider,
and UI changes should still be testable without physical hardware through fakes
and recorded protocol fixtures.

## Design rules

- Keep the core source-neutral; do not add Omi or provider assumptions to shared
  contracts.
- Keep transport, audio processing, providers, storage, and UI behind separate
  boundaries.
- Make start, stop, disconnect, cancellation, and cleanup behavior explicit.
- Treat model output as untrusted input.
- Never commit API keys, recordings, transcripts, device identifiers, or private
  endpoint details.
- Do not claim hardware support or accuracy without documented physical testing.
- Use synthetic audio in tests unless a fixture has clear consent and licensing.
- Preserve attribution and license notices for adapted code or protocol details.

Read [docs/architecture.md](docs/architecture.md) before changing a shared
interface. Read [docs/voice-runtime.md](docs/voice-runtime.md) before changing
capture lifecycle, provider, endpointing, model-pack, or speech-output behavior.

## Voice-runtime pull requests

Runtime changes should include deterministic tests for the failure and timing
paths they touch. Depending on the change, cover delayed startup, cancellation
during startup, late partials or finals, duplicate finalization, empty results,
provider disconnect, input mute and resume, timeout cleanup, and speech-output
echo suppression. Tests must use synthetic text and audio.

Keep product commands and billing policy outside the runtime. Provider-specific
dependencies belong behind adapters, with their licenses and model terms called
out in the pull request.

## Connector pull requests

A connector contribution should document:

1. the device or source and supported platforms
2. protocol provenance and upstream license
3. permissions and discovery behavior
4. connection and capture lifecycle
5. audio codec, sample rate, channels, and framing
6. supported and unsupported capabilities
7. reconnect, interruption, and cleanup behavior
8. automated tests using a fake or fixture
9. manual hardware-validation steps and results
10. privacy implications and known limitations

Experimental support is welcome when its status is explicit.

## Pull-request checklist

- Keep the change focused on one issue.
- Add or update tests for behavior changes.
- Run `flutter analyze` and `flutter test`.
- Update public documentation when behavior or contracts change.
- Link the issue and explain how each acceptance criterion is satisfied.
- Call out untested platforms or hardware honestly.
- Do not include drive-by formatting or unrelated generated files.

By contributing, you agree that your contribution is licensed under the
repository's [Apache License 2.0](LICENSE).
