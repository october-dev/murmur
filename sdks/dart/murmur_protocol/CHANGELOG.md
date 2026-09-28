## Unreleased

- Add typed audio formats and session commands with presence-preserving
  ProtoJSON serialization.
- Add framework-neutral voice connector, session, state, and error interfaces.
- Support protocol 1.1: add `EngineEvent` and typed `EngineControl` for engine,
  voice-pack, microphone, and speech-output contracts; add the provider,
  input-gate, wake-phrase, and batch-progress runtime payloads; add
  `SetSpeakerVerification`, `StartBatchTranscription`, and
  `StartSession.engineId`; validate transcript word timings and
  speaker-verification results. Exhaustive switches over `SessionCommand` or
  `RuntimePayloadKind` must handle the new cases.

## 0.1.0

- Add versioned protocol, runtime-event, and voice-source models.
- Add shared ProtoJSON conformance coverage.
- Expand conformance coverage for sessions, audio frames, and source discovery;
  RuntimeEvent uint64 fields now use `BigInt`, and protocol support is major-only.
