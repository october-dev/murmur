## Unreleased

- Add typed audio formats and session commands with presence-preserving
  ProtoJSON serialization.
- Add framework-neutral voice connector, session, state, and error interfaces.
- Add the `VoiceProvider` recognition contract and the `VoiceCaptureCoordinator`,
  the single owner of a capture generation, with bounded waits on an injected
  `Scheduler` and shared lifecycle scenario fixtures in `conformance/`.
- Preserve both utterances across rapid warm re-holds and cancel obsolete
  flush deadlines.
- Add idempotent coordinator `dispose()` and per-generation
  `CaptureSnapshot.droppedFrames` reporting.
- Surface provider control failures and fail promptly when the source stops
  during startup. Document `stop()` failures during terminal finalization.
- Report utterance callback exceptions to the delivery zone consistently,
  without treating them as provider failures or swallowing them on finalize.

## 0.1.0

- Add versioned protocol, runtime-event, and voice-source models.
- Add shared ProtoJSON conformance coverage.
- Expand conformance coverage for sessions, audio frames, and source discovery;
  RuntimeEvent uint64 fields now use `BigInt`, and protocol support is major-only.
