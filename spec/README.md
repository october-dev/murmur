# Murmur protocol specification

The files under `proto/murmur/v1` are Murmur's language-neutral source of
truth. Applications, connectors, providers, SDKs, sidecars, and remote agents
exchange these concepts without depending on Flutter or Dart.

The first stable namespace is `murmur.v1`. Backward-compatible fields may be
added within v1. Removing fields, changing field meanings, reusing field
numbers, or changing enum values requires a new protocol namespace.

## Encoding

- Protocol Buffers are canonical for binary and generated SDK use.
- ProtoJSON is canonical for JSON transports and conformance fixtures.
- Audio payloads use protobuf `bytes`; ProtoJSON represents them as base64.
- Event order uses a `sequence` scoped to the envelope's routing identifier,
  not wall-clock time.
- `monotonic_time_us` measures elapsed time on the producing host and must not
  be compared across machines or sessions.

The protocol does not prescribe an in-process API or transport. It can cross a
WebSocket, gRPC stream, local socket, stdio sidecar, FFI boundary, or remain
inside one process. Routing keys are therefore carried in every message rather
than assumed from a connection.

## Version

The current wire contract is `murmur.v1` **1.1**. Minor 1 adds the engine,
voice-pack, speech-output, microphone, provider-lifecycle, input-gate,
wake-phrase, speaker-verification, and batch contracts described below.
Producers set `protocol.minor` to the additive revision they speak; readers
support every minor of their major and ignore unknown fields.

## Envelopes and scopes

| Envelope | Routing key | Ordering key | Carries |
| --- | --- | --- | --- |
| `RuntimeEvent` | `session_id` | `sequence` | session events |
| `SessionControl` | `session_id` | `request_sequence` | session commands |
| `AudioFrame` | `session_id` | `sequence` | session audio |
| `EngineEvent` | `engine_id` | `sequence` | engine events |
| `EngineControl` | `engine_id` | `request_sequence` | engine commands |

Ordering keys strictly increase per routing key, so one transport can carry
several sessions and engines. The routing key is required and non-empty.

Engine-scoped concepts exist before, after, or across capture sessions, so they
live in the engine envelopes:

| Concept | Carrier |
| --- | --- |
| Engine identity, locality, platform, capabilities, readiness | `EngineEvent.engine_status` |
| Voice-pack state, components, byte progress, typed errors | `EngineEvent.voice_pack_status` |
| Voice-pack prepare, retry, repair | `EngineControl.voice_pack` |
| Microphone permission, route, interruption, device readiness | `EngineEvent.microphone_status` |
| Speech-output request and cancellation | `EngineControl.speak`, `EngineControl.cancel_speech` |
| Speech-output lifecycle and outcome | `EngineEvent.speech_output` |

Session-scoped concepts extend the session envelopes:

| Concept | Carrier |
| --- | --- |
| Session to engine binding | `StartSession.engine_id`, `StartBatchTranscription.engine_id` |
| Provider lifecycle and graceful-finalization outcome | `RuntimeEvent.provider_status` |
| Effective recognition-input gate, including half duplex | `RuntimeEvent.input_gate_status` |
| Speaker-verification mode and bypass | `SessionControl.speaker_verification` |
| Speaker outcome and rejected finals | `Transcript.speaker_verification` with `Transcript.kind` |
| Wake-phrase detection, activation, dismissal | `RuntimeEvent.wake_phrase` |
| Batch transcription | `SessionControl.start_batch`, `AudioFrame`, `finalize`, `stop`, `RuntimeEvent.batch_progress`, `Transcript.words`, `provider_status` |

## Capabilities

`EngineDescriptor.capabilities` is a list of stable string tokens. Absence
means unsupported, and readiness is not capability. Receivers ignore unknown
tokens for negotiation and preserve them, so a new token never breaks an older
client. Engines never simulate an unsupported capability.

| Token | Gates |
| --- | --- |
| `streaming_transcription` | `start` |
| `graceful_finalization` | `finalize` |
| `batch_transcription` | `start_batch` |
| `word_timings` | `Transcript.words` |
| `speech_output` | `speak`, `cancel_speech` |
| `echo_cancellation` | `SpeakRequest.full_duplex` |
| `wake_phrase` | `start` with `CAPTURE_MODE_WAKE_PHRASE` |
| `speaker_verification` | `speaker_verification` |
| `voice_packs` | `voice_pack` |

A session whose `start` names an `engine_id` is engine-bound: its commands are
gated by that engine's capabilities and it receives that engine's half-duplex
gate causes. A session without `engine_id` is unbound and keeps unchanged v1
behavior for `start` (in any capture mode, including a host-side wake detector),
`input_gate`, `finalize`, and `stop`. `speaker_verification` on an unbound
session is rejected with `invalid_state`; `start_batch` always names an engine.

The existing `VoiceSource.capabilities` remains a closed enum.

## Command rejection and operation outcomes

A command the receiver refuses before acting on it (for example
`capability_unsupported`, `invalid_state`, or an unknown `pack_id`) produces
only a `MurmurError` on the generic error arm of the matching stream:
`RuntimeEvent.error` for session commands and `EngineEvent.error` for engine
commands. That error must set `metadata["request_sequence"]` to the rejected
command's `request_sequence` as a canonical decimal string; with the envelope
routing key it identifies the rejected request. A capability rejection also
sets `metadata["capability"]` to the missing token. A rejected command starts
no operation, emits no lifecycle or terminal event, and changes no state, so
hosts must not wait for a terminal state of a rejected request. Generic errors
that are not command rejections omit `request_sequence`. The key is reserved
and carries no user content.

Every accepted operation reaches exactly one terminal state, even when
cancellation races completion:

- a provider session, streaming or batch: `FINALIZED`, `CANCELLED`, or `FAILED`
- a speech output: `COMPLETED`, `CANCELLED`, or `FAILED`

A failure after acceptance is reported through that operation's `FAILED` state
and its `error`, never through the generic error arm. `FAILED` requires an
error, and an error is forbidden in every other provider, speech-output,
voice-pack, and component state. An engine that is `NOT_READY` may carry an
error as its reason. Cancellation is never failure.

`FINALIZED` means every final transcript for accepted audio has already been
emitted. `stop` cancels and is never graceful.

### Error codes

New contracts use these stable `MurmurError.code` values:

| Code | Meaning |
| --- | --- |
| `capability_unsupported` | The engine does not advertise a required capability |
| `invalid_state` | The command is not legal in the current state |
| `permission_denied` | The operating system denied a required permission |
| `voice_pack_required` | A voice pack must be prepared first |
| `voice_pack_download_failed` | Voice-pack content could not be fetched |
| `voice_pack_verification_failed` | Voice-pack content failed verification |
| `insufficient_storage` | Not enough storage to install a voice pack |
| `speech_output_timeout` | A speech-output watchdog expired |
| `provider_timeout` | A provider did not respond in time |

## Voice packs

`VoicePackStatus` is a full snapshot keyed by `pack_id`, emitted when the pack
changes and when a voice-pack request is received. It does not identify which
request caused it. A pack is `READY` exactly when every required, supported
component is `READY`; component states are diagnostic and never authorize use
of a pack that is not `READY`. A byte total of 0 means unknown; otherwise the
completed count must not exceed it.

- `PREPARE` is idempotent and single-flight per pack, and a no-op when `READY`.
- `RETRY` is allowed after `FAILED` with a retryable error. It invalidates the
  failed components and prepares again.
- `REPAIR` verifies every component and re-fetches damaged ones. The engine may
  also repair automatically, bounded and never looping, reported as
  `REPAIRING`.

## Speech output and the input gate

`InputGateStatus.closed_by` is the full set of active reasons recognition input
is closed; an empty set means open. It is emitted whenever the set changes.
Values are distinct and their order is not significant. Each holder adds and
removes only its own cause, so input reopens only when no cause remains, and a
cause stays in the set while any holder still holds it.

Speech output is single-flight per engine: a new `speak` cancels the active
output. A half-duplex output (`full_duplex` false, the default) adds
`SPEECH_OUTPUT` to every live engine-bound session on its engine during
playback, replaces it with `ECHO_CLEARANCE` for the echo tail
(`echo_clearance_ms`, or the engine default when 0), and then removes it. A
full-duplex output requires `echo_cancellation` and never gates input.

If playback began, completion, cancellation, and failure all stop playback,
move through `ECHO_CLEARING` for the tail, and then emit the terminal state as
the output's gate cause is removed. An output cancelled or failed before
playback began terminates immediately and never adds a cause. A watchdog
failure (`FAILED` with `speech_output_timeout`) uses a bounded tail. A speech
tail or watchdog never opens a gate held by `HOST`, `FINALIZATION`, or
`INTERRUPTION`.

## Microphones

`MicrophoneStatus` is a full, device-level snapshot per `source_id`, emitted
before any session exists (for example to arm wake detection). It is distinct
from `CaptureReadiness.live`, which reports real audio flowing in a session.
`interruption` is set exactly when readiness is `INTERRUPTED`. Device names and
raw device identifiers are forbidden. `MicrophoneRoute` is validated and fails
closed, so a new route value is emitted only behind a capability token.

## Speaker verification

A final refused by speaker verification is a `Transcript` with
`kind = TRANSCRIPT_KIND_REJECTED` and `speaker_verification` set to `REJECTED`
(a different speaker) or `UNCERTAIN` (a fail-closed policy). Its text may be
shown but must never be dispatched as a command. `TRANSCRIPT_KIND_REJECTED`
without `speaker_verification` keeps its existing meaning: a final rejected for
another reason. Hosts therefore treat every `REJECTED` final as display-only.

| `Transcript.kind` | Allowed `speaker_verification` |
| --- | --- |
| `UNSPECIFIED` | absent |
| `PARTIAL` | absent |
| `FINAL` | absent, `ACCEPTED`, `BYPASSED`, `UNCERTAIN` (fail-open) |
| `REJECTED` | absent, `REJECTED`, `UNCERTAIN` (fail-closed) |

An absent or `UNSPECIFIED` result means not evaluated.

`SetSpeakerVerification` changes the session mode:

- `BYPASSED` is legal only while the mode is `ENFORCED` and covers the current
  utterance. The engine restores `ENFORCED` after that utterance's accepted
  tail is finalized and on every stop or error path. A bypassed utterance
  produces `FINAL` with `BYPASSED`, never `REJECTED`.
- Bypass requested in any other mode is rejected with `invalid_state`.
- `DISABLED` is a separate, explicit mode that bypass never changes.

## Wake phrases

`WakePhraseEvent` reports `DETECTED`, then `ACTIVATED` or `DISMISSED` (the
false-positive policy discarded the detection) in a
`CAPTURE_MODE_WAKE_PHRASE` session. `phrase_id` names a host-configured phrase,
never captured speech. Wake-phrase configuration is a product setting and is
not part of the protocol.

## Batch transcription

A batch job is a session:

1. `start_batch` names the engine and the audio format.
2. `AudioFrame` messages on the same session carry the audio in that format.
3. `finalize` marks the end of input.
4. Zero or more `batch_progress` events and `FINAL` transcripts (with `words`)
   follow.
5. `provider_status` `FINALIZED` completes the job. Zero transcripts is a valid
   empty result.

`stop` cancels (`CANCELLED`), and a failure reports `FAILED` with an error.
Audio is carried only in frames; file paths and URLs are not part of the
protocol.

Batch offsets are uint32 milliseconds on the submitted-media timeline, unrelated
to the envelope `monotonic_time_us`. Sample 0 is the first sample of the first
`AudioFrame` submitted to the session, and frames are contiguous by sample
count whether or not the provider uses every sample. PCM frame durations follow
from payload length and format; Opus frames take their duration from
`frame_duration_ms`, which is therefore required for an Opus batch. A word
covers `[start_offset_ms, end_offset_ms)`: start rounds down, end rounds up,
start is at most end, and words are ordered by non-decreasing start.
`Transcript.words` is emitted only in batch sessions; live word timing is not
defined. `echo_clearance_ms` is a duration.

## Evolution rules

- Never reuse or renumber fields or enum values. A retired field reserves both
  its number and its name.
- Envelope metadata uses field numbers 1 through 9. Oneof arms start at 10 and
  are append-only.
- Every enum's zero value is `*_UNSPECIFIED` and is never repurposed.
- Growable feature sets use string tokens, like capabilities. Validated enums
  (states, outcomes, discriminators, and `MicrophoneRoute`) fail closed, so a
  new value in one of them is emitted only behind a capability token.

## Out of scope

Product commands, UI state, entitlement, subscription, or trial fields,
analytics and usage metering, model or provider choice, product settings
(including wake-phrase configuration), credentials, device names and raw device
identifiers, and filesystem paths or signed URLs do not enter the protocol.

## Validate

With `protoc` installed, run:

```bash
make check-protocol
```

The command compiles every schema into a temporary descriptor set without
writing generated code into the repository.
