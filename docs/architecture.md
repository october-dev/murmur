# Murmur architecture

Murmur is a source-neutral voice modality runtime with a Flutter reference app.
The architecture keeps hardware transport, speech providers, product UI, and
remote actions independent so each can evolve without becoming a requirement
for the others.

The wire boundary exists as the versioned `murmur.v1` Protocol Buffer schema.
Runtime interfaces that do not yet exist remain proposals to be refined through
linked GitHub issues and small pull requests.

## Dependency rule

Dependencies point inward:

```text
apps / agents / host integrations
              │
              ▼
connectors / providers / runtime policy
              │
              ▼
        language SDK model
              │
              ▼
 murmur.v1 protocol + conformance suite
```

The protocol does not import or encode Flutter UI, Omi-specific behavior,
provider SDKs, databases, or remote-agent transports. SDKs depend on the
protocol; connectors and applications depend on an SDK. The dependency never
points back from the protocol to an implementation.

## Layers

### Protocol contracts

The protocol owns the smallest stable vocabulary shared across integrations:

- `VoiceSource` — identity, display metadata, transport, and capabilities
- `VoiceConnector` — discovery and connection lifecycle for a source family
- `VoiceSession` — one explicit capture connection with state and cleanup
- `AudioFormat` — sample rate, channels, sample encoding, frame duration, codec
- `AudioFrame` — bytes plus source and monotonic timing metadata
- `VoiceEvent` — session, speech, transcript, intent, action, and error events
- `VoiceCapability` — optional features such as battery, buttons, speaker output,
  background capture, and device-side recording

The canonical fields live in `spec/proto/murmur/v1`. Binary transports use
protobuf encoding; JSON transports and fixtures use ProtoJSON. Session-scoped
sequences and monotonic timestamps preserve order without pretending clocks on
different machines are comparable.

### SDKs and conformance

SDKs provide idiomatic models and runtime implementations without becoming the
source of truth. Dart, TypeScript, Python, and Rust start from the same event
envelope and fixtures. A new Swift, Kotlin, C++, Go, or other SDK can become
compatible by implementing `murmur.v1` and passing `conformance/`.

Generated protobuf bindings may remain internal to an SDK. Connector and app
APIs should expose stable, idiomatic types instead of code-generator details.

### Connectors

Connectors translate a source-specific transport into core contracts. Examples
include Omi BLE, phone microphone, operating-system audio input, a test fixture,
or an authenticated network stream.

A connector owns:

- discovery or source enumeration
- permission and readiness reporting
- connect, start, stop, disconnect, and cleanup behavior
- source-specific codec parsing and metadata
- capability reporting
- actionable errors without provider or product assumptions

A connector does not choose transcription vendors, write conversation history,
interpret commands, or render product UI.

### Audio and speech pipeline

The pipeline accepts normalized frames and may add voice activity detection,
resampling, buffering, transcription, diarization, and speech output. Each stage
is replaceable and declares the formats or events it consumes and produces.

Backpressure, interruption, reconnect, and partial-result semantics must be
explicit. Unbounded audio buffering is not acceptable.

The capture coordinator is a separate runtime component, not UI state. It owns
session generations, immediate input gating, bounded finalization, warm
push-to-talk parking, honest capture readiness, and cleanup. The detailed
runtime design and race-condition invariants are in
[voice-runtime.md](voice-runtime.md).

### Providers

Provider adapters expose narrow capabilities rather than one universal AI
client. Initial families are transcription, language or structured intent,
embeddings, and text-to-speech. A deterministic fake provider supports tests and
offline development.

Secrets are passed to adapters through a credential boundary; connectors and
core events never carry API keys.

### Storage

Storage consumes events through an interface. The reference app uses a local
implementation, while host apps can substitute their own retention or sync
policy. Raw audio retention is separate from transcript retention and is off by
default unless a product explicitly enables it.

### Remote actions

Remote management consumes finalized transcripts or structured intent only
after an explicit policy check. Models propose commands; they do not execute
arbitrary text. Commands are typed, allowlisted, attributable, revocable, and
audited.

## Event flow

```text
source discovered
    → session connecting
    → session ready
    → capture started
    → audio frames
    → speech segment started/updated/ended
    → transcript partial/final
    → intent proposed
    → approval requested/granted/denied
    → action started/result/failed
    → capture stopped
    → session closed
```

Consumers subscribe only to the events they need. Ordering is guaranteed within
a session; events from different sessions are not assumed to share a clock.

## Connector capability model

Capabilities prevent Omi or mobile assumptions from becoming universal:

| Capability | Example |
| --- | --- |
| Live audio | Stream microphone frames while connected |
| Stored audio | Download recordings captured by a device |
| Battery | Report battery level or charging state |
| Hardware control | Surface button presses or capture state |
| Output audio | Play a response through the source |
| Background mode | Continue an explicit session while the app is backgrounded |

Unsupported capabilities remain absent, not simulated.

## Repository layout

```text
spec/                           # canonical protobuf + manifest schemas
conformance/                    # shared ProtoJSON fixtures
sdks/
├── dart/murmur_protocol/       # Flutter and pure-Dart surface
├── typescript/                 # Node, Electron, web, React Native
├── python/                     # research, automation, AI services
└── rust/murmur-protocol/       # native, sidecar, server, embedded
packages/
├── flutter/murmur_flutter/     # Flutter native capability binding
└── react-native/               # Expo / React Native native binding
connectors/                     # connector manifests and packages
apps/flutter/                   # reference mobile experience
agents/                         # remote-manager implementations
integrations/omarchy/           # Omarchy Quattro bar integration
```

## Privacy and security invariants

- Capture and streaming state are visible and attributable to a source.
- Opening a connection does not silently begin recording.
- Raw audio is not retained by default.
- Provider credentials never enter logs, events, connector metadata, or storage.
- Remote actions require structured commands and a policy decision.
- Destructive or sensitive actions require confirmation.
- Every long-lived session has an explicit, idempotent close path.
- Late events from a cancelled or superseded session cannot dispatch actions.
- Speech output gates recognition so the application cannot transcribe itself.
- Diagnostics contain lifecycle metadata and text lengths, not speech content.
- Tests and examples use synthetic audio unless redistribution and consent are
  documented.

## Definition of a supported connector

A connector is considered supported when it includes:

1. protocol and license provenance
2. capability documentation
3. permission and lifecycle handling
4. format or codec documentation
5. deterministic tests without requiring hardware
6. a documented physical-hardware validation procedure
7. privacy behavior and known platform limitations

Experimental connectors may land earlier when they are clearly labeled and do
not destabilize the core contract.
