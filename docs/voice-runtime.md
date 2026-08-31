# Voice runtime

Murmur's voice runtime is the source- and provider-neutral control plane between
an audio connector and an application. It owns capture-session correctness; it
does not own a particular microphone, speech model, agent, or product command.

This design distills field-tested voice runtime patterns into public,
implementation-independent contracts. The goal is to let contributors improve
the hard, reusable parts of voice once and share those improvements across
applications. Product commands, account rules, private endpoints, and
third-party native implementation code are outside this design.

## Runtime boundary

```text
connector                     runtime                       consumers
---------                     -------                       ---------
mic / wearable  ->  capture coordinator  ->  transcript / intent / UI
                         |       |       |
                         |       |       +-- speech feedback
                         |       +---------- provider adapter
                         +------------------ session policy
```

The connector owns access to audio. The provider owns recognition. The runtime
coordinates them and emits ordered events. A host application decides how a
final transcript or proposed intent is used.

The runtime must be usable without a particular host application, Omi, Flutter
widgets, a paid service, or a network connection.

## Proposed runtime contracts

The language-neutral event envelope is defined in `murmur.v1`. Each SDK can
offer an idiomatic coordinator and provider API, but its observable behavior
should preserve these concepts and pass the shared conformance suite:

### `VoiceProvider`

A live provider session starts with callbacks or an event stream and has an
idempotent hard stop. Optional capabilities are declared instead of assumed:

- partial and final transcript delivery
- immediate input mute and warm unmute
- graceful finalization of a server-side decoder
- real-audio readiness and normalized amplitude
- rejected-final reporting, for example when optional speaker verification
  rejects a segment
- provider close and typed failure events

`stop` means cancel and release resources. `finalize` means close the input
gate, let already accepted audio finish decoding, return the final text, and
then release resources. They are deliberately different operations.

### `VoiceCaptureCoordinator`

The coordinator owns one active capture generation. Its public state should be
small enough for any UI to render without reconstructing internal timing:

```text
idle -> starting -> listening -> finalizing -> idle
           |            |             |
           +---------- error <--------+

listening <-> warm-muted
```

Suggested observable fields include capture mode, session identifier,
amplitude, partial text, buffered final text, whether real audio is live,
whether finalization is pending, and an actionable error.

### Events

Every event carries a session identifier and monotonic sequence. At minimum:

- capture starting, live, muted, resumed, stopping, and stopped
- amplitude changed
- transcript partial, final, and rejected
- provider warning, failure, and closed
- intent proposed and confirmation requested
- action started, succeeded, and failed

Events from a cancelled or superseded generation must not affect the current
session.

## Session invariants

Reliable voice depends more on lifecycle discipline than on a happy-path API.
The initial implementation must enforce these rules:

1. **One owner.** Only the current session generation can publish state or
   dispatch a command. Late async work from an older generation is ignored.
2. **Gate immediately.** Releasing push-to-talk closes audio input
   synchronously, before waiting for a provider flush. Speech after release is
   never appended to that utterance.
3. **Keep the tail.** Audio accepted before the gate closes is allowed to reach
   a final transcript within a bounded flush window.
4. **Keep the head.** Capture may start while a provider warms or connects, but
   the pre-roll buffer is bounded and drained in order with backpressure.
5. **Finalize once.** Concurrent finalization requests share one operation and
   cannot dispatch the utterance twice.
6. **Stop safely.** Stop is idempotent and cleans up a partially started
   session, including microphone tracks, subscriptions, timers, sockets,
   processes, and buffers.
7. **Show honest readiness.** An open stream is not necessarily real audio.
   Bluetooth inputs can emit silence while changing modes, so `captureLive`
   follows the first meaningful frame or a connector-native readiness signal.
8. **Bound every wait.** Startup, endpointing, finalization, and shutdown have
   explicit deadlines and typed outcomes.
9. **Never execute rejected speech.** A speaker-verification rejection can be
   shown to the user but never enters the command stream.
10. **Do not hear yourself.** Speech output gates recognition during playback
    and for a short provider-dependent echo tail.

## Capture modes

The same coordinator supports distinct interaction policies:

- **Tap to speak** starts a session and ends after an explicit stop or detected
  endpoint.
- **Hold to talk** opens while pressed, gates immediately on release, and waits
  only for the accepted tail.
- **Warm push to talk** parks a muted session briefly after release so the next
  press does not reacquire a Bluetooth microphone or reload a model.
- **Hands free** listens for one utterance, combines finals separated by short
  pauses, dispatches once, and then stops or deliberately rearms.
- **Wake phrase** activates capture through a replaceable detector; wake-word
  parsing is not embedded in the core runtime.

Mode policy controls timing, while connectors and providers stay mode-neutral.

## Endpointing and transcript assembly

Providers disagree about partials, finals, silence, and stream closure. Murmur
normalizes those differences:

- partial text is replaceable presentation state
- final chunks are ordered and append-only within an utterance
- adjacent final chunks may be coalesced across a short silence window
- an explicit `muted(flushing: false)` can finish immediately
- a flush deadline prevents a missing provider event from hanging the session
- empty finals are valid outcomes and do not become actions

Timing values are policy configuration with conservative defaults, not magic
constants in UI code.

## Provider selection and fallback

Users choose a processing policy such as `offline`, `online`, or a specific
adapter when exposed by the host. A resolver maps that preference plus runtime
capabilities to an implementation.

Selection must:

- fail private/local when persisted settings are malformed
- never make a cloud provider available only because an entitlement or
  credential check is slow
- keep the user preference separate from today's concrete vendor
- fall back per session when an optional optimized engine cannot start
- pin the chosen engine for the life of the session so audio and stop calls
  cannot route to different implementations

Provider credentials enter through a secret boundary and never appear in
events, connector metadata, or diagnostics.

## On-device model packs

Offline recognition often needs several components—recognition, voice activity
detection, speech output, or optional speaker models. Murmur should expose one
atomic pack manager instead of making each screen infer readiness.

- `ready` means every component required on this platform is installed,
  verified, and loadable
- partial component state is diagnostic, not permission to start the pack
- preparation is single-flight and safe to call repeatedly
- retry invalidates the affected artifact before preparing again
- automatic repair is classified, bounded, and never loops forever
- download and extraction include disk-space headroom and exact progress when
  available
- the on-disk schema is versioned, and a valid warm relaunch avoids needless
  preparation
- unsupported components are explicit rather than reported as ready

Individual engine adapters remain responsible for their upstream licenses,
model terms, supported platforms, and redistribution rules.

## Speech feedback and interruption

Voice is an eyes-free interface only when it can acknowledge what happened.
Murmur therefore treats text-to-speech and short earcons as output capabilities,
not as assumptions of the transcription provider.

Spoken feedback should be brief, cancellable, and single-flight. Recognition is
half-duplex by default: microphone frames are gated while speech plays and for
an echo-clearance tail. A native engine that owns both input and output can do
this at the source; browser or cloud capture needs the same protection in the
runtime. Every output path has a watchdog so a missing playback callback cannot
leave capture permanently muted.

## Intent and action boundary

Speech-to-text and command execution are separate layers. A host may pass a
final utterance plus a bounded state snapshot to an intent adapter, which can
return either a clarification request or an ordered proposal of typed actions.

Only an allowlisted executor can run those actions. Destructive or sensitive
operations require a code-enforced confirmation. A model never receives a raw
shell or arbitrary-code execution path merely because input arrived by voice.
The same action registry should serve touch, text, gaze, and voice so each
modality receives the same permissions and behavior.

## Privacy-safe diagnostics

Voice logs are useful for lifecycle failures and unusually risky for users.
Default diagnostics may include timings, state transitions, provider IDs,
error codes, frame counts, byte counts, and transcript lengths. They must not
include transcript text, audio, credentials, device identifiers, signed URLs,
or generated replies that quote the user.

Tests should scan logging call sites and fixtures to keep this invariant from
regressing.

## What remains host-specific

- product-specific canvas commands, prompts, state snapshots, and tool names
- subscription, trial, entitlement, and usage-metering policy
- private services, endpoints, analytics, and account identifiers
- host UI components, IPC names, and application state
- native engines or model assets whose licenses and redistribution terms have
  not been reviewed for Murmur
- constants tuned to one product without a public configuration and test basis

Murmur can define adapters for these capabilities without making any one
implementation part of its Apache-licensed core.

## Implementation sequence

1. Extend `murmur.v1` and the shared fixtures only when a missing wire concept is
   proven; keep framework-specific state out of the schema.
2. Implement the provider and capture-state contracts in the first SDK without
   changing their cross-language semantics.
3. Build a deterministic fake provider that can delay startup, emit partials,
   deliver late finals, reject a final, fail, and disconnect.
4. Implement the capture coordinator and its race-condition test matrix.
5. Connect phone microphone and Omi audio through the same session boundary.
6. Add provider selection, graceful fallback, and BYOK credential injection.
7. Add the atomic on-device model-pack manager.
8. Add speech feedback and echo-loop protection.
9. Add typed intent proposals and the confirmation boundary.

Each stage should be useful and reviewable without waiting for the entire stack.
